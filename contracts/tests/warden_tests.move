#[test_only]
module warden::warden_tests;

use sui::tx_context;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use warden::vault;
use warden::policy;
use warden::guardian;
use warden::critic;
use warden::ledger;
use warden::warden;
use warden::feed;

const ADMIN: address = @0xA;
const CRITIC: address = @0xC;

// a shared market feed pre-loaded with (price, depth)
fun feed_with(price: u64, depth: u64, clk: &clock::Clock, ctx: &mut TxContext): feed::OracleFeed {
    let mut f = feed::new(ctx.sender(), 3_600_000, clk, ctx);
    feed::update(&mut f, price, depth, clk, ctx);
    f
}

// build the full stack, return the moving parts
fun setup(ctx: &mut TxContext, clock: &clock::Clock): (
    vault::Vault<SUI>, vault::OwnerCap, policy::WardenPolicy,
    policy::GenerationRegistry, critic::CriticRegistry, critic::CriticCap,
    ledger::TradeLedger,
) {
    let (mut v, ocap) = vault::new<SUI>(ctx);
    // fund the vault with 1_000_000
    let c = coin::mint_for_testing<SUI>(1_000_000, ctx);
    vault::deposit(&mut v, c, ctx);
    let vid = vault::vault_id(&v);

    let reg = policy::init_registry(vid, ctx);
    // per_tx 100_000, window 300_000 / 60s, reserve 50_000, ttl 1h
    let pol = policy::mint(&reg, vid, ADMIN, 100_000, 300_000, 60_000, 50_000, 3_600_000, clock, ctx);

    let creg = critic::init_registry(vid, CRITIC, ctx);
    let ccap = critic::new_cap_for(CRITIC, ctx);

    let led = ledger::new(vid, ctx);
    (v, ocap, pol, reg, creg, ccap, led)
}

fun teardown(
    v: vault::Vault<SUI>, ocap: vault::OwnerCap, pol: policy::WardenPolicy,
    reg: policy::GenerationRegistry, creg: critic::CriticRegistry,
    ccap: critic::CriticCap, led: ledger::TradeLedger,
) {
    vault::destroy_for_testing(v);
    vault::destroy_cap_for_testing(ocap);
    policy::destroy_policy_for_testing(pol);
    policy::destroy_registry_for_testing(reg);
    critic::destroy_registry_for_testing(creg);
    critic::destroy_cap_for_testing(ccap);
    ledger::destroy_for_testing(led);
}

#[test]
fun test_happy_path() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut v, ocap, mut pol, reg, creg, ccap, mut led) = setup(&mut ctx, &clk);

    // low exposure, deep book → low risk; claim ~matches derived
    let amount = 10_000;
    let derived = guardian::derive_risk_bps(amount, 1_000_000, 100_000_000);
    let t = warden::propose(&v, amount, guardian::dir_increase(), derived);
    let verdict = critic::judge(&ccap, warden::trade_digest(&t), true);
    let market = feed_with(1_000_000, 100_000_000, &clk, &mut ctx); // deep book
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        &market, b"walrus-blob-1", b"tee-att-1", &clk,
    );

    assert!(ledger::receipt_accepted(&r), 100);
    assert!(ledger::seq(&led) == 1, 101);
    assert!(vault::deployed(&v) == amount, 102);
    assert!(!vault::is_frozen(&v), 103);

    feed::destroy_for_testing(market);
    teardown(v, ocap, pol, reg, creg, ccap, led);
    clock::destroy_for_testing(clk);
}

// PIN (audit finding "DIR_REDUCE never reduces exposure"): documents that
// `direction` is a guardian gate label only — the executed leg is deploy-only
// in this package; a future package will branch settle() to undeploy on the
// reduce direction. A fully valid REDUCE-labelled trade (all five gates green)
// still moves idle -> deployed, INCREASING exposure by exactly `amount`.
#[test]
fun test_reduce_label_still_deploys() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut v, ocap, mut pol, reg, creg, ccap, mut led) = setup(&mut ctx, &clk);

    let idle_before = vault::idle_value(&v);
    let deployed_before = vault::deployed(&v);
    let nav_before = vault::nav(&v);

    // low exposure, deep fresh feed → guardian passes; direction = REDUCE
    let amount = 10_000;
    let derived = guardian::derive_risk_bps(deployed_before + amount, 1_000_000, 100_000_000);
    let t = warden::propose(&v, amount, guardian::dir_reduce(), derived);
    let verdict = critic::judge(&ccap, warden::trade_digest(&t), true);
    let market = feed_with(1_000_000, 100_000_000, &clk, &mut ctx);
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        &market, b"walrus-blob-reduce", b"tee-att-reduce", &clk,
    );

    assert!(ledger::receipt_accepted(&r), 400);       // trade went through
    assert!(!vault::is_frozen(&v), 401);
    // exposure INCREASED by exactly `amount` despite the REDUCE label
    assert!(vault::deployed(&v) == deployed_before + amount, 402);
    assert!(vault::idle_value(&v) == idle_before - amount, 403);
    assert!(vault::nav(&v) == nav_before, 404);       // conserved: funds never left

    feed::destroy_for_testing(market);
    teardown(v, ocap, pol, reg, creg, ccap, led);
    clock::destroy_for_testing(clk);
}

#[test]
fun test_divergence_freezes_and_records() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut v, ocap, mut pol, reg, creg, ccap, mut led) = setup(&mut ctx, &clk);

    let amount = 10_000;
    // agent LIES: claims 10 bps while the chain will derive far higher
    let t = warden::propose(&v, amount, guardian::dir_increase(), 10);
    let verdict = critic::judge(&ccap, warden::trade_digest(&t), true); // critic even approved it
    // thin book (depth 1000) on the on-chain feed → derived risk explodes
    let market = feed_with(1_000_000, 1_000, &clk, &mut ctx);
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        &market, b"walrus-blob-bad", b"tee-att-bad", &clk,
    );

    assert!(!ledger::receipt_accepted(&r), 200);   // rejected
    assert!(vault::is_frozen(&v), 201);            // chain froze the vault
    assert!(vault::deployed(&v) == 0, 202);        // nothing executed
    assert!(ledger::seq(&led) == 1, 203);          // but it IS on the record

    feed::destroy_for_testing(market);
    teardown(v, ocap, pol, reg, creg, ccap, led);
    clock::destroy_for_testing(clk);
}

#[test]
fun test_owner_withdraw_works_even_when_frozen() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut v, ocap, pol, reg, creg, ccap, led) = setup(&mut ctx, &clk);

    vault::freeze_vault(&mut v, 9); // agent halted
    let coin_out = vault::owner_withdraw(&mut v, &ocap, 200_000, &mut ctx);
    assert!(coin::value(&coin_out) == 200_000, 300); // owner still gets funds
    coin::burn_for_testing(coin_out);

    teardown(v, ocap, pol, reg, creg, ccap, led);
    clock::destroy_for_testing(clk);
}

#[test]
#[expected_failure(abort_code = 1, location = warden)] // ECriticDigestMismatch
fun test_critic_must_sign_the_real_digest() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut v, ocap, mut pol, reg, creg, ccap, mut led) = setup(&mut ctx, &clk);

    let amount = 10_000;
    let derived = guardian::derive_risk_bps(amount, 1_000_000, 100_000_000);
    let t = warden::propose(&v, amount, guardian::dir_increase(), derived);
    // critic signs a DIFFERENT digest than the one bound to the trade
    let verdict = critic::judge(&ccap, b"a-forged-digest", true);
    let market = feed_with(1_000_000, 100_000_000, &clk, &mut ctx);
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        &market, b"x", b"y", &clk,
    ); // judged != trade.digest -> ECriticDigestMismatch
    ledger::receipt_seq(&r); // unreachable

    feed::destroy_for_testing(market);
    teardown(v, ocap, pol, reg, creg, ccap, led);
    clock::destroy_for_testing(clk);
}

#[test]
#[expected_failure(abort_code = 3, location = policy)] // EPerTxCap
fun test_per_tx_cap_breach_aborts() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut v, ocap, mut pol, reg, creg, ccap, mut led) = setup(&mut ctx, &clk);

    let amount = 200_000; // > per_tx_cap (100_000)
    let derived = guardian::derive_risk_bps(amount, 1_000_000, 100_000_000);
    let t = warden::propose(&v, amount, guardian::dir_reduce(), derived);
    let verdict = critic::judge(&ccap, warden::trade_digest(&t), true);
    let market = feed_with(1_000_000, 100_000_000, &clk, &mut ctx);
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        &market, b"x", b"y", &clk,
    );
    ledger::receipt_seq(&r); // unreachable

    feed::destroy_for_testing(market);
    teardown(v, ocap, pol, reg, creg, ccap, led);
    clock::destroy_for_testing(clk);
}

#[test]
#[expected_failure(abort_code = 2, location = policy)] // EStaleGeneration
fun test_revocation_kills_policy() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut v, ocap, mut pol, mut reg, creg, ccap, mut led) = setup(&mut ctx, &clk);

    // admin (the dummy sender) revokes the whole generation
    policy::revoke_all(&mut reg, &ctx);

    let amount = 10_000;
    let derived = guardian::derive_risk_bps(amount, 1_000_000, 100_000_000);
    let t = warden::propose(&v, amount, guardian::dir_reduce(), derived);
    let verdict = critic::judge(&ccap, warden::trade_digest(&t), true);
    let market = feed_with(1_000_000, 100_000_000, &clk, &mut ctx);
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        &market, b"x", b"y", &clk,
    );
    ledger::receipt_seq(&r); // unreachable

    feed::destroy_for_testing(market);
    teardown(v, ocap, pol, reg, creg, ccap, led);
    clock::destroy_for_testing(clk);
}

#[test]
#[expected_failure(abort_code = 1, location = feed)] // EStale
fun test_feed_stale_read_aborts() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let market = feed_with(1_000_000, 100_000_000, &clk, &mut ctx); // max_age 1h
    clock::increment_for_testing(&mut clk, 3_600_001); // older than max_age
    let (_p, _d) = feed::read(&market, &clk); // stale → abort
    feed::destroy_for_testing(market);
    clock::destroy_for_testing(clk);
}

#[test]
#[expected_failure(abort_code = 0, location = feed)] // ENotFeeder
fun test_feed_only_feeder_updates() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let mut f = feed::new(@0xA, 3_600_000, &clk, &mut ctx); // feeder 0xA, sender 0x0
    feed::update(&mut f, 1, 1, &clk, &ctx); // sender != feeder → abort
    feed::destroy_for_testing(f);
    clock::destroy_for_testing(clk);
}
