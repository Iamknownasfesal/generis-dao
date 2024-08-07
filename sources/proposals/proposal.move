module generis_dao::proposal;

use generis_dao::{
    config::ProposalConfig,
    display_wrapper,
    pre_proposal::PreProposal,
    reward_pool::{Self, RewardPool},
    vote::Vote,
    vote_type::VoteTypeClone
};
use std::{string::{utf8, String}, type_name::{Self, TypeName}};
use sui::{coin::Coin, display, linked_table::{Self, LinkedTable}};

// === Structs ===

public struct Proposal<phantom RewardCoin, phantom VoteCoin> has key, store {
    id: UID,
    /// Proposal number
    number: u64,
    /// Name of the proposal
    name: String,
    /// Description of the proposal
    description: String,
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

// === Public-Mutative Functions ===

#[allow(lint(share_owned))]
public(package) fun new<RewardCoin, VoteCoin>(
    config: &ProposalConfig,
    pre_proposal: PreProposal,
    reward_coin: Coin<RewardCoin>,
    start_time: u64,
    end_time: u64,
    ctx: &mut TxContext,
): Proposal<RewardCoin, VoteCoin> {
    let reward_pool = if (reward_coin.value() > 0) {
        option::some(reward_pool::new(reward_coin, ctx))
    } else {
        reward_coin.destroy_zero();
        option::none()
    };

    let proposal = Proposal<RewardCoin, VoteCoin> {
        id: object::new(ctx),
        number: config.proposal_index(),
        name: pre_proposal.name(),
        description: pre_proposal.description(),
        accepted_by: ctx.sender(),
        pre_proposal,
        reward_pool,
        start_time,
        end_time,
        votes: linked_table::new(ctx),
        total_vote_value: 0,
        reward_coin_type: type_name::get<RewardCoin>(),
        vote_coin_type: type_name::get<VoteCoin>(),
    };

    let mut display = display::new<Proposal<RewardCoin, VoteCoin>>(
        config.publisher(),
        ctx,
    );

    display.add(utf8(b"name"), utf8(b"Sui Generis Proposal | {name}"));
    display.add(
        utf8(b"description"),
        utf8(b"{description}"),
    );
    display.add(
        utf8(b"image_url"),
        utf8(b"https://dao.suigeneris.auction/proposal/image/{id}?type=active"),
    );
    display.add(
        utf8(b"index"),
        utf8(b"{number}"),
    );
    display.update_version();

    transfer::public_share_object(display_wrapper::new(display, ctx));

    proposal
}

public(package) fun extend_time<RewardCoin, VoteCoin>(
    proposal: &mut Proposal<RewardCoin, VoteCoin>,
    end_time: u64,
) {
    proposal.end_time = end_time;
}

public(package) fun add_vote_value<RewardCoin, VoteCoin>(
    proposal: &mut Proposal<RewardCoin, VoteCoin>,
    value: u64,
) {
    proposal.total_vote_value = proposal.total_vote_value + value;
}

public(package) fun destroy<RewardCoin, VoteCoin>(
    proposal: Proposal<RewardCoin, VoteCoin>,
): (
    u64,
    PreProposal,
    address,
    Option<RewardPool<RewardCoin>>,
    LinkedTable<address, Vote<VoteCoin>>,
    u64,
    u64,
) {
    let Proposal {
        id,
        number,
        pre_proposal,
        accepted_by,
        reward_pool,
        votes,
        total_vote_value,
        start_time,
        ..,
    } = proposal;

    object::delete(id);

    return (
        number,
        pre_proposal,
        accepted_by,
        reward_pool,
        votes,
        total_vote_value,
        start_time,
    )
}

public(package) fun mut_pre_proposal<RewardCoin, VoteCoin>(
    proposal: &mut Proposal<RewardCoin, VoteCoin>,
): &mut PreProposal {
    &mut proposal.pre_proposal
}

public(package) fun mut_votes<RewardCoin, VoteCoin>(
    proposal: &mut Proposal<RewardCoin, VoteCoin>,
): &mut LinkedTable<address, Vote<VoteCoin>> {
    &mut proposal.votes
}

public(package) fun mut_reward_pool<RewardCoin, VoteCoin>(
    proposal: &mut Proposal<RewardCoin, VoteCoin>,
): &mut Option<RewardPool<RewardCoin>> {
    &mut proposal.reward_pool
}

// === Public-View Functions ===

public fun accepted_by<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): address {
    proposal.accepted_by
}

public fun pre_proposal<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): &PreProposal {
    &proposal.pre_proposal
}

public fun start_time<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): u64 {
    proposal.start_time
}

public fun end_time<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): u64 {
    proposal.end_time
}

public fun total_vote_value<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): u64 {
    proposal.total_vote_value
}

public fun reward_coin_type<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): TypeName {
    proposal.reward_coin_type
}

public fun vote_coin_type<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): TypeName {
    proposal.vote_coin_type
}

public fun votes<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): &LinkedTable<address, Vote<VoteCoin>> {
    &proposal.votes
}

public fun vec_vote_ids<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): vector<ID> {
    let mut vec_vote_ids = vector::empty<ID>();
    let mut id = proposal.votes.back();

    while (id.is_some()) {
        let vote: &Vote<VoteCoin> = proposal.votes.borrow(*id.borrow());
        vec_vote_ids.push_back(object::id(vote));

        id = proposal.votes.prev(*id.borrow());
    };

    vec_vote_ids
}

public fun did_user_vote_if_where<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
    ctx: &mut TxContext,
): (bool, Option<ID>) {
    let mut id = proposal.votes.back();

    while (id.is_some()) {
        if (*id.borrow() == ctx.sender()) {
            return (
                true,
                option::some(proposal
                    .votes
                    .borrow(*id.borrow())
                    .vote_type_id()),
            )
        };

        id = proposal.votes.prev(*id.borrow());
    };

    (false, option::none())
}

public fun vote_length<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): u64 {
    proposal.votes.length()
}

public fun reward_pool<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): &Option<RewardPool<RewardCoin>> {
    &proposal.reward_pool
}

public fun vec_vote_types<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): vector<VoteTypeClone> {
    proposal.pre_proposal().vec_vote_types()
}

public fun number<RewardCoin, VoteCoin>(
    proposal: &Proposal<RewardCoin, VoteCoin>,
): u64 {
    proposal.number
}
