module generis_dao::dao {
    // === Imports ===
    use generis_dao::reward_pool::{Self, RewardPool};
    use generis_dao::dao_admin::{DaoAdmin, new};
    use sui::balance::Balance;
    use sui::object_bag::{Self, ObjectBag};
    use sui::coin::Coin;
    use sui::event::emit;
    use std::string::String;
    use std::type_name::{Self, TypeName};

    // === Errors ===

    // === Constants ===

    // === Structs ===

    public struct Vote<phantom T> has key, store {
        id: UID,
        /// The amount of Generis the user has used to vote for the {Proposal}.
        balance: Balance<T>,
        /// The `sui::object::ID` of the {Proposal}.
        proposal_id: ID,
        /// The `sui::object::ID` of the {VoteType}.
        vote_type_id: ID,
    }

    public struct VoteType has key, store {
        id: UID,
        /// The name of the {VoteType}.
        name: String,
        /// The `sui::object::ID` of the {Proposal}.
        proposal_id: ID,
    }

    public struct PreProposal has key, store {
        id: UID,
        /// The user who created the proposal
        proposer: address,
        /// The name of the {PreProposal}.
        name: String,
        /// The description of the {PreProposal}.
        description: String,
        /// Vote Types
        vote_types: ObjectBag,
    }

    public struct Proposal<phantom T> has key, store {
        id: UID,
        /// Proposal accepted by
        accepted_by: address,
        /// The {PreProposal} that the {Proposal} is based on.
        pre_proposal: PreProposal,
        /// The reward pool of the {Proposal}.
        reward_pool: Option<RewardPool<T>>,
        /// When the users can start voting
        start_time: u64,
        /// Users can no longer vote after the `end_time`.
        end_time: u64,
        // The CoinType of the {Vote}
        coin_type: TypeName
    }

    public struct CompletedProposal has key, store {
        id: UID,
        /// The {PreProposal} that the {Proposal} is based on.
        pre_proposal: PreProposal,
        /// End time of the proposal
        ended_at: u64,
        /// Approved {VoteType}
        approved_vote_type: VoteType,
    }

    public struct ProposalRegistry has key, store {
        id: UID,
        /// Completed {Proposal}s
        completed_proposals: ObjectBag,
        /// Active {Proposal}s
        active_proposals: ObjectBag,
        /// PreProposals
        pre_proposals: ObjectBag,
    }

    // === Events ===

    public struct PreProposalCreated has copy, drop {
        pre_proposal_id: ID,
        proposer: address,
        name: String,
        description: String,
    }

    public struct ProposalCreated has copy, drop {
        proposal_id: ID,
        accepted_by: address,
        pre_proposal_id: ID,
    }

    public struct ProposalCompleted has copy, drop {
        proposal_id: ID,
        pre_proposal_id: ID,
    }

    // === Init ===

    fun init(ctx: &mut TxContext) {
        transfer::public_share_object(
            ProposalRegistry {
                id: object::new(ctx),
                completed_proposals: object_bag::new(ctx),
                active_proposals: object_bag::new(ctx),
                pre_proposals: object_bag::new(ctx),
            }
        );

        transfer::public_transfer(
            new(ctx),
            ctx.sender()
        )
    }

    // === Public-Mutative Functions ===

    public entry fun create_pre_proposal(
        registry: &mut ProposalRegistry,
        name: String,
        description: String,
        vote_types: vector<String>,
        ctx: &mut TxContext
    ) {
        let pre_proposal = create_pre_proposal_(
            name,
            description,
            vote_types,
            ctx
        );

        emit(PreProposalCreated {
            pre_proposal_id: object::id(&pre_proposal),
            proposer: ctx.sender(),
            name: pre_proposal.name,
            description: pre_proposal.description,
        });

        object_bag::add(
            &mut registry.pre_proposals,
            object::id(&pre_proposal),
            pre_proposal
        );
    }

    public entry fun create_proposal<T>(
        _: &DaoAdmin,
        registry: &mut ProposalRegistry,
        name: String,
        description: String,
        vote_types: vector<String>,
        coin: Coin<T>,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext
    ) {
        let pre_proposal = create_pre_proposal_(
            name,
            description,
            vote_types,
            ctx
        );

        emit(PreProposalCreated {
            pre_proposal_id: object::id(&pre_proposal),
            proposer: ctx.sender(),
            name: pre_proposal.name,
            description: pre_proposal.description,
        });

        let proposal = approve_pre_proposal_(
            pre_proposal,
            coin,
            start_time,
            end_time,
            ctx
        );

        emit(ProposalCreated {
            proposal_id: object::id(&proposal),
            accepted_by: ctx.sender(),
            pre_proposal_id: object::id(&proposal.pre_proposal),
        });

        object_bag::add(
            &mut registry.active_proposals,
            object::id(&proposal),
            proposal
        );
    }

    public entry fun approve_pre_proposal<T>(
        _: &DaoAdmin,
        registry: &mut ProposalRegistry,
        pre_proposal_id: ID,
        coin: Coin<T>,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext
    ) {
        let pre_proposal = object_bag::remove(&mut registry.pre_proposals, pre_proposal_id);

        let proposal = approve_pre_proposal_(
            pre_proposal,
            coin,
            start_time,
            end_time,
            ctx
        );

        emit(ProposalCreated {
            proposal_id: object::id(&proposal),
            accepted_by: ctx.sender(),
            pre_proposal_id: object::id(&proposal.pre_proposal),
        });

        object_bag::add(
            &mut registry.active_proposals,
            object::id(&proposal),
            proposal
        );
    }

    // === Public-View Functions ===

    // === Admin Functions ===

    // === Public-Package Functions ===

    // === Private Functions ===

    fun create_pre_proposal_(
        name: String,
        description: String,
        vote_types: vector<String>,
        ctx: &mut TxContext
    ): PreProposal {
        let mut pre_proposal = PreProposal {
            id: object::new(ctx),
            proposer: ctx.sender(),
            name: name,
            description: description,
            vote_types: object_bag::new(ctx),
        };

        let proposal_id = object::id(&pre_proposal);
        let mut vote_types = vote_types;

        while (vote_types.length() > 0) {
            let vote_type = VoteType {
                id: object::new(ctx),
                name: vote_types.pop_back(),
                proposal_id,
            };

            let vote_type_id = object::id(&vote_type);

            object_bag::add(&mut pre_proposal.vote_types, vote_type_id, vote_type);
        };

        pre_proposal
    }

    fun approve_pre_proposal_<T>(
        pre_proposal: PreProposal,
        coin: Coin<T>,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext
    ): Proposal<T> {
        let proposal = Proposal {
            id: object::new(ctx),
            accepted_by: ctx.sender(),
            pre_proposal: pre_proposal,
            reward_pool: option::some(reward_pool::new(coin, ctx)),
            start_time,
            end_time,
            coin_type: type_name::get<T>(),
        };

        proposal
    }

    // === Test Functions ===

}