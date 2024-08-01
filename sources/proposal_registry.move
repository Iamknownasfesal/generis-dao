module generis_dao::proposal_registry;

use sui::table_vec::{Self, TableVec};

// === Structs ===

public struct ProposalRegistry has key, store {
    id: UID,
    /// Completed {Proposal}s
    completed_proposals: TableVec<ID>,
    /// Active {Proposal}s
    active_proposals: TableVec<ID>,
    /// Pre {Proposal}s
    pre_proposals: TableVec<ID>,
}

// === Public-Mutative Functions ===

public(package) fun new(ctx: &mut TxContext): ProposalRegistry {
    ProposalRegistry {
        id: object::new(ctx),
        completed_proposals: table_vec::empty(ctx),
        active_proposals: table_vec::empty(ctx),
        pre_proposals: table_vec::empty(ctx),
    }
}

public fun add_completed_proposal(self: &mut ProposalRegistry, id: ID) {
    self.completed_proposals.push_back(id)
}

public fun add_active_proposal(self: &mut ProposalRegistry, id: ID) {
    self.active_proposals.push_back(id)
}

public fun add_pre_proposal(self: &mut ProposalRegistry, id: ID) {
    self.pre_proposals.push_back(id)
}

public fun remove_completed_proposal(self: &mut ProposalRegistry, id: ID) {
    let index = self.find_completed_proposal(id).extract();
    self.completed_proposals.swap_remove(index);
}

public fun remove_active_proposal(self: &mut ProposalRegistry, id: ID) {
    let index = self.find_active_proposal(id).extract();
    self.active_proposals.swap_remove(index);
}

public fun remove_pre_proposal(self: &mut ProposalRegistry, id: ID) {
    let index = self.find_pre_proposal(id).extract();
    self.pre_proposals.swap_remove(index);
}

// === Public-View Functions ===

public fun get_completed_proposals(self: &ProposalRegistry): vector<ID> {
    let mut i = 0;
    let mut proposals = vector::empty();

    while (i < self.completed_proposals.length()) {
        proposals.push_back(*self.completed_proposals.borrow(i));
        i = i + 1;
    };

    proposals
}

public fun get_active_proposals(self: &ProposalRegistry): vector<ID> {
    let mut i = 0;
    let mut proposals = vector::empty();

    while (i < self.active_proposals.length()) {
        proposals.push_back(*self.active_proposals.borrow(i));
        i = i + 1;
    };

    proposals
}

public fun get_pre_proposals(self: &ProposalRegistry): vector<ID> {
    let mut i = 0;
    let mut proposals = vector::empty();

    while (i < self.pre_proposals.length()) {
        proposals.push_back(*self.pre_proposals.borrow(i));
        i = i + 1;
    };

    proposals
}

// === Private-View Functions ===

fun find_completed_proposal(self: &ProposalRegistry, id: ID): Option<u64> {
    return find_in_table_vec(&self.completed_proposals, id)
}

fun find_active_proposal(self: &ProposalRegistry, id: ID): Option<u64> {
    return find_in_table_vec(&self.active_proposals, id)
}

fun find_pre_proposal(self: &ProposalRegistry, id: ID): Option<u64> {
    return find_in_table_vec(&self.pre_proposals, id)
}

// === Helper Functions ===

fun find_in_table_vec(table_vec: &TableVec<ID>, id: ID): Option<u64> {
    let mut i = 0;

    while (i < table_vec.length()) {
        if (table_vec.borrow(i) == id) {
            return option::some(i)
        };

        i = i + 1;
    };

    return option::none()
}
