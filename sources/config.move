module generis_dao::config {
    // === Imports ===

    use generis_dao::dao_admin::DaoAdmin;

    // === Structs ===
    
    public struct ProposalConfig has key, store {
        id: UID,
        /// The minimum amount of Generis that a user needs to pay to create a {PreProposal}. This will send to the wallet of the {DaoReceiver}.
        fee: u64,
        /// The DAO Receiver address
        receiver: address,
    }

    // === Public-Mutative Functions ===

    public(package) fun new(fee: u64, receiver: address, ctx: &mut TxContext): ProposalConfig {
        ProposalConfig {
            id: object::new(ctx),
            fee,
            receiver,
        }
    }

    public fun set_fee(_: &DaoAdmin, proposal_config: &mut ProposalConfig, min_generis_to_create_proposal: u64) {
        proposal_config.fee = min_generis_to_create_proposal;
    }

    public fun set_dao_receiver(_: &DaoAdmin, proposal_config: &mut ProposalConfig, receiver: address) {
        proposal_config.receiver = receiver;
    }

    // === Public-View Functions ===

    public fun fee(proposal_config: &ProposalConfig): u64 {
        proposal_config.fee
    }

    public fun receiver(proposal_config: &ProposalConfig): address {
        proposal_config.receiver
    }
}