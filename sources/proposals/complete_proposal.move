module generis_dao::completed_proposal {
    use generis_dao::{pre_proposal::PreProposal, vote_type::VoteType};

    // === Structs ===

    public struct CompletedProposal has key, store {
        id: UID,
        /// The proposal number
        number: u64,
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

    // === Public-Mutative Functions ===

    #[allow(lint(share_owned))]
    public(package) fun new(
        number: u64,
        pre_proposal: PreProposal,
        ended_at: u64,
        approved_vote_type: VoteType,
        accepted_by: address,
        total_vote_value: u64,
        ctx: &mut TxContext,
    ): CompletedProposal {
        let proposal = CompletedProposal {
            id: object::new(ctx),
            number,
            pre_proposal,
            ended_at,
            approved_vote_type,
            accepted_by,
            total_vote_value,
        };

        proposal
    }

    // === Public-View Functions ===

    public fun number(completed_proposal: &CompletedProposal): u64 {
        completed_proposal.number
    }

    public fun pre_proposal(
        completed_proposal: &CompletedProposal,
    ): &PreProposal {
        &completed_proposal.pre_proposal
    }

    public fun ended_at(completed_proposal: &CompletedProposal): u64 {
        completed_proposal.ended_at
    }

    public fun approved_vote_type(
        completed_proposal: &CompletedProposal,
    ): &VoteType {
        &completed_proposal.approved_vote_type
    }

    public fun accepted_by(completed_proposal: &CompletedProposal): address {
        completed_proposal.accepted_by
    }

    public fun total_vote_value(completed_proposal: &CompletedProposal): u64 {
        completed_proposal.total_vote_value
    }
}
