module generis_dao::proposal {
    // === Imports ===

    use generis_dao::reward_pool::{Self, RewardPool};
    use generis_dao::pre_proposal::{PreProposal};
    use generis_dao::vote::Vote;
    use sui::linked_table::{Self, LinkedTable};
    use sui::coin::Coin;
    use std::type_name::{Self, TypeName};

    // === Structs ===

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

    // === Public-Mutative Functions ===

    public(package) fun new<RewardCoin, VoteCoin>(
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

    public fun add_vote_value<RewardCoin, VoteCoin>(proposal: &mut Proposal<RewardCoin, VoteCoin>, value: u64) {
        proposal.total_vote_value = proposal.total_vote_value + value;
    }

    public fun destroy<RewardCoin, VoteCoin>(proposal: Proposal<RewardCoin, VoteCoin>): (PreProposal, address, Option<RewardPool<RewardCoin>>, LinkedTable<address, Vote<VoteCoin>>, u64) {
        let Proposal { id, pre_proposal, accepted_by, reward_pool, start_time: _, end_time: _, votes, total_vote_value, reward_coin_type: _, vote_coin_type: _ } = proposal;

        object::delete(id);

        return (
            pre_proposal,
            accepted_by,
            reward_pool,
            votes,
            total_vote_value,
        )
    }

    public fun mut_pre_proposal<RewardCoin, VoteCoin>(proposal: &mut Proposal<RewardCoin, VoteCoin>): &mut PreProposal {
        &mut proposal.pre_proposal
    }

    public fun mut_votes<RewardCoin, VoteCoin>(proposal: &mut Proposal<RewardCoin, VoteCoin>): &mut LinkedTable<address, Vote<VoteCoin>> {
        &mut proposal.votes
    }

    public fun mut_reward_pool<RewardCoin, VoteCoin>(proposal: &mut Proposal<RewardCoin, VoteCoin>): &mut Option<RewardPool<RewardCoin>> {
        &mut proposal.reward_pool
    }

    // === Public-View Functions ===

    public fun accepted_by<RewardCoin, VoteCoin>(proposal: &Proposal<RewardCoin, VoteCoin>): address {
        proposal.accepted_by
    }

    public fun pre_proposal<RewardCoin, VoteCoin>(proposal: &Proposal<RewardCoin, VoteCoin>): &PreProposal {
        &proposal.pre_proposal
    }

    public fun start_time<RewardCoin, VoteCoin>(proposal: &Proposal<RewardCoin, VoteCoin>): u64 {
        proposal.start_time
    }

    public fun end_time<RewardCoin, VoteCoin>(proposal: &Proposal<RewardCoin, VoteCoin>): u64 {
        proposal.end_time
    }

    public fun total_vote_value<RewardCoin, VoteCoin>(proposal: &Proposal<RewardCoin, VoteCoin>): u64 {
        proposal.total_vote_value
    }

    public fun reward_coin_type<RewardCoin, VoteCoin>(proposal: &Proposal<RewardCoin, VoteCoin>): TypeName {
        proposal.reward_coin_type
    }

    public fun vote_coin_type<RewardCoin, VoteCoin>(proposal: &Proposal<RewardCoin, VoteCoin>): TypeName {
        proposal.vote_coin_type
    }

    public fun votes<RewardCoin, VoteCoin>(proposal: &Proposal<RewardCoin, VoteCoin>): &LinkedTable<address, Vote<VoteCoin>> {
        &proposal.votes
    }

    public fun reward_pool<RewardCoin, VoteCoin>(proposal: &Proposal<RewardCoin, VoteCoin>): &Option<RewardPool<RewardCoin>> {
        &proposal.reward_pool
    }
}