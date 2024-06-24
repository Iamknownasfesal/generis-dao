module generis_dao::dao {
    // === Imports ===
    use generis_dao::reward_pool::{Self, RewardPool};
    use generis_dao::dao_admin::{DaoAdmin, new};
    use generis::generis::{GENERIS};
    use sui::balance::Balance;
    use sui::object_bag::{Self, ObjectBag};
    use sui::linked_table::{Self, LinkedTable};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::event::emit;
    use std::type_name::{Self, TypeName};
    use std::string::String;
    // === Errors ===

    /// The user cannot vote with a zero coin value.
    const ECannotVoteWithZeroCoinValue: u64 = 0;
    /// The user cannot vote after the `end_time`.
    const ETooLateToVote: u64 = 1;
    /// The user cannot vote before the `start_time`.
    const ETooSoonToVote: u64 = 2;
    /// The proposal does not exist.
    const EProposalDoesNotExist: u64 = 3;
    /// {VoteCoinype} does not exist.
    const EVoteCoinypeDoesNotExist: u64 = 4;
    /// Already voted, cannot vote different {VoteCoinype}.
    const ECannotVoteDifferentVoteCoinype: u64 = 5;
    /// The proposal cannot yet be completed.
    const EProposalCannotBeCompletedYet: u64 = 6;
    /// {VoteType} cannot be {None}
    const EVoteTypeCannotBeNone: u64 = 7;
    /// Not enough Generis to create a proposal.
    const ENotEnoughGenerisToCreateProposal: u64 = 8;
    /// There is still rewards in the reward pool.
    const ECannotDeleteProposalWithRewards: u64 = 9;

    // === Constants ===

    // === Structs ===

    public struct Vote<phantom RewardCoin> has key, store {
        id: UID,
        /// The amount of Generis the user has used to vote for the {Proposal}.
        balance: Balance<RewardCoin>,
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
        /// Total vote value
        total_vote_value: u64,
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
        vote_types: LinkedTable<ID, VoteType>
    }

    public struct Proposal<phantom RewardCoin, phantom VoteCoin> has key, store {
        id: UID,
        /// Proposal accepted by
        accepted_by: address,
        /// The {PreProposal} that the {Proposal} is based on.
        pre_proposal: PreProposal,
        /// The reward pool of the {Proposal}.
        reward_pool: Option<RewardPool<RewardCoin>>,
        /// When the users can start voting
        start_time: u64,
        /// Users can no longer vote after the `end_time`.
        end_time: u64,
        /// Total vote value
        total_vote_value: u64,
        // Votes casted for the {Proposal}
        votes: LinkedTable<address, Vote<VoteCoin>>,
        // RewardCoin type name
        reward_coin_type: TypeName,
        // VoteCoin type name
        vote_coin_type: TypeName,
    }

    public struct CompletedProposal has key, store {
        id: UID,
        /// The {PreProposal} that the {Proposal} is based on.
        pre_proposal: PreProposal,
        /// End time of the proposal
        ended_at: u64,
        /// Approved {VoteType}
        approved_vote_type: VoteType,
        /// Proposal accepted by
        accepted_by: address,
        /// How much total votes has been casted
        total_vote_value: u64,
    }

    public struct ProposalRegistry has key, store {
        id: UID,
        /// Completed {Proposal}s
        completed_proposals: ObjectBag,
        /// Active {Proposal}s
        active_proposals: ObjectBag,
        /// Pre {Proposal}s
        pre_proposals: ObjectBag,
    }

    public struct ProposalConfig has key, store {
        id: UID,
        /// The minimum amount of Generis that a user needs to pay to create a {PreProposal}. This will send to the wallet of the {DaoReceiver}.
        min_generis_to_create_proposal: u64,
        /// The DAO Receiver address
        dao_receiver: address,
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
        completed_proposal_id: ID,
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
        );

        transfer::public_share_object(
            ProposalConfig {
                id: object::new(ctx),
                min_generis_to_create_proposal: 100_000_000_000,
                dao_receiver: @dao,
            }
        )
    }

    // === Public-Mutative Functions ===

    public fun create_pre_proposal(
        config: &ProposalConfig,
        registry: &mut ProposalRegistry,
        generis_in: Coin<GENERIS>,
        name: String,
        description: String,
        vote_types: vector<String>,
        ctx: &mut TxContext
    ): ID {
        assert!(generis_in.value() >= config.min_generis_to_create_proposal, ENotEnoughGenerisToCreateProposal);
        transfer::public_transfer(
            generis_in,
            config.dao_receiver
        );

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

        let pre_proposal_id = object::id(&pre_proposal);

        registry.pre_proposals.add(
            pre_proposal_id,
            pre_proposal
        );

        pre_proposal_id
    }

    public fun create_proposal<RewardCoin, VoteCoin>(
        _: &DaoAdmin,
        registry: &mut ProposalRegistry,
        name: String,
        description: String,
        vote_types: vector<String>,
        reward_coin: Coin<RewardCoin>,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext
    ): ID {
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

        let proposal = approve_pre_proposal_<RewardCoin, VoteCoin>(
            pre_proposal,
            reward_coin,
            start_time,
            end_time,
            ctx
        );

        let proposal_id = object::id(&proposal);

        emit(ProposalCreated {
            proposal_id,
            accepted_by: ctx.sender(),
            pre_proposal_id: object::id(&proposal.pre_proposal),
        });

        registry.active_proposals.add(
            proposal_id,
            proposal
        );

        proposal_id
    }

    public fun approve_pre_proposal<RewardCoin, VoteCoin>(
        _: &DaoAdmin,
        registry: &mut ProposalRegistry,
        pre_proposal_id: ID,
        reward_coin: Coin<RewardCoin>,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext
    ): ID {
        assert!(registry.pre_proposals.contains(pre_proposal_id), EProposalDoesNotExist);
        let pre_proposal = registry.pre_proposals.remove(pre_proposal_id);

        let proposal = approve_pre_proposal_<RewardCoin, VoteCoin>(
            pre_proposal,
            reward_coin,
            start_time,
            end_time,
            ctx
        );

        let proposal_id = object::id(&proposal);

        emit(ProposalCreated {
            proposal_id,
            accepted_by: ctx.sender(),
            pre_proposal_id: object::id(&proposal.pre_proposal),
        });

        registry.active_proposals.add(
            proposal_id,
            proposal
        );

        proposal_id
    }

    public fun vote<RewardCoin, VoteCoin>(
        registry: &mut ProposalRegistry,
        clock: &Clock,
        proposal_id: ID,
        vote_type_id: ID,
        vote_coin: Coin<VoteCoin>,
        ctx: &mut TxContext
    ) {
        assert!(registry.active_proposals.contains(proposal_id), EProposalDoesNotExist);
        let value = vote_coin.value();
        assert!(value > 0, ECannotVoteWithZeroCoinValue);

        let proposal: &mut Proposal<RewardCoin, VoteCoin> = registry.active_proposals.borrow_mut(proposal_id);

        assert!(clock.timestamp_ms() >= proposal.start_time, ETooSoonToVote);
        assert!(clock.timestamp_ms() <= proposal.end_time, ETooLateToVote);
        assert!(proposal.pre_proposal.vote_types.contains(vote_type_id), EVoteCoinypeDoesNotExist);

        if (proposal.votes.contains(ctx.sender())) {
            let vote: &mut Vote<VoteCoin> = proposal.votes.borrow_mut(ctx.sender());

            assert!(vote.vote_type_id == vote_type_id, ECannotVoteDifferentVoteCoinype);

            vote.balance.join(vote_coin.into_balance());
        } else {
            let vote = Vote {
                id: object::new(ctx),
                balance: vote_coin.into_balance(),
                proposal_id,
                vote_type_id,
            };

            proposal.votes.push_back(ctx.sender(), vote);
        };

        proposal.total_vote_value = proposal.total_vote_value + value;

        let vote_type: &mut VoteType = proposal.pre_proposal.vote_types.borrow_mut(vote_type_id);
        vote_type.total_vote_value = vote_type.total_vote_value + value;
    }

    public fun complete<RewardCoin, VoteCoin>(
        _: &DaoAdmin,
        clock: &Clock,
        registry: &mut ProposalRegistry,
        proposal_id: ID,
        ctx: &mut TxContext
    ): ID {
        assert!(registry.active_proposals.contains(proposal_id), EProposalDoesNotExist);
        let mut proposal: Proposal<RewardCoin, VoteCoin> = registry.active_proposals.remove(proposal_id);
        assert!(clock.timestamp_ms() >= proposal.end_time, EProposalCannotBeCompletedYet);

        let mut max_vote_value = 0;
        let mut approved_vote_type: Option<ID> = option::none();
        let mut id = proposal.pre_proposal.vote_types.back();

        while (id.is_some()) {
            let vote_type: &VoteType = proposal.pre_proposal.vote_types.borrow(*id.borrow());

            if (vote_type.total_vote_value > max_vote_value) {
                max_vote_value = vote_type.total_vote_value;
                approved_vote_type = option::some(*id.borrow());
            };

            id = proposal.pre_proposal.vote_types.prev(*id.borrow());
        };

        assert!(approved_vote_type.is_some(), EVoteTypeCannotBeNone);

        let approved_vote_type = approved_vote_type.extract();
        share_incentive_pool_rewards(&mut proposal, ctx);

        let Proposal { id, pre_proposal, accepted_by, reward_pool, start_time: _, end_time: _, votes, total_vote_value, reward_coin_type: _, vote_coin_type: _ } = proposal;

        let mut pre_proposal = pre_proposal;
        let approved_vote_type: VoteType = pre_proposal.vote_types.remove(approved_vote_type);

        let completed_proposal = CompletedProposal {
            id: object::new(ctx),
            pre_proposal,
            ended_at: clock.timestamp_ms(),
            approved_vote_type,
            accepted_by: accepted_by,
            total_vote_value,
        };

        let completed_proposal_id = object::id(&completed_proposal);

        registry.completed_proposals.add(
            completed_proposal_id,
            completed_proposal
        );

        emit(ProposalCompleted {
            proposal_id: object::uid_to_inner(&id),
            completed_proposal_id,
        });

        object::delete(id);
        votes.destroy_empty();
        reward_pool.destroy_none();

        completed_proposal_id
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
            vote_types: linked_table::new(ctx),
        };

        let proposal_id = object::id(&pre_proposal);
        let mut vote_types = vote_types;

        while (vote_types.length() > 0) {
            let vote_type = VoteType {
                id: object::new(ctx),
                name: vote_types.pop_back(),
                proposal_id,
                total_vote_value: 0,
            };

            let vote_type_id = object::id(&vote_type);

            pre_proposal.vote_types.push_back(vote_type_id, vote_type);
        };

        pre_proposal
    }

    fun approve_pre_proposal_<RewardCoin, VoteCoin>(
        pre_proposal: PreProposal,
        reward_coin: Coin<RewardCoin>,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext
    ): Proposal<RewardCoin, VoteCoin> {
        let reward_pool = if (reward_coin.value() > 0) {
            option::some(reward_pool::new(reward_coin, ctx))
        } else {
            reward_coin.destroy_zero();
            option::none()
        };

        let proposal = Proposal {
            id: object::new(ctx),
            accepted_by: ctx.sender(),
            pre_proposal: pre_proposal,
            reward_pool,
            start_time,
            end_time,
            votes: linked_table::new(ctx),
            total_vote_value: 0,
            reward_coin_type: type_name::get<RewardCoin>(),
            vote_coin_type: type_name::get<VoteCoin>(),
        };
        

        proposal
    }

    fun share_incentive_pool_rewards<RewardCoin, VoteCoin>(
        proposal: &mut Proposal<RewardCoin, VoteCoin>,
        ctx: &mut TxContext
    ) {
        let reward_pool: RewardPool<RewardCoin> = proposal.reward_pool.extract();
        let total_vote_value = proposal.total_vote_value as u128;
        let mut total_reward = reward_pool.value() as u128;
        let mut reward_coins = reward_pool.destroy(ctx);

        while (proposal.votes.length() > 0) {
            let (addr, vote) = proposal.votes.pop_front();
            let Vote<VoteCoin> { id, balance: vote_balance, proposal_id: _, vote_type_id: _ } = vote;
            let vote_value = vote_balance.value() as u128;
            let reward = (total_reward * vote_value) / total_vote_value;

            transfer::public_transfer(
                reward_coins.split(reward as u64, ctx),
                addr
            );

            transfer::public_transfer(coin::from_balance(vote_balance, ctx), addr);
            object::delete(id);

            total_reward = total_reward - reward;
        };

        // This will return anways if the total_reward is not zero, so if any math error happens, the reward will saved.
        assert!(reward_coins.value() == 0, ECannotDeleteProposalWithRewards);
        reward_coins.destroy_zero();
    }

    // === Test Functions ===

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}