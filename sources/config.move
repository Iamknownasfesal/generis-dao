module generis_dao::config {
    use generis_dao::dao_admin::DaoAdmin;

    public struct ProposalConfig has key, store {
        id: UID,
        /// The minimum amount of Generis that a user needs to pay to create a {PreProposal}. This will send to the wallet of the {DaoReceiver}.
        fee: u64,
        /// The DAO Receiver address
        receiver: address,
        /// Minimum amount of Generis that a user needs to pay to create a {PreProposal}
        min_generis_to_create_proposal: u64,
    }

    // === Public-Mutative Functions ===

    public(package) fun new(
        fee: u64,
        receiver: address,
        min_generis_to_create_proposal: u64,
        ctx: &mut TxContext,
    ): ProposalConfig {
        ProposalConfig { id: object::new(ctx), fee, receiver, min_generis_to_create_proposal }
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
        min_generis_to_create_proposal: u64,
    ) {
        proposal_config.min_generis_to_create_proposal = min_generis_to_create_proposal;
    }

    // === Public-View Functions ===

    public fun fee(proposal_config: &ProposalConfig): u64 {
        proposal_config.fee
    }

    public fun receiver(proposal_config: &ProposalConfig): address {
        proposal_config.receiver
    }
    public fun min_generis_to_create_proposal(proposal_config: &ProposalConfig): u64 {
        proposal_config.min_generis_to_create_proposal
    }
}
