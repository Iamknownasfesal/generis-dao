#[test_only]
module generis_dao::dao_tests {
    use std::type_name;
    use std::string;

    use sui::clock::{Self, Clock};
    use sui::test_utils::assert_eq;
    use sui::coin::{Coin, mint_for_testing};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    use generis_dao::s_eth::S_ETH;
    use generis_dao::test_utils::{people, scenario};
    use generis_dao::dao::{Self, ProposalRegistry};
    use generis_dao::config::ProposalConfig;
    use generis_dao::dao_admin::DaoAdmin;
    use generis::generis::GENERIS;

    const DEFAULT_PRE_PROPOSAL_FEES: u64 = 100_000_000_000;

    #[test]
    #[lint_allow(share_owned)]
    fun initiates_correctly() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;

        let mut c = clock::create_for_testing(ctx(test));

        set_up(test);

        // Check that the DAO is initiated correctly
        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);

            assert_eq(config.fee(), DEFAULT_PRE_PROPOSAL_FEES);
            assert_eq(config.receiver(), @dao);

            test::return_shared(config);
        };

        let mut pre_proposal_id_: ID = object::id(&c);

        // Create a pre-proposal and check that it is created correctly
        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);

            let mut vote_types = vector::empty();

            vote_types.push_back(string::utf8(b"yes"));
            vote_types.push_back(string::utf8(b"no"));

            let pre_proposal_id = dao::create_pre_proposal(
                &config,
                &mut registry,
                mint_for_testing(100_000_000_000, ctx(test)),
                string::utf8(b"test"),
                string::utf8(b"this is a test"),
                vote_types,
                ctx(test)
            );

            let pre_proposal = registry.get_pre_proposal(pre_proposal_id);

            assert_eq(pre_proposal.proposer(), alice);
            assert_eq(pre_proposal.name(), string::utf8(b"test"));
            assert_eq(pre_proposal.description(), string::utf8(b"this is a test"));
            assert_eq(pre_proposal.vote_types().length(), 2);

            pre_proposal_id_ = pre_proposal_id;

            test::return_shared(config);
            test::return_shared(registry);
        };
        
        // Check if after the pre-proposal is created, the proposal payment is gotten by the DAO
        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let payment = test::take_from_address<Coin<GENERIS>>(test, @dao);

            assert_eq(payment.value(), DEFAULT_PRE_PROPOSAL_FEES);

            test::return_shared(config);
            test::return_to_address(@dao, payment);
        };

        let mut proposal_id_: ID = object::id(&c);
        
        // Approve the pre-proposal and check that the proposal is created correctly
        next_tx(test, alice);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let dao_admin = test::take_from_sender<DaoAdmin>(test);

            let proposal_id = dao::approve_pre_proposal<S_ETH, GENERIS>(
                &dao_admin,
                &mut registry,
                pre_proposal_id_,
                mint_for_testing(100_000_000_000, ctx(test)),
                1,
                100,
                ctx(test)
            );

            let proposal = registry.get_proposal<S_ETH, GENERIS>(proposal_id);

            assert_eq(proposal.accepted_by(), alice);
            assert_eq(object::id(proposal.pre_proposal()), pre_proposal_id_);
            assert_eq(proposal.reward_pool().is_some(), true);
            assert_eq(proposal.start_time(), 1);
            assert_eq(proposal.end_time(), 100);
            assert_eq(proposal.total_vote_value(), 0);
            assert_eq(proposal.votes().length(), 0);
            assert_eq(proposal.reward_coin_type(), type_name::get<S_ETH>());
            assert_eq(proposal.vote_coin_type(), type_name::get<GENERIS>());

            proposal_id_ = proposal_id;

            test::return_shared(registry);
            test::return_to_sender(test, dao_admin);
        };

        clock::increment_for_testing(&mut c, 1);

        // Vote on the proposal and check that the vote is registered correctly
        next_tx(test, alice);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);

            let proposal = registry.get_proposal<S_ETH, GENERIS>(proposal_id_);
            let vote_types = proposal.pre_proposal().vote_types();
            // Vote yes
            let vote_type_id = vote_types.front();

            assert_eq(vote_type_id.is_some(), true);
            let vote_type_id = *vote_type_id.borrow();

            let vote_coin = mint_for_testing<GENERIS>(20_000_000_000, ctx(test));

            let vote_id = dao::vote<S_ETH, GENERIS>(&mut registry, &c, proposal_id_, vote_type_id, vote_coin, ctx(test));

            let proposal = registry.get_proposal<S_ETH, GENERIS>(proposal_id_);

            let votes = proposal.votes();

            assert_eq(votes.length(), 1);

            let vote = votes.borrow(alice);

            assert_eq(object::id(vote), vote_id);
            assert_eq(vote.proposal_id(), proposal_id_);
            assert_eq(vote.vote_type_id(), vote_type_id);
            assert_eq(vote.balance().value(), 20_000_000_000);
            
            test::return_shared(registry);
        };

        // Okay vote 90% with different vote types, votes and addresses

        let bob: address = @0xb0b;
        let charlie: address = @0xc0c;
        let dave: address = @0xd0d;

        next_tx(test, alice);

        let registry = test::take_shared<ProposalRegistry>(test);
        let proposal = registry.get_proposal<S_ETH, GENERIS>(proposal_id_);
        let vote_types_yes = *proposal.pre_proposal().vote_types().front().borrow();
        let vote_types_no = *proposal.pre_proposal().vote_types().back().borrow();
        test::return_shared(registry);

        next_tx(test, bob);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);

            vote_easy(&c, &mut registry, proposal_id_, vote_types_no, 20_000_000_000, ctx(test));
            vote_easy(&c, &mut registry, proposal_id_, vote_types_no, 10_000_000_000, ctx(test));

            test::return_shared(registry);
        };

        next_tx(test, charlie);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);

            vote_easy(&c, &mut registry, proposal_id_, vote_types_no, 20_000_000_000, ctx(test));
            vote_easy(&c, &mut registry, proposal_id_, vote_types_no, 20_000_000_000, ctx(test));

            test::return_shared(registry);
        };

        next_tx(test, dave);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);

            vote_easy(&c, &mut registry, proposal_id_, vote_types_yes, 10_000_000_000, ctx(test));

            test::return_shared(registry);
        };

        // Let's complete now

        clock::increment_for_testing(&mut c, 100);

        next_tx(test, alice);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let admin = test::take_from_sender<DaoAdmin>(test);

            let complete_id = dao::complete<S_ETH, GENERIS>(&admin, &c, &mut registry, proposal_id_, ctx(test));

            let completed_proposal = registry.get_completed_proposal(complete_id);

            assert_eq(completed_proposal.ended_at(), 101);
            assert_eq(object::id(completed_proposal.approved_vote_type()), vote_types_no);
            assert_eq(completed_proposal.accepted_by(), alice);
            assert_eq(completed_proposal.total_vote_value(), 100_000_000_000);

            test::return_shared(registry);
            test::return_to_sender(test, admin);
        };

        // Let's check the rewards

        next_tx(test, alice);
        {
            let reward_coins = test::take_from_sender<Coin<S_ETH>>(test);

            assert_eq(reward_coins.value(), 20_000_000_000);

            test::return_to_sender(test, reward_coins);
        };

        next_tx(test, bob);
        {
            let reward_coins = test::take_from_sender<Coin<S_ETH>>(test);

            assert_eq(reward_coins.value(), 30_000_000_000);

            test::return_to_sender(test, reward_coins);
        };

        next_tx(test, charlie);
        {
            let reward_coins = test::take_from_sender<Coin<S_ETH>>(test);

            assert_eq(reward_coins.value(), 40_000_000_000);

            test::return_to_sender(test, reward_coins);
        };

        next_tx(test, dave);
        {
            let reward_coins = test::take_from_sender<Coin<S_ETH>>(test);

            assert_eq(reward_coins.value(), 10_000_000_000);

            test::return_to_sender(test, reward_coins);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    fun vote_easy(c: &Clock, registry: &mut ProposalRegistry, proposal_id: ID, vote_type_id: ID, amount: u64, ctx: &mut TxContext) {
        let vote_coin = mint_for_testing<GENERIS>(amount, ctx);

        dao::vote<S_ETH, GENERIS>(registry, c, proposal_id, vote_type_id, vote_coin, ctx);
    }

    #[lint_allow(share_owned)]
    fun set_up(test: &mut Scenario) {
        let (alice, _) = people();
        next_tx(test, alice);
        {
            dao::init_for_testing(ctx(test));
        };
    }
}