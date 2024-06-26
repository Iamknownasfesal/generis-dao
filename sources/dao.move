module generis_dao::dao {
    // === Imports ===

    use generis_dao::reward_pool::RewardPool;
    use generis_dao::dao_admin::{Self, DaoAdmin};
    use generis_dao::config::{Self, ProposalConfig};
    use generis_dao::pre_proposal::{Self, PreProposal};
    use generis_dao::proposal::{Self, Proposal};
    use generis_dao::completed_proposal::{Self, CompletedProposal};
    use generis_dao::vote::{Self, Vote};
    use generis_dao::vote_type::{VoteType};
    use generis::generis::GENERIS;
    use sui::object_bag::{Self, ObjectBag};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::event::emit;
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
    const EVoteTypeDoesNotExist: u64 = 4;
    /// Already voted, cannot vote different {VoteCoinype}.
    const ECannotVoteDifferentVoteCoinType: u64 = 5;
    /// The proposal cannot yet be completed.
    const EProposalCannotBeCompletedYet: u64 = 6;
    /// {VoteType} cannot be {None}
    const EVoteTypeCannotBeNone: u64 = 7;
    /// Not enough Generis to create a proposal.
    const ENotEnoughGenerisToCreateProposal: u64 = 8;
    /// There is still rewards in the reward pool.
    const ECannotDeleteProposalWithRewards: u64 = 9;
    /// At least two vote types are required.
    const EAtLeastTwoVoteTypesAreRequired: u64 = 10;

    // === Constants ===

    const DEFAULT_PRE_PROPOSAL_FEES: u64 = 100_000_000_000;

    // === Structs ===

    public struct ProposalRegistry has key, store {
        id: UID,
        /// Completed {Proposal}s
        completed_proposals: ObjectBag,
        /// Active {Proposal}s
        active_proposals: ObjectBag,
        /// Pre {Proposal}s
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
        completed_proposal_id: ID,
    }

    // === Init ===

    #[lint_allow(share_owned)]
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
            dao_admin::new(ctx),
            ctx.sender()
        );

        transfer::public_share_object(
            config::new(DEFAULT_PRE_PROPOSAL_FEES, @dao, ctx)
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
        assert!(generis_in.value() >= config.fee(), ENotEnoughGenerisToCreateProposal);
        assert!(vote_types.length() >= 2, EAtLeastTwoVoteTypesAreRequired);
        transfer::public_transfer(
            generis_in,
            config.receiver()
        );

        let pre_proposal = pre_proposal::new(
            name,
            description,
            vote_types,
            ctx
        );

        emit(PreProposalCreated {
            pre_proposal_id: object::id(&pre_proposal),
            proposer: ctx.sender(),
            name: pre_proposal.name(),
            description: pre_proposal.description(),
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
        let pre_proposal = pre_proposal::new(
            name,
            description,
            vote_types,
            ctx
        );

        emit(PreProposalCreated {
            pre_proposal_id: object::id(&pre_proposal),
            proposer: ctx.sender(),
            name: pre_proposal.name(),
            description: pre_proposal.description()
        });

        let proposal = proposal::new<RewardCoin, VoteCoin>(
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
            pre_proposal_id: object::id(proposal.pre_proposal()),
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
        let pre_proposal: PreProposal = registry.pre_proposals.remove(pre_proposal_id);

        let proposal = proposal::new<RewardCoin, VoteCoin>(
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
            pre_proposal_id: object::id(proposal.pre_proposal()),
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
    ): ID {
        assert!(registry.active_proposals.contains(proposal_id), EProposalDoesNotExist);
        let value = vote_coin.value();
        assert!(value > 0, ECannotVoteWithZeroCoinValue);

        let proposal: &mut Proposal<RewardCoin, VoteCoin> = registry.active_proposals.borrow_mut(proposal_id);

        assert!(clock.timestamp_ms() >= proposal.start_time(), ETooSoonToVote);
        assert!(clock.timestamp_ms() <= proposal.end_time(), ETooLateToVote);
        assert!(proposal.pre_proposal().vote_types().contains(vote_type_id), EVoteTypeDoesNotExist);

        if (proposal.votes().contains(ctx.sender())) {
            let vote: &mut Vote<VoteCoin> = proposal.mut_votes().borrow_mut(ctx.sender());

            assert!(vote.vote_type_id() == vote_type_id, ECannotVoteDifferentVoteCoinType);

            vote.mut_balance().join(vote_coin.into_balance());
        } else {
            let vote = vote::new(
                vote_coin.into_balance(),
                proposal_id,
                vote_type_id,
                ctx
            );

            proposal.mut_votes().push_back(ctx.sender(), vote);
        };

        proposal.add_vote_value(value);

        let vote_type: &mut VoteType = proposal.mut_pre_proposal().mut_vote_types().borrow_mut(vote_type_id);
        vote_type.add_vote_value(value);

        object::id(proposal.votes().borrow(ctx.sender()))
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
        assert!(clock.timestamp_ms() >= proposal.end_time(), EProposalCannotBeCompletedYet);

        let mut max_vote_value = 0;
        let mut approved_vote_type: Option<ID> = option::none();
        let vote_types = proposal.pre_proposal().vote_types();
        let mut id = vote_types.back();

        while (id.is_some()) {
            let vote_type: &VoteType = vote_types.borrow(*id.borrow());

            if (vote_type.total_vote_value() > max_vote_value) {
                max_vote_value = vote_type.total_vote_value();
                approved_vote_type = option::some(*id.borrow());
            };

            id = vote_types.prev(*id.borrow());
        };

        assert!(approved_vote_type.is_some(), EVoteTypeCannotBeNone);

        let approved_vote_type = approved_vote_type.extract();
        share_incentive_pool_rewards(&mut proposal, ctx);

        let (pre_proposal, accepted_by, reward_pool, votes, total_vote_value) = proposal.destroy();

        let mut pre_proposal = pre_proposal;
        let approved_vote_type: VoteType = pre_proposal.mut_vote_types().remove(approved_vote_type);

        let completed_proposal = completed_proposal::new(
            pre_proposal,
            clock.timestamp_ms(),
            approved_vote_type,
            accepted_by,
            total_vote_value,
            ctx
        );

        let completed_proposal_id = object::id(&completed_proposal);

        registry.completed_proposals.add(
            completed_proposal_id,
            completed_proposal
        );

        emit(ProposalCompleted {
            proposal_id,
            completed_proposal_id,
        });

        votes.destroy_empty();
        reward_pool.destroy_none();

        completed_proposal_id
    }

    // === Private Functions ===

    fun share_incentive_pool_rewards<RewardCoin, VoteCoin>(
        proposal: &mut Proposal<RewardCoin, VoteCoin>,
        ctx: &mut TxContext
    ) {
        let reward_pool: RewardPool<RewardCoin> = proposal.mut_reward_pool().extract();
        let total_vote_value = proposal.total_vote_value() as u128;
        let total_reward = reward_pool.value() as u128;
        let mut reward_coins = reward_pool.destroy(ctx);

        while (proposal.votes().length() > 0) {
            let (addr, vote) = proposal.mut_votes().pop_front();
            let (vote_balance, _, _) = vote.destroy();
            let vote_value = vote_balance.value() as u128;
            let reward = (total_reward * vote_value) / total_vote_value;

            transfer::public_transfer(
                reward_coins.split(reward as u64, ctx),
                addr
            );

            transfer::public_transfer(coin::from_balance(vote_balance, ctx), addr);
        };

        // This will return anways if the total_reward is not zero, so if any math error happens, the reward will saved.
        assert!(reward_coins.value() == 0, ECannotDeleteProposalWithRewards);
        reward_coins.destroy_zero();
    }

    // === Public-View Functions ===

    public fun get_pre_proposal(registry: &ProposalRegistry, pre_proposal_id: ID): &PreProposal {
        registry.pre_proposals.borrow(pre_proposal_id)
    }

    public fun get_proposal<RewardCoin, VoteCoin>(registry: &ProposalRegistry, proposal_id: ID): &Proposal<RewardCoin, VoteCoin> {
        registry.active_proposals.borrow(proposal_id)
    }

    public fun get_completed_proposal(registry: &ProposalRegistry, completed_proposal_id: ID): &CompletedProposal {
        registry.completed_proposals.borrow(completed_proposal_id)
    }

    // === Test Functions ===

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}