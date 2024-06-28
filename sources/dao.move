module generis_dao::dao {
    use generis_dao::reward_pool::RewardPool;
    use generis_dao::dao_admin::{Self, DaoAdmin};
    use generis_dao::config::{Self, ProposalConfig};
    use generis_dao::pre_proposal::{Self, PreProposal};
    use generis_dao::proposal::{Self, Proposal};
    use generis_dao::completed_proposal;
    use generis_dao::proposal_registry::{Self, ProposalRegistry};
    use generis_dao::vote::{Self, Vote};
    use generis_dao::vote_type::{VoteType};
    use generis::generis::GENERIS;
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::event::emit;
    use std::string::String;

    // === Errors ===

    // Voting Errors
    /// The user cannot vote with a zero coin value.
    const ECannotVoteWithZeroCoinValue: u64 = 1;
    /// The user cannot vote after the `end_time`.
    const ETooLateToVote: u64 = 2;
    /// The user cannot vote before the `start_time`.
    const ETooSoonToVote: u64 = 3;
    /// Already voted, cannot vote different {VoteCoinType}.
    const ECannotVoteDifferentVoteCoinType: u64 = 4;
    /// {VoteType} cannot be {None}
    const EVoteTypeCannotBeNone: u64 = 5;

    // Proposal Errors
    /// Not enough Generis to create a proposal.
    const ENotEnoughGenerisToCreateProposal: u64 = 6;
    /// User should have more than the minimum amount of Generis to create a proposal.
    const EUserShouldHaveMoreThanMinimumGeneris: u64 = 7;
    /// The proposal cannot yet be completed.
    const EProposalCannotBeCompletedYet: u64 = 8;
    /// There is still rewards in the reward pool.
    const ECannotDeleteProposalWithRewards: u64 = 9;
    /// Cannot extend the proposal with an `end_time` smaller than the current `end_time`.
    const ECannotExtendProposalWithSmallerEndTime: u64 = 10;

    // Vote Type Errors
    /// {VoteType} does not exist.
    const EVoteTypeDoesNotExist: u64 = 11;
    /// At least two vote types are required.
    const EAtLeastTwoVoteTypesAreRequired: u64 = 12;

    // === Constants ===

    const DEFAULT_PRE_PROPOSAL_FEES: u64 = 100_000_000_000;
    const DEFAULT_PRE_PROPOSAL_MIN: u64 = 1_000_000_000_000;

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
        transfer::public_share_object(proposal_registry::new(ctx));

        transfer::public_transfer(
            dao_admin::new(ctx),
            ctx.sender(),
        );

        transfer::public_share_object(config::new(
            DEFAULT_PRE_PROPOSAL_FEES,
            @dao,
            DEFAULT_PRE_PROPOSAL_MIN,
            ctx,
        ))
    }

    // === Public-Mutative Functions ===

    #[lint_allow(share_owned)]
    public entry fun create_pre_proposal(
        config: &ProposalConfig,
        registry: &mut ProposalRegistry,
        generis_in: Coin<GENERIS>,
        name: String,
        description: String,
        vote_types: vector<String>,
        ctx: &mut TxContext,
    ) {
        assert!(generis_in.value() >= config.fee(), ENotEnoughGenerisToCreateProposal);
        assert!(
            generis_in.value() >= config.min_generis_to_create_proposal(),
            EUserShouldHaveMoreThanMinimumGeneris,
        );
        assert!(vote_types.length() >= 2, EAtLeastTwoVoteTypesAreRequired);
        let mut generis_in = generis_in;
        transfer::public_transfer(
            generis_in.split(config.fee(), ctx),
            config.receiver(),
        );

        transfer::public_transfer(
            generis_in,
            ctx.sender(),
        );

        let pre_proposal = pre_proposal::new(
            name,
            description,
            vote_types,
            ctx,
        );

        emit(PreProposalCreated {
            pre_proposal_id: object::id(&pre_proposal),
            proposer: ctx.sender(),
            name: pre_proposal.name(),
            description: pre_proposal.description(),
        });

        registry.add_pre_proposal(object::id(&pre_proposal));

        transfer::public_share_object(pre_proposal);
    }

    #[lint_allow(share_owned)]
    public entry fun create_proposal<RewardCoin, VoteCoin>(
        _: &DaoAdmin,
        registry: &mut ProposalRegistry,
        name: String,
        description: String,
        vote_types: vector<String>,
        reward_coin: Coin<RewardCoin>,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext,
    ) {
        let pre_proposal = pre_proposal::new(
            name,
            description,
            vote_types,
            ctx,
        );

        emit(PreProposalCreated {
            pre_proposal_id: object::id(&pre_proposal),
            proposer: ctx.sender(),
            name: pre_proposal.name(),
            description: pre_proposal.description(),
        });

        let proposal = proposal::new<RewardCoin, VoteCoin>(
            pre_proposal,
            reward_coin,
            start_time,
            end_time,
            ctx,
        );

        let proposal_id = object::id(&proposal);

        emit(ProposalCreated {
            proposal_id,
            accepted_by: ctx.sender(),
            pre_proposal_id: object::id(proposal.pre_proposal()),
        });

        registry.add_active_proposal(proposal_id);

        transfer::public_share_object(proposal);
    }

    #[lint_allow(share_owned)]
    public entry fun approve_pre_proposal<RewardCoin, VoteCoin>(
        _: &DaoAdmin,
        registry: &mut ProposalRegistry,
        pre_proposal: PreProposal,
        reward_coin: Coin<RewardCoin>,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext,
    ) {
        registry.remove_pre_proposal(object::id(&pre_proposal));

        let proposal = proposal::new<RewardCoin, VoteCoin>(
            pre_proposal,
            reward_coin,
            start_time,
            end_time,
            ctx,
        );

        let proposal_id = object::id(&proposal);

        emit(ProposalCreated {
            proposal_id,
            accepted_by: ctx.sender(),
            pre_proposal_id: object::id(proposal.pre_proposal()),
        });

        transfer::public_share_object(proposal);
        registry.add_active_proposal(proposal_id);
    }

    public fun vote<RewardCoin, VoteCoin>(
        proposal: &mut Proposal<RewardCoin, VoteCoin>,
        clock: &Clock,
        vote_type_id: ID,
        vote_coin: Coin<VoteCoin>,
        ctx: &mut TxContext,
    ): ID {
        let value = vote_coin.value();
        assert!(value > 0, ECannotVoteWithZeroCoinValue);

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
                object::id(proposal),
                vote_type_id,
                ctx,
            );

            proposal.mut_votes().push_back(ctx.sender(), vote);
        };

        proposal.add_vote_value(value);

        let vote_type: &mut VoteType = proposal
            .mut_pre_proposal()
            .mut_vote_types()
            .borrow_mut(vote_type_id);
        vote_type.add_vote_value(value);

        object::id(proposal.votes().borrow(ctx.sender()))
    }

    #[lint_allow(share_owned)]
    public entry fun complete<RewardCoin, VoteCoin>(
        _: &DaoAdmin,
        clock: &Clock,
        registry: &mut ProposalRegistry,
        proposal: Proposal<RewardCoin, VoteCoin>,
        ctx: &mut TxContext,
    ) {
        let proposal_id = object::id(&proposal);
        registry.remove_active_proposal(proposal_id);
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
        let mut proposal = proposal;
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
            ctx,
        );

        let completed_proposal_id = object::id(&completed_proposal);

        registry.add_completed_proposal(completed_proposal_id);

        emit(ProposalCompleted { proposal_id, completed_proposal_id });

        transfer::public_share_object(completed_proposal);
        votes.destroy_empty();
        reward_pool.destroy_none();
    }

    public entry fun extend_proposal<RewardCoin, VoteCoin>(
        _: &DaoAdmin,
        proposal: &mut Proposal<RewardCoin, VoteCoin>,
        end_time: u64,
    ) {
        assert!(end_time > proposal.end_time(), ECannotExtendProposalWithSmallerEndTime);
        proposal.extend_time(end_time);
    }

    // === Private Functions ===

    fun share_incentive_pool_rewards<RewardCoin, VoteCoin>(
        proposal: &mut Proposal<RewardCoin, VoteCoin>,
        ctx: &mut TxContext,
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
                addr,
            );

            transfer::public_transfer(coin::from_balance(vote_balance, ctx), addr);
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
