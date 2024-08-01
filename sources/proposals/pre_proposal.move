module generis_dao::pre_proposal;

use generis_dao::vote_type::{Self, VoteType};
use std::string::String;
use sui::linked_table::{Self, LinkedTable};

// === Structs ===

public struct PreProposal has key, store {
    id: UID,
    /// The user who created the proposal
    proposer: address,
    /// The name of the {PreProposal}.
    name: String,
    /// The description of the {PreProposal}.
    description: String,
    /// Vote Types
    vote_types: LinkedTable<ID, VoteType>,
}

// === Public-Mutative Functions ===

public(package) fun new(
    name: String,
    description: String,
    vote_types: vector<String>,
    ctx: &mut TxContext,
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
        let vote_type = vote_type::new(
            vote_types.pop_back(),
            proposal_id,
            0,
            ctx,
        );

        let vote_type_id = object::id(&vote_type);

        pre_proposal.vote_types.push_back(vote_type_id, vote_type);
    };

    pre_proposal
}

public(package) fun destruct_and_new(
    pre_proposal: PreProposal,
    ctx: &mut TxContext,
): PreProposal {
    let PreProposal {
        id,
        proposer,
        name,
        description,
        vote_types,
    } = pre_proposal;
    object::delete(id);

    PreProposal {
        id: object::new(ctx),
        proposer,
        name,
        description,
        vote_types,
    }
}

public(package) fun destruct(pre_proposal: PreProposal) {
    let PreProposal {
        id,
        mut vote_types,
        ..,
    } = pre_proposal;

    while (vote_types.length() > 0) {
        let (_, vote_type) = vote_types.pop_back();
        vote_type.destruct();
    };

    vote_types.destroy_empty();

    object::delete(id);
}

public(package) fun mut_vote_types(
    pre_proposal: &mut PreProposal,
): &mut LinkedTable<ID, VoteType> {
    &mut pre_proposal.vote_types
}

// === Public-View Functions ===

public fun proposer(pre_proposal: &PreProposal): address {
    pre_proposal.proposer
}

public fun name(pre_proposal: &PreProposal): String {
    pre_proposal.name
}

public fun description(pre_proposal: &PreProposal): String {
    pre_proposal.description
}

public fun vote_types(pre_proposal: &PreProposal): &LinkedTable<ID, VoteType> {
    &pre_proposal.vote_types
}
