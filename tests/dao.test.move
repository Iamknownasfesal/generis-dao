#[test_only]
module generis_dao::dao_tests {
    use generis::generis::GENERIS;
    use generis_dao::{
        completed_proposal::CompletedProposal,
        config::ProposalConfig,
        dao,
        dao_admin::DaoAdmin,
        pre_proposal::PreProposal,
        proposal::Proposal,
        proposal_registry::ProposalRegistry,
        s_eth::S_ETH,
        test_utils::{people, scenario}
    };
    use std::{string, type_name};
    use sui::{
        clock::{Self, Clock},
        coin::{Coin, mint_for_testing},
        test_scenario::{Self as test, Scenario, next_tx, ctx},
        test_utils::assert_eq
    };

    const DEFAULT_PRE_PROPOSAL_FEES: u64 = 100_000_000_000;
    const DEFAULT_PRE_PROPOSAL_MIN: u64 = 1_000_000_000_000;

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
            assert_eq(config.receiver(), @dao_treasury);
            assert_eq(
                config.min_generis_to_create_proposal(),
                DEFAULT_PRE_PROPOSAL_MIN,
            );

            test::return_shared(config);
        };

        // Create a pre-proposal and check that it is created correctly
        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);

            let mut vote_types = vector::empty();

            vote_types.push_back(string::utf8(b"yes"));
            vote_types.push_back(string::utf8(b"no"));

            dao::create_pre_proposal(
                &config,
                &mut registry,
                mint_for_testing(1_100_000_000_000, ctx(test)),
                string::utf8(b"test"),
                string::utf8(b"this is a test"),
                vote_types,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
        };

        next_tx(test, alice);
        {
            let pre_proposal = test::take_shared<PreProposal>(test);
            assert_eq(pre_proposal.proposer(), alice);
            assert_eq(pre_proposal.name(), string::utf8(b"test"));
            assert_eq(
                pre_proposal.description(),
                string::utf8(b"this is a test"),
            );
            assert_eq(pre_proposal.vote_types().length(), 2);

            test::return_shared(pre_proposal);
        };

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let payment = test::take_from_address<Coin<GENERIS>>(
                test,
                @dao_treasury,
            );

            assert_eq(payment.value(), DEFAULT_PRE_PROPOSAL_FEES);

            test::return_shared(config);
            test::return_to_address(@dao_treasury, payment);
        };

        // Approve the pre-proposal and check that the proposal is created correctly
        next_tx(test, alice);
        {
            let mut config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let dao_admin = test::take_from_sender<DaoAdmin>(test);
            let pre_proposal = test::take_shared<PreProposal>(test);

            dao::approve_pre_proposal<S_ETH, GENERIS>(
                &dao_admin,
                &mut config,
                &mut registry,
                pre_proposal,
                mint_for_testing(100_000_000_000, ctx(test)),
                1,
                100,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
            test::return_to_sender(test, dao_admin);
        };

        next_tx(test, alice);
        {
            let proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(test);
            assert_eq(proposal.accepted_by(), alice);
            assert_eq(proposal.reward_pool().is_some(), true);
            assert_eq(proposal.start_time(), 1);
            assert_eq(proposal.end_time(), 100);
            assert_eq(proposal.total_vote_value(), 0);
            assert_eq(proposal.votes().length(), 0);
            assert_eq(proposal.reward_coin_type(), type_name::get<S_ETH>());
            assert_eq(proposal.vote_coin_type(), type_name::get<GENERIS>());

            test::return_shared(proposal);
        };
        clock::increment_for_testing(&mut c, 1);

        // Vote on the proposal and check that the vote is registered correctly
        next_tx(test, alice);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );
            let vote_types = proposal.pre_proposal().vote_types();
            // Vote yes
            let vote_type_id = vote_types.front();

            assert_eq(vote_type_id.is_some(), true);
            let vote_type_id = *vote_type_id.borrow();

            let vote_coin = mint_for_testing<GENERIS>(
                20_000_000_000,
                ctx(test),
            );

            let vote_id = dao::vote<S_ETH, GENERIS>(
                &mut proposal,
                &c,
                vote_type_id,
                vote_coin,
                ctx(test),
            );

            let votes = proposal.votes();

            assert_eq(votes.length(), 1);

            let vote = votes.borrow(alice);

            assert_eq(object::id(vote), vote_id);
            assert_eq(vote.proposal_id(), object::id(&proposal));
            assert_eq(vote.vote_type_id(), vote_type_id);
            assert_eq(vote.balance().value(), 20_000_000_000);
            test::return_shared(proposal);
        };

        // Okay vote 90% with different vote types, votes and addresses

        let bob: address = @0xb0b;
        let charlie: address = @0xc0c;
        let dave: address = @0xd0d;

        next_tx(test, alice);

        let registry = test::take_shared<ProposalRegistry>(test);
        let proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(test);
        let vote_types_yes = *proposal
            .pre_proposal()
            .vote_types()
            .front()
            .borrow();
        let vote_types_no = *proposal
            .pre_proposal()
            .vote_types()
            .back()
            .borrow();
        test::return_shared(registry);
        test::return_shared(proposal);

        next_tx(test, bob);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );

            vote_easy(
                &mut proposal,
                &c,
                vote_types_no,
                20_000_000_000,
                ctx(test),
            );
            vote_easy(
                &mut proposal,
                &c,
                vote_types_no,
                10_000_000_000,
                ctx(test),
            );

            test::return_shared(proposal);
        };

        next_tx(test, charlie);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );

            vote_easy(
                &mut proposal,
                &c,
                vote_types_no,
                20_000_000_000,
                ctx(test),
            );
            vote_easy(
                &mut proposal,
                &c,
                vote_types_no,
                20_000_000_000,
                ctx(test),
            );

            test::return_shared(proposal);
        };

        next_tx(test, dave);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );

            vote_easy(
                &mut proposal,
                &c,
                vote_types_yes,
                10_000_000_000,
                ctx(test),
            );

            test::return_shared(proposal);
        };

        // Let's complete now

        clock::increment_for_testing(&mut c, 100);

        next_tx(test, alice);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let admin = test::take_from_sender<DaoAdmin>(test);
            let proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(test);

            dao::complete<S_ETH, GENERIS>(
                &admin,
                &c,
                &mut registry,
                proposal,
                ctx(test),
            );

            test::return_shared(registry);
            test::return_to_sender(test, admin);
        };

        next_tx(test, alice);
        {
            let completed_proposal = test::take_shared<CompletedProposal>(test);

            assert_eq(completed_proposal.ended_at(), 101);
            assert_eq(
                object::id(completed_proposal.approved_vote_type()),
                vote_types_no,
            );
            assert_eq(completed_proposal.accepted_by(), alice);
            assert_eq(completed_proposal.total_vote_value(), 100_000_000_000);

            test::return_shared(completed_proposal);
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

    #[test]
    #[lint_allow(share_owned)]
    fun initializes() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;

        set_up(test);

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);

            assert_eq(config.fee(), DEFAULT_PRE_PROPOSAL_FEES);
            assert_eq(config.receiver(), @dao_treasury);
            assert_eq(
                config.min_generis_to_create_proposal(),
                DEFAULT_PRE_PROPOSAL_MIN,
            );

            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    fun initializes_pre_proposal() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;

        set_up(test);

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);

            let mut vote_types = vector::empty();

            vote_types.push_back(string::utf8(b"yes"));
            vote_types.push_back(string::utf8(b"no"));

            dao::create_pre_proposal(
                &config,
                &mut registry,
                mint_for_testing(1_100_000_000_000, ctx(test)),
                string::utf8(b"test"),
                string::utf8(b"this is a test"),
                vote_types,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
        };

        next_tx(test, alice);
        {
            let pre_proposal = test::take_shared<PreProposal>(test);
            assert_eq(pre_proposal.proposer(), alice);
            assert_eq(pre_proposal.name(), string::utf8(b"test"));
            assert_eq(
                pre_proposal.description(),
                string::utf8(b"this is a test"),
            );
            assert_eq(pre_proposal.vote_types().length(), 2);

            test::return_shared(pre_proposal);
        };

        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    fun approves_pre_proposal() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;

        set_up(test);

        let c = clock::create_for_testing(ctx(test));

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);

            let mut vote_types = vector::empty();

            vote_types.push_back(string::utf8(b"yes"));
            vote_types.push_back(string::utf8(b"no"));

            dao::create_pre_proposal(
                &config,
                &mut registry,
                mint_for_testing(1_100_000_000_000, ctx(test)),
                string::utf8(b"test"),
                string::utf8(b"this is a test"),
                vote_types,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
        };

        next_tx(test, alice);
        {
            let mut config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let dao_admin = test::take_from_sender<DaoAdmin>(test);
            let pre_proposal = test::take_shared<PreProposal>(test);

            dao::approve_pre_proposal<S_ETH, GENERIS>(
                &dao_admin,
                &mut config,
                &mut registry,
                pre_proposal,
                mint_for_testing(100_000_000_000, ctx(test)),
                1,
                100,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
            test::return_to_sender(test, dao_admin);
        };

        next_tx(test, alice);
        {
            let proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(test);
            assert_eq(proposal.accepted_by(), alice);
            assert_eq(proposal.reward_pool().is_some(), true);
            assert_eq(proposal.start_time(), 1);
            assert_eq(proposal.end_time(), 100);
            assert_eq(proposal.total_vote_value(), 0);
            assert_eq(proposal.votes().length(), 0);
            assert_eq(proposal.reward_coin_type(), type_name::get<S_ETH>());
            assert_eq(proposal.vote_coin_type(), type_name::get<GENERIS>());

            test::return_shared(proposal);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    fun admin_can_create_proposal() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;

        set_up(test);

        let c = clock::create_for_testing(ctx(test));

        next_tx(test, alice);
        {
            let mut config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let dao_admin = test::take_from_sender<DaoAdmin>(test);

            let mut vote_types = vector::empty();

            vote_types.push_back(string::utf8(b"yes"));
            vote_types.push_back(string::utf8(b"no"));

            dao::create_proposal<S_ETH, GENERIS>(
                &dao_admin,
                &mut config,
                &mut registry,
                string::utf8(b"test"),
                string::utf8(b"this is a test"),
                vote_types,
                mint_for_testing(100_000_000_000, ctx(test)),
                1,
                100,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
            test::return_to_sender(test, dao_admin);
        };

        next_tx(test, alice);
        {
            let proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(test);
            assert_eq(proposal.accepted_by(), alice);
            assert_eq(proposal.reward_pool().is_some(), true);
            assert_eq(proposal.start_time(), 1);
            assert_eq(proposal.end_time(), 100);
            assert_eq(proposal.total_vote_value(), 0);
            assert_eq(proposal.votes().length(), 0);
            assert_eq(proposal.reward_coin_type(), type_name::get<S_ETH>());
            assert_eq(proposal.vote_coin_type(), type_name::get<GENERIS>());

            test::return_shared(proposal);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    fun can_vote() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;
        let mut c = setup_with_approved_proposal(test);

        clock::increment_for_testing(&mut c, 1);

        next_tx(test, alice);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );
            let vote_types = proposal.pre_proposal().vote_types();
            let vote_type_id = *vote_types.front().borrow();

            let vote_coin = mint_for_testing<GENERIS>(
                20_000_000_000,
                ctx(test),
            );

            dao::vote<S_ETH, GENERIS>(
                &mut proposal,
                &c,
                vote_type_id,
                vote_coin,
                ctx(test),
            );

            assert_eq(proposal.total_vote_value(), 20_000_000_000);
            test::return_shared(proposal);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    fun can_complete_proposal() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;
        let mut c = setup_with_approved_proposal(test);

        clock::increment_for_testing(&mut c, 99);

        next_tx(test, alice);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let admin = test::take_from_sender<DaoAdmin>(test);
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );

            let vote_type_id = *proposal
                .pre_proposal()
                .vote_types()
                .front()
                .borrow();

            vote_easy(
                &mut proposal,
                &c,
                vote_type_id,
                20_000_000_000,
                ctx(test),
            );

            clock::increment_for_testing(&mut c, 2);

            dao::complete<S_ETH, GENERIS>(
                &admin,
                &c,
                &mut registry,
                proposal,
                ctx(test),
            );

            test::return_shared(registry);
            test::return_to_sender(test, admin);
        };

        next_tx(test, alice);
        {
            let completed_proposal = test::take_shared<CompletedProposal>(test);
            assert_eq(completed_proposal.ended_at(), 101);
            assert_eq(completed_proposal.accepted_by(), alice);
            assert_eq(completed_proposal.total_vote_value(), 20_000_000_000);

            test::return_shared(completed_proposal);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::ECannotVoteWithZeroCoinValue)]
    fun test_cannot_vote_with_zero_coin_value() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;
        let c = setup_with_approved_proposal(test);

        next_tx(test, alice);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );
            let vote_types = proposal.pre_proposal().vote_types();
            let vote_type_id = *vote_types.front().borrow();

            let vote_coin = mint_for_testing<GENERIS>(0, ctx(test));

            dao::vote<S_ETH, GENERIS>(
                &mut proposal,
                &c,
                vote_type_id,
                vote_coin,
                ctx(test),
            );

            test::return_shared(proposal);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::ETooLateToVote)]
    fun test_too_late_to_vote() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;
        let mut c = setup_with_approved_proposal(test);

        clock::increment_for_testing(&mut c, 101);

        next_tx(test, alice);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );
            let vote_types = proposal.pre_proposal().vote_types();
            let vote_type_id = *vote_types.front().borrow();

            let vote_coin = mint_for_testing<GENERIS>(
                20_000_000_000,
                ctx(test),
            );

            dao::vote<S_ETH, GENERIS>(
                &mut proposal,
                &c,
                vote_type_id,
                vote_coin,
                ctx(test),
            );

            test::return_shared(proposal);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::ETooSoonToVote)]
    fun test_too_soon_to_vote() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;
        let mut c = setup_with_approved_proposal(test);

        clock::increment_for_testing(&mut c, 0);

        next_tx(test, alice);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );
            let vote_types = proposal.pre_proposal().vote_types();
            let vote_type_id = *vote_types.front().borrow();

            let vote_coin = mint_for_testing<GENERIS>(
                20_000_000_000,
                ctx(test),
            );

            dao::vote<S_ETH, GENERIS>(
                &mut proposal,
                &c,
                vote_type_id,
                vote_coin,
                ctx(test),
            );

            test::return_shared(proposal);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::EVoteTypeDoesNotExist)]
    fun test_vote_with_non_existent_vote_coin_type() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;
        let mut c = setup_with_approved_proposal(test);

        clock::increment_for_testing(&mut c, 1);

        next_tx(test, alice);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );
            let vote_coin = mint_for_testing<GENERIS>(
                20_000_000_000,
                ctx(test),
            );

            dao::vote<S_ETH, GENERIS>(
                &mut proposal,
                &c,
                object::id(&c),
                vote_coin,
                ctx(test),
            );

            test::return_shared(proposal);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::ECannotVoteDifferentVoteCoinType)]
    fun test_vote_with_different_vote_coin_type() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;
        let mut c = setup_with_approved_proposal(test);

        clock::increment_for_testing(&mut c, 1);

        next_tx(test, alice);
        {
            let mut proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(
                test,
            );
            let vote_coin = mint_for_testing<GENERIS>(
                20_000_000_000,
                ctx(test),
            );
            let vote_types = proposal.pre_proposal().vote_types();
            let vote_type_id = *vote_types.front().borrow();
            let vote_type_id_2 = *vote_types.back().borrow();

            dao::vote<S_ETH, GENERIS>(
                &mut proposal,
                &c,
                vote_type_id,
                vote_coin,
                ctx(test),
            );
            let vote_coin = mint_for_testing<GENERIS>(
                20_000_000_000,
                ctx(test),
            );

            dao::vote<S_ETH, GENERIS>(
                &mut proposal,
                &c,
                vote_type_id_2,
                vote_coin,
                ctx(test),
            );

            test::return_shared(proposal);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::EProposalCannotBeCompletedYet)]
    fun test_complete_proposal_too_early() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;
        let c = setup_with_approved_proposal(test);

        next_tx(test, alice);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(test);
            let admin = test::take_from_sender<DaoAdmin>(test);

            dao::complete<S_ETH, GENERIS>(
                &admin,
                &c,
                &mut registry,
                proposal,
                ctx(test),
            );

            test::return_shared(registry);
            test::return_to_sender(test, admin);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::EVoteTypeCannotBeNone)]
    fun test_vote_with_none_vote_type() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;
        let mut c = setup_with_approved_proposal(test);

        clock::increment_for_testing(&mut c, 101);

        next_tx(test, alice);
        {
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let proposal = test::take_shared<Proposal<S_ETH, GENERIS>>(test);
            let admin = test::take_from_sender<DaoAdmin>(test);

            dao::complete<S_ETH, GENERIS>(
                &admin,
                &c,
                &mut registry,
                proposal,
                ctx(test),
            );

            test::return_shared(registry);
            test::return_to_sender(test, admin);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::ENotEnoughGenerisToCreateProposal)]
    fun test_not_enough_generis_to_create_proposal() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;

        set_up(test);

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);

            let mut vote_types = vector::empty();

            vote_types.push_back(string::utf8(b"yes"));
            vote_types.push_back(string::utf8(b"no"));

            dao::create_pre_proposal(
                &config,
                &mut registry,
                mint_for_testing(0, ctx(test)),
                string::utf8(b"test"),
                string::utf8(b"this is a test"),
                vote_types,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
        };

        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::EUserShouldHaveMoreThanMinimumGeneris)]
    fun test_user_should_have_more_than_minimum_generis() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;

        set_up(test);

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);

            let mut vote_types = vector::empty();

            vote_types.push_back(string::utf8(b"yes"));
            vote_types.push_back(string::utf8(b"no"));

            dao::create_pre_proposal(
                &config,
                &mut registry,
                mint_for_testing(100_000_000_001, ctx(test)),
                string::utf8(b"test"),
                string::utf8(b"this is a test"),
                vote_types,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
        };

        test::end(scenario);
    }

    #[test]
    #[lint_allow(share_owned)]
    #[expected_failure(abort_code = dao::EAtLeastTwoVoteTypesAreRequired)]
    fun test_at_least_two_vote_types_are_required() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;

        set_up(test);

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);

            let mut vote_types = vector::empty();

            vote_types.push_back(string::utf8(b"yes"));

            dao::create_pre_proposal(
                &config,
                &mut registry,
                mint_for_testing(1_100_000_000_000, ctx(test)),
                string::utf8(b"test"),
                string::utf8(b"this is a test"),
                vote_types,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
        };

        test::end(scenario);
    }

    fun setup_with_approved_proposal(test: &mut Scenario): Clock {
        let (alice, _) = people();
        next_tx(test, alice);
        {
            dao::init_for_testing(ctx(test));
        };

        let c = clock::create_for_testing(ctx(test));

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);

            let mut vote_types = vector::empty();

            vote_types.push_back(string::utf8(b"yes"));
            vote_types.push_back(string::utf8(b"no"));

            dao::create_pre_proposal(
                &config,
                &mut registry,
                mint_for_testing(1_100_000_000_000, ctx(test)),
                string::utf8(b"test"),
                string::utf8(b"this is a test"),
                vote_types,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
        };

        next_tx(test, alice);
        {
            let mut config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);
            let dao_admin = test::take_from_sender<DaoAdmin>(test);
            let pre_proposal = test::take_shared<PreProposal>(test);

            dao::approve_pre_proposal<S_ETH, GENERIS>(
                &dao_admin,
                &mut config,
                &mut registry,
                pre_proposal,
                mint_for_testing(100_000_000_000, ctx(test)),
                1,
                100,
                ctx(test),
            );

            test::return_shared(config);
            test::return_shared(registry);
            test::return_to_sender(test, dao_admin);
        };

        c
    }

    fun vote_easy(
        proposal: &mut Proposal<S_ETH, GENERIS>,
        c: &Clock,
        vote_type_id: ID,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        let vote_coin = mint_for_testing<GENERIS>(amount, ctx);

        dao::vote<S_ETH, GENERIS>(proposal, c, vote_type_id, vote_coin, ctx);
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
