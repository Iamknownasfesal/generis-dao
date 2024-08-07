module generis_dao::dao;

use generis::generis::GENERIS;
use generis_dao::{
    completed_proposal::{Self, CompletedProposal},
    config::{Self, ProposalConfig},
    dao_admin::{Self, DaoAdmin},
    display_wrapper,
    pre_proposal::{Self, PreProposal},
    proposal::{Self, Proposal},
    proposal_registry::{Self, ProposalRegistry},
    reward_pool::RewardPool,
    vote::{Self, Vote},
    vote_type::VoteType
};
use std::{string::{String, utf8}, type_name::{Self, TypeName}};
use sui::{
    clock::Clock,
    coin::{Self, Coin},
    display,
    event::emit,
    linked_table::LinkedTable,
    package
};

// === Errors ===

// Voting Errors

/// Invalid Payment Type
const EInvalidPaymentType: u64 = 0;
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
const ENotEnoughInToCreateProposal: u64 = 6;
/// User should have more than the minimum amount of Generis to create a proposal.
const EUserShouldHaveMoreThanMinimumIn: u64 = 7;
/// The proposal cannot yet be completed.
const EProposalCannotBeCompletedYet: u64 = 8;
/// Cannot extend the proposal with an `end_time` smaller than the current `end_time`.
const ECannotExtendProposalWithSmallerEndTime: u64 = 9;

// Vote Type Errors
/// {VoteType} does not exist.
const EVoteTypeDoesNotExist: u64 = 10;
/// At least two vote types are required.
const EAtLeastTwoVoteTypesAreRequired: u64 = 11;

/// Vote Config Errors
/// The user cannot vote without having minimum Generis.
const EUserShouldHaveMinimumGenerisToVote: u64 = 12;

// === Constants ===

const DEFAULT_PRE_PROPOSAL_FEES: u64 = 100_000_000_000;
const DEFAULT_PRE_PROPOSAL_MIN: u64 = 1_000_000_000_000;
const DEFAULT_MIN_VOTE_VALUE: u64 = 1_000_000_000;

// === Structs ===

public struct ExecutingProposal<
    phantom RewardCoin,
    phantom VoteCoin,
> has store, key {
    id: UID,
    linked_table: LinkedTable<address, Vote<VoteCoin>>,
    rewards: Option<RewardPool<RewardCoin>>,
    total_vote_value: u64,
    total_reward: Option<u64>,
}

/// == OTW ==

public struct DAO has drop {}

// === Events ===

public struct PreProposalCreated has copy, drop {
    pre_proposal_id: ID,
    proposer: address,
    name: String,
    description: String,
}

public struct PreProposalRejected has copy, drop {
    rejected_by: address,
    pre_proposal_id: ID,
}

public struct ProposalCreated has copy, drop {
    proposal_id: ID,
    accepted_by: address,
    pre_proposal_id: ID,
    index: u64,
}

public struct VoteEvent has copy, drop {
    proposal_id: ID,
    voter: address,
    vote_type_id: ID,
    vote_value: u64,
}

public struct ProposalCompleted has copy, drop {
    proposal_id: ID,
    completed_proposal_id: ID,
    index: u64,
}

public struct ExecutingProposalCreated has copy, drop {
    executing_proposal_id: ID,
    votes_length: u64,
    reward_type_name: TypeName,
    vote_type_name: TypeName,
}

// === Init ===

#[lint_allow(share_owned)]
fun init(otw: DAO, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    transfer::public_share_object(proposal_registry::new(ctx));

    let sender = ctx.sender();
    dao_admin::new(sender, ctx);
    transfer::public_transfer(dao_admin::new_dao_admin(ctx), sender);
    transfer::public_transfer(dao_admin::new_dao_admin(ctx), @dao_treasury);

    let mut display = display::new<PreProposal>(&publisher, ctx);
    display.add(utf8(b"name"), utf8(b"Sui Generis Pre-Proposal | {name}"));
    display.add(
        utf8(b"description"),
        utf8(b"{description}"),
    );
    display.add(
        utf8(b"image_url"),
        utf8(b"https://dao.suigeneris.auction/proposal/image/{id}?type=pre"),
    );
    display.update_version();

    transfer::public_share_object(display_wrapper::new(display, ctx));

    let mut display = display::new<CompletedProposal>(&publisher, ctx);
    display.add(
        utf8(b"name"),
        utf8(b"Sui Generis Completed Proposal | {name}"),
    );
    display.add(
        utf8(b"description"),
        utf8(b"{description}"),
    );
    display.add(
        utf8(b"image_url"),
        utf8(
            b"https://dao.suigeneris.auction/proposal/image/{id}?type=completed",
        ),
    );
    display.add(
        utf8(b"index"),
        utf8(b"{number}"),
    );
    display.update_version();

    transfer::public_share_object(display_wrapper::new(display, ctx));

    transfer::public_share_object(
        config::new<GENERIS>(
            DEFAULT_PRE_PROPOSAL_FEES,
            @dao_treasury,
            DEFAULT_PRE_PROPOSAL_MIN,
            DEFAULT_MIN_VOTE_VALUE,
            publisher,
            ctx,
        ),
    )
}

// === Public-Mutative Functions ===

#[lint_allow(share_owned)]
public entry fun create_pre_proposal<PaymentCoin>(
    config: &ProposalConfig,
    registry: &mut ProposalRegistry,
    in: Coin<PaymentCoin>,
    name: String,
    description: String,
    vote_types: vector<String>,
    ctx: &mut TxContext,
) {
    assert!(
        in.value() >= config.fee(),
        ENotEnoughInToCreateProposal,
    );
    assert!(
        in.value() >= config.min_in_to_create_proposal(),
        EUserShouldHaveMoreThanMinimumIn,
    );
    assert!(vote_types.length() >= 2, EAtLeastTwoVoteTypesAreRequired);
    assert!(
        type_name::get<PaymentCoin>() == config.payment_type(),
        EInvalidPaymentType,
    );
    let mut in = in;
    transfer::public_transfer(
        in.split(config.fee(), ctx),
        config.receiver(),
    );

    transfer::public_transfer(
        in,
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
    config: &mut ProposalConfig,
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
        config,
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
        index: proposal.number(),
    });

    config.proposal_created();
    registry.add_active_proposal(proposal_id);
    transfer::public_share_object(proposal);
}

#[lint_allow(share_owned)]
public entry fun approve_pre_proposal<RewardCoin, VoteCoin>(
    _: &DaoAdmin,
    config: &mut ProposalConfig,
    registry: &mut ProposalRegistry,
    pre_proposal: PreProposal,
    reward_coin: Coin<RewardCoin>,
    start_time: u64,
    end_time: u64,
    ctx: &mut TxContext,
) {
    registry.remove_pre_proposal(object::id(&pre_proposal));

    let proposal = proposal::new<RewardCoin, VoteCoin>(
        config,
        pre_proposal.destruct_and_new(ctx),
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
        index: proposal.number(),
    });

    config.proposal_created();
    transfer::public_share_object(proposal);
    registry.add_active_proposal(proposal_id);
}

public entry fun reject_pre_proposal(
    _: &DaoAdmin,
    registry: &mut ProposalRegistry,
    pre_proposal: PreProposal,
    ctx: &mut TxContext,
) {
    registry.remove_pre_proposal(object::id(&pre_proposal));
    let pre_proposal_id = object::id(&pre_proposal);

    pre_proposal.destruct();

    emit(PreProposalRejected {
        rejected_by: ctx.sender(),
        pre_proposal_id,
    });
}

public fun vote<RewardCoin, VoteCoin>(
    proposal: &mut Proposal<RewardCoin, VoteCoin>,
    config: &ProposalConfig,
    clock: &Clock,
    vote_type_id: ID,
    vote_coin: Coin<VoteCoin>,
    ctx: &mut TxContext,
): ID {
    let value = vote_coin.value();
    assert!(value > 0, ECannotVoteWithZeroCoinValue);
    assert!(
        value >= config.min_vote_value(),
        EUserShouldHaveMinimumGenerisToVote,
    );
    assert!(clock.timestamp_ms() >= proposal.start_time(), ETooSoonToVote);
    assert!(clock.timestamp_ms() <= proposal.end_time(), ETooLateToVote);
    assert!(
        proposal.pre_proposal().vote_types().contains(vote_type_id),
        EVoteTypeDoesNotExist,
    );

    if (proposal.votes().contains(ctx.sender())) {
        let vote: &mut Vote<VoteCoin> = proposal
            .mut_votes()
            .borrow_mut(ctx.sender());

        assert!(
            vote.vote_type_id() == vote_type_id,
            ECannotVoteDifferentVoteCoinType,
        );

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

    emit(VoteEvent {
        proposal_id: object::id(proposal),
        voter: ctx.sender(),
        vote_type_id,
        vote_value: value,
    });

    object::id(proposal.votes().borrow(ctx.sender()))
}

#[lint_allow(share_owned)]
public fun complete_proposal<RewardCoin, VoteCoin>(
    _: &DaoAdmin,
    clock: &Clock,
    registry: &mut ProposalRegistry,
    proposal: Proposal<RewardCoin, VoteCoin>,
    ctx: &mut TxContext,
): ExecutingProposal<RewardCoin, VoteCoin> {
    let proposal_id = object::id(&proposal);
    registry.remove_active_proposal(proposal_id);
    assert!(
        clock.timestamp_ms() >= proposal.end_time(),
        EProposalCannotBeCompletedYet,
    );

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

    let (
        number,
        pre_proposal,
        accepted_by,
        reward_pool,
        votes,
        total_vote_value,
        start_time,
    ) = proposal.destroy();

    let mut pre_proposal = pre_proposal;
    let approved_vote_type: VoteType = pre_proposal
        .mut_vote_types()
        .remove(approved_vote_type);

    let completed_proposal = completed_proposal::new(
        number,
        pre_proposal,
        start_time,
        clock.timestamp_ms(),
        approved_vote_type,
        accepted_by,
        total_vote_value,
        ctx,
    );

    let completed_proposal_id = object::id(&completed_proposal);

    registry.add_completed_proposal(completed_proposal_id);

    emit(ProposalCompleted {
        proposal_id,
        completed_proposal_id,
        index: number,
    });

    transfer::public_share_object(completed_proposal);

    let total_reward = if (reward_pool.is_some()) {
        option::some(reward_pool.borrow().value())
    } else {
        option::none()
    };

    let executing_proposal = ExecutingProposal {
        id: object::new(ctx),
        linked_table: votes,
        rewards: reward_pool,
        total_vote_value,
        total_reward,
    };

    emit(ExecutingProposalCreated {
        executing_proposal_id: object::id(&executing_proposal),
        votes_length: executing_proposal.linked_table.length(),
        reward_type_name: type_name::get<RewardCoin>(),
        vote_type_name: type_name::get<VoteCoin>(),
    });

    executing_proposal
}

public fun go_over_votes<RewardCoin, VoteCoin>(
    _: &DaoAdmin,
    executing_proposal: &mut ExecutingProposal<RewardCoin, VoteCoin>,
    go_over_times: u64,
    ctx: &mut TxContext,
) {
    let linked_table = &mut executing_proposal.linked_table;
    let total_vote_value = executing_proposal.total_vote_value;
    let total_reward = &mut executing_proposal.total_reward;
    let rewards = &mut executing_proposal.rewards;

    let reward_pool_available = rewards.is_some();
    let mut count = 0;

    while (linked_table.length() > 0) {
        let (addr, vote) = linked_table.pop_front();
        let (vote_balance, _, _) = vote.destroy();
        let vote_value = vote_balance.value();

        if (reward_pool_available) {
            transfer::public_transfer(
                rewards
                    .borrow_mut()
                    .split(
                        (
                            (
                                (*total_reward.borrow_mut() as u128) * (
                                    vote_value as u128,
                                ),
                            ) / (total_vote_value as u128),
                        ) as u64,
                        ctx,
                    ),
                addr,
            );
        };

        transfer::public_transfer(
            coin::from_balance(vote_balance, ctx),
            addr,
        );

        count = count + 1;

        if (count >= go_over_times) {
            break
        };
    };
}

public fun finish_go_over_votes<RewardCoin, VoteCoin>(
    _: &DaoAdmin,
    config: &ProposalConfig,
    executing_proposal: ExecutingProposal<RewardCoin, VoteCoin>,
    ctx: &mut TxContext,
) {
    let ExecutingProposal {
        id,
        linked_table,
        rewards,
        ..,
    } = executing_proposal;

    object::delete(id);
    linked_table.destroy_empty();

    let mut rewards = rewards;

    if (rewards.is_some()) {
        let reward_coin = rewards.extract().destroy(ctx);

        transfer::public_transfer(
            reward_coin,
            config.receiver(),
        );
    };

    rewards.destroy_none();
}

public entry fun extend_proposal<RewardCoin, VoteCoin>(
    _: &DaoAdmin,
    proposal: &mut Proposal<RewardCoin, VoteCoin>,
    end_time: u64,
) {
    assert!(
        end_time > proposal.end_time(),
        ECannotExtendProposalWithSmallerEndTime,
    );
    proposal.extend_time(end_time);
}

// === Public-View Functions for ExecutingProposal ===

public fun linked_table<RewardCoin, VoteCoin>(
    executing_proposal: &ExecutingProposal<RewardCoin, VoteCoin>,
): &LinkedTable<address, Vote<VoteCoin>> {
    &executing_proposal.linked_table
}

public fun linked_table_length<RewardCoin, VoteCoin>(
    executing_proposal: &ExecutingProposal<RewardCoin, VoteCoin>,
): u64 {
    executing_proposal.linked_table.length()
}

public fun rewards<RewardCoin, VoteCoin>(
    executing_proposal: &ExecutingProposal<RewardCoin, VoteCoin>,
): &Option<RewardPool<RewardCoin>> {
    &executing_proposal.rewards
}

public fun total_vote_value<RewardCoin, VoteCoin>(
    executing_proposal: &ExecutingProposal<RewardCoin, VoteCoin>,
): u64 {
    executing_proposal.total_vote_value
}

public fun total_reward<RewardCoin, VoteCoin>(
    executing_proposal: &ExecutingProposal<RewardCoin, VoteCoin>,
): Option<u64> {
    executing_proposal.total_reward
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(DAO {}, ctx);
}
