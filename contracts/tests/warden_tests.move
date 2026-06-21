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

const ADMIN: address = @0xA;
const CRITIC: address = @0xC;

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

    let digest = b"trade-1";
    // low exposure, deep book → low risk; claim ~matches derived
    let amount = 10_000;
    let derived = guardian::derive_risk_bps(amount, 1_000_000, 100_000_000);
    let t = warden::propose(&v, amount, guardian::dir_increase(), derived, digest);
    let verdict = critic::judge(&ccap, digest, true);
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        1_000_000, 100_000_000, b"walrus-blob-1", b"tee-att-1", &clk,
    );

    assert!(ledger::receipt_accepted(&r), 100);
    assert!(ledger::seq(&led) == 1, 101);
    assert!(vault::deployed(&v) == amount, 102);
    assert!(!vault::is_frozen(&v), 103);

    teardown(v, ocap, pol, reg, creg, ccap, led);
    clock::destroy_for_testing(clk);
}

#[test]
fun test_divergence_freezes_and_records() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut v, ocap, mut pol, reg, creg, ccap, mut led) = setup(&mut ctx, &clk);

    let digest = b"trade-bad";
    let amount = 10_000;
    // agent LIES: claims 10 bps while the chain will derive far higher
    let t = warden::propose(&v, amount, guardian::dir_increase(), 10, digest);
    let verdict = critic::judge(&ccap, digest, true); // critic even approved it
    // thin book (depth 1000) → derived risk explodes → divergence fault
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        1_000_000, 1_000, b"walrus-blob-bad", b"tee-att-bad", &clk,
    );

    assert!(!ledger::receipt_accepted(&r), 200);   // rejected
    assert!(vault::is_frozen(&v), 201);            // chain froze the vault
    assert!(vault::deployed(&v) == 0, 202);        // nothing executed
    assert!(ledger::seq(&led) == 1, 203);          // but it IS on the record

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
#[expected_failure(abort_code = 3, location = policy)] // EPerTxCap
fun test_per_tx_cap_breach_aborts() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut v, ocap, mut pol, reg, creg, ccap, mut led) = setup(&mut ctx, &clk);

    let digest = b"too-big";
    let amount = 200_000; // > per_tx_cap (100_000)
    let derived = guardian::derive_risk_bps(amount, 1_000_000, 100_000_000);
    let t = warden::propose(&v, amount, guardian::dir_reduce(), derived, digest);
    let verdict = critic::judge(&ccap, digest, true);
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        1_000_000, 100_000_000, b"x", b"y", &clk,
    );
    ledger::receipt_seq(&r); // unreachable

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

    let digest = b"after-revoke";
    let amount = 10_000;
    let derived = guardian::derive_risk_bps(amount, 1_000_000, 100_000_000);
    let t = warden::propose(&v, amount, guardian::dir_reduce(), derived, digest);
    let verdict = critic::judge(&ccap, digest, true);
    let r = warden::settle(
        t, &mut v, &mut pol, &reg, &creg, verdict, &mut led,
        1_000_000, 100_000_000, b"x", b"y", &clk,
    );
    ledger::receipt_seq(&r); // unreachable

    teardown(v, ocap, pol, reg, creg, ccap, led);
    clock::destroy_for_testing(clk);
}
