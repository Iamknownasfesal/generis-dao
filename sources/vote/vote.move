module generis_dao::vote {
    use sui::balance::Balance;

    // === Structs ===

    public struct Vote<phantom VoteCoin> has key, store {
        id: UID,
        /// The amount of Generis the user has used to vote for the {Proposal}.
        balance: Balance<VoteCoin>,
        /// The `sui::object::ID` of the {Proposal}.
        proposal_id: ID,
        /// The `sui::object::ID` of the {VoteType}.
        vote_type_id: ID,
    }

    // === Public-Mutative Functions ===

    public(package) fun new<VoteCoin>(
        balance: Balance<VoteCoin>,
        proposal_id: ID,
        vote_type_id: ID,
        ctx: &mut TxContext,
    ): Vote<VoteCoin> {
        Vote { id: object::new(ctx), balance, proposal_id, vote_type_id }
    }

    public fun destroy<VoteCoin>(
        vote: Vote<VoteCoin>,
    ): (Balance<VoteCoin>, ID, ID) {
        let Vote { id, balance, proposal_id, vote_type_id } = vote;

        object::delete(id);

        (balance, proposal_id, vote_type_id)
    }

    public fun mut_balance<VoteCoin>(
        vote: &mut Vote<VoteCoin>,
    ): &mut Balance<VoteCoin> {
        &mut vote.balance
    }

    // === Public-View Functions ===

    public fun value<VoteCoin>(vote: &Vote<VoteCoin>): u64 {
        vote.balance.value()
    }

    public fun proposal_id<VoteCoin>(vote: &Vote<VoteCoin>): ID {
        vote.proposal_id
    }

    public fun vote_type_id<VoteCoin>(vote: &Vote<VoteCoin>): ID {
        vote.vote_type_id
    }

    public fun balance<VoteCoin>(vote: &Vote<VoteCoin>): &Balance<VoteCoin> {
        &vote.balance
    }
}
