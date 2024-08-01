module generis_dao::config;

use generis_dao::dao_admin::DaoAdmin;
use std::type_name::{Self, TypeName};
use sui::package::Publisher;

public struct ProposalConfig has key, store {
    id: UID,
    /// The minimum amount of Generis that a user needs to pay to create a {PreProposal}. This will send to the wallet of the {DaoReceiver}.
    fee: u64,
    /// The DAO Receiver address
    receiver: address,
    /// Minimum amount of Generis that a user needs to pay to create a {PreProposal}
    min_in_to_create_proposal: u64,
    /// The amount of proposals got created
    proposal_index: u64,
    /// Publisher object for adding display
    publisher: Publisher,
    /// TypeName of the Payment
    payment_type: TypeName,
}

// === Public-Mutative Functions ===

public(package) fun new<PaymentCoin>(
    fee: u64,
    receiver: address,
    min_in_to_create_proposal: u64,
    publisher: Publisher,
    ctx: &mut TxContext,
): ProposalConfig {
    ProposalConfig {
        id: object::new(ctx),
        fee,
        receiver,
        min_in_to_create_proposal,
        proposal_index: 1,
        publisher,
        payment_type: type_name::get<PaymentCoin>(),
    }
}

public(package) fun proposal_created(proposal_config: &mut ProposalConfig) {
    proposal_config.proposal_index = proposal_config.proposal_index + 1;
}

public entry fun set_fee(
    _: &DaoAdmin,
    proposal_config: &mut ProposalConfig,
    min_generis_to_create_proposal: u64,
) {
    proposal_config.fee = min_generis_to_create_proposal;
}

public entry fun set_dao_receiver(
    _: &DaoAdmin,
    proposal_config: &mut ProposalConfig,
    receiver: address,
) {
    proposal_config.receiver = receiver;
}

public entry fun set_min_generis_to_create_proposal(
    _: &DaoAdmin,
    proposal_config: &mut ProposalConfig,
    min_in_to_create_proposal: u64,
) {
    proposal_config.min_in_to_create_proposal = min_in_to_create_proposal;
}

public entry fun set_payment_type<PaymentCoin>(
    _: &DaoAdmin,
    proposal_config: &mut ProposalConfig,
) {
    proposal_config.payment_type = type_name::get<PaymentCoin>();
}

// === Public-View Functions ===

public fun fee(proposal_config: &ProposalConfig): u64 {
    proposal_config.fee
}

public fun receiver(proposal_config: &ProposalConfig): address {
    proposal_config.receiver
}

public fun min_in_to_create_proposal(proposal_config: &ProposalConfig): u64 {
    proposal_config.min_in_to_create_proposal
}

public fun proposal_index(proposal_config: &ProposalConfig): u64 {
    proposal_config.proposal_index
}

public fun payment_type(proposal_config: &ProposalConfig): TypeName {
    proposal_config.payment_type
}

public(package) fun publisher(proposal_config: &ProposalConfig): &Publisher {
    &proposal_config.publisher
}
