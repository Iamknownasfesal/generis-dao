#[test_only]
module generis_dao::dao_tests {
    use std::type_name;
    use std::string;

    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::test_utils::assert_eq;
    use sui::coin::{Self, burn_for_testing, mint_for_testing};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

    use generis_dao::s_eth::S_ETH;
    use generis_dao::test_utils::{people, scenario};
    use generis_dao::dao::{Self, ProposalRegistry};
    use generis_dao::config::{Self, ProposalConfig};

    const DEFAULT_PRE_PROPOSAL_FEES: u64 = 100_000_000_000;

    #[test]
    #[lint_allow(share_owned)]
    fun initiates_correctly() {
        let mut scenario = scenario();
        let (alice, _) = people();

        let test = &mut scenario;

        let mut c = clock::create_for_testing(ctx(test));

        set_up(test);

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);

            assert_eq(config.fee(), DEFAULT_PRE_PROPOSAL_FEES);
            assert_eq(config.receiver(), @dao);

            test::return_shared(config);
        };

        next_tx(test, alice);
        {
            let config = test::take_shared<ProposalConfig>(test);
            let mut registry = test::take_shared<ProposalRegistry>(test);

            // let pre_proposal_id = dao::create_pre_proposal(
            //     &config,
            //     &mut registry,
            //     mint_for_testing(100_000_000_000, ctx(test)),
            //     string::utf8(b"test"),
            //     string::utf8(b"this is a test"),
            //     vector::empty(),
            //     ctx(test)
            // );

            // let pre_proposal = registry.get_pre_proposal(pre_proposal_id);

            // assert_eq(pre_proposal.proposer, alice);

            test::return_shared(config);
            test::return_shared(registry);
        };

        clock::destroy_for_testing(c);
        test::end(scenario);
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