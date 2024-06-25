module generis_dao::vote_type {
    // === Imports ===

    use std::string::String;

    // === Structs ===

    public struct VoteType has key, store {
        id: UID,
        /// The name of the {VoteType}.
        name: String,
        /// The `sui::object::ID` of the {Proposal}.
        proposal_id: ID,
        /// Total vote value
        total_vote_value: u64,
    }

    // === Public-Mutative Functions ===

    public(package) fun new(name: String, proposal_id: ID, total_vote_value: u64, ctx: &mut TxContext): VoteType {
        VoteType {
            id: object::new(ctx),
            name,
            proposal_id,
            total_vote_value,
        }
    }

    public fun add_vote_value(self: &mut VoteType, value: u64) {
        self.total_vote_value = self.total_vote_value + value;
    }

    // === Public-View Functions ===

    public fun name(self: &VoteType): String {
        self.name
    }

    public fun proposal_id(self: &VoteType): ID {
        self.proposal_id
    }

    public fun total_vote_value(self: &VoteType): u64 {
        self.total_vote_value
    }
}