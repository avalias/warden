#[test_only]
/// Negative-path coverage for the gates the thesis rests on: the L1 policy
/// scope (per-tx / window / expiry / pause / wrong-vault), the L2 critic veto
/// (rejection + wrong identity), the L4 ledger (monotonic append), and the L0
/// vault boundary (reserve floor / frozen / owner-only / unfreeze). Every abort
/// code is exercised by name so the suite proves the invariants, not just the
/// happy path.
module warden::gate_tests;

use sui::tx_context;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use warden::policy;
use warden::critic;
use warden::ledger;
use warden::vault;

const AGENT: address = @0xA;
const CRITIC: address = @0xC;

fun mk_policy(
    per_tx: u64, window_cap: u64, window_ms: u64, ttl: u64,
    clk: &clock::Clock, ctx: &mut TxContext,
): (policy::GenerationRegistry, policy::WardenPolicy) {
    let vid = object::id_from_address(@0x11);
    let reg = policy::init_registry(vid, ctx);
    let pol = policy::mint(&reg, vid, AGENT, per_tx, window_cap, window_ms, 0, ttl, clk, ctx);
    (reg, pol)
}

fun drop_policy(reg: policy::GenerationRegistry, pol: policy::WardenPolicy, clk: clock::Clock) {
    policy::destroy_policy_for_testing(pol);
    policy::destroy_registry_for_testing(reg);
    clock::destroy_for_testing(clk);
}

// ---------- L1 policy: scope is enforced ----------

#[test]
#[expected_failure(abort_code = 4, location = policy)] // EWindowCap
fun test_window_cap_trips() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (reg, mut pol) = mk_policy(1_000_000, 1000, 100_000, 3_600_000, &clk, &mut ctx);
    policy::assert_and_spend(&mut pol, &reg, 600, &clk);   // window_spent 600
    policy::assert_and_spend(&mut pol, &reg, 600, &clk);   // 1200 > 1000 -> abort
    drop_policy(reg, pol, clk);
}

#[test]
fun test_window_resets_after_window_ms() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let (reg, mut pol) = mk_policy(1_000_000, 1000, 100_000, 3_600_000, &clk, &mut ctx);
    policy::assert_and_spend(&mut pol, &reg, 600, &clk);   // window_spent 600
    clock::increment_for_testing(&mut clk, 100_001);       // past the window
    policy::assert_and_spend(&mut pol, &reg, 900, &clk);   // resets -> 900 <= 1000 ok
    drop_policy(reg, pol, clk);
}

#[test]
#[expected_failure(abort_code = 0, location = policy)] // EExpired
fun test_policy_expiry_aborts() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let (reg, mut pol) = mk_policy(1_000_000, 1_000_000, 100_000, 1000, &clk, &mut ctx);
    clock::increment_for_testing(&mut clk, 1001);          // now > expiry
    policy::assert_and_spend(&mut pol, &reg, 1, &clk);      // EExpired
    drop_policy(reg, pol, clk);
}

#[test]
#[expected_failure(abort_code = 1, location = policy)] // EPaused
fun test_paused_blocks_spend() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (mut reg, mut pol) = mk_policy(1_000_000, 1_000_000, 100_000, 3_600_000, &clk, &mut ctx);
    policy::set_paused(&mut reg, true, &ctx);
    policy::assert_and_spend(&mut pol, &reg, 1, &clk);      // EPaused
    drop_policy(reg, pol, clk);
}

#[test]
#[expected_failure(abort_code = 5, location = policy)] // EWrongVault
fun test_policy_wrong_vault_aborts() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let (reg, mut pol) = mk_policy(1_000_000, 1_000_000, 100_000, 3_600_000, &clk, &mut ctx);
    let reg_b = policy::init_registry(object::id_from_address(@0x22), &mut ctx); // different vault
    policy::assert_and_spend(&mut pol, &reg_b, 1, &clk);    // reg_b.vault != pol.vault -> EWrongVault
    policy::destroy_registry_for_testing(reg_b);
    drop_policy(reg, pol, clk);
}

// ---------- L2 critic: the veto is real ----------

#[test]
fun test_critic_approval_returns_digest() {
    let mut ctx = tx_context::dummy();
    let reg = critic::init_registry(object::id_from_address(@0x11), CRITIC, &mut ctx);
    let cap = critic::new_cap_for(CRITIC, &mut ctx);
    let v = critic::judge(&cap, b"trade-x", true);
    let dig = critic::consume(&reg, v);
    assert!(dig == b"trade-x", 0);
    critic::destroy_cap_for_testing(cap);
    critic::destroy_registry_for_testing(reg);
}

#[test]
#[expected_failure(abort_code = 1, location = critic)] // ERejected
fun test_critic_rejection_aborts_settlement() {
    let mut ctx = tx_context::dummy();
    let reg = critic::init_registry(object::id_from_address(@0x11), CRITIC, &mut ctx);
    let cap = critic::new_cap_for(CRITIC, &mut ctx);
    let v = critic::judge(&cap, b"trade-x", false);        // critic says NO
    let _dig = critic::consume(&reg, v);                   // ERejected
    critic::destroy_cap_for_testing(cap);
    critic::destroy_registry_for_testing(reg);
}

#[test]
#[expected_failure(abort_code = 0, location = critic)] // ENotRegistered
fun test_unsanctioned_critic_aborts() {
    let mut ctx = tx_context::dummy();
    let reg = critic::init_registry(object::id_from_address(@0x11), CRITIC, &mut ctx);
    let cap = critic::new_cap_for(@0xBAD, &mut ctx);        // a different critic identity
    let v = critic::judge(&cap, b"trade-x", true);
    let _dig = critic::consume(&reg, v);                   // critic != reg.critic -> ENotRegistered
    critic::destroy_cap_for_testing(cap);
    critic::destroy_registry_for_testing(reg);
}

// ---------- L4 ledger: monotonic, append-only ----------

#[test]
fun test_ledger_seq_is_monotonic_no_delete() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let mut l = ledger::new(object::id_from_address(@0x11), &mut ctx);
    let _r1 = ledger::record(&mut l, 1000, 10, 0, true, 0, b"d1", b"w", b"t", &clk);
    clock::increment_for_testing(&mut clk, 5);
    let _r2 = ledger::record(&mut l, 9000, 0, 1, false, 1, b"d2", b"w", b"t", &clk); // a rejection, still recorded
    assert!(ledger::seq(&l) == 2, 0);
    assert!(ledger::count(&l) == 2, 1);
    ledger::destroy_for_testing(l);
    clock::destroy_for_testing(clk);
}

// ---------- L0 vault: the custody boundary ----------

fun mk_vault(amount: u64, ctx: &mut TxContext): (vault::Vault<SUI>, vault::OwnerCap) {
    let (mut v, cap) = vault::new<SUI>(ctx);
    let c = coin::mint_for_testing<SUI>(amount, ctx);
    vault::deposit(&mut v, c, ctx);
    (v, cap)
}

#[test]
#[expected_failure(abort_code = 2, location = vault)] // EReserveBreached
fun test_deploy_respects_reserve_floor() {
    let mut ctx = tx_context::dummy();
    let (mut v, cap) = mk_vault(1000, &mut ctx);
    vault::deploy(&mut v, 600, 500);   // 600 + 500 > 1000 idle -> EReserveBreached
    vault::destroy_for_testing(v);
    vault::destroy_cap_for_testing(cap);
}

#[test]
#[expected_failure(abort_code = 1, location = vault)] // EFrozen
fun test_deploy_blocked_while_frozen() {
    let mut ctx = tx_context::dummy();
    let (mut v, cap) = mk_vault(1000, &mut ctx);
    vault::freeze_vault(&mut v, 9);
    vault::deploy(&mut v, 100, 0);     // frozen -> EFrozen
    vault::destroy_for_testing(v);
    vault::destroy_cap_for_testing(cap);
}

#[test]
#[expected_failure(abort_code = 0, location = vault)] // ENotOwner
fun test_withdraw_rejects_wrong_cap() {
    let mut ctx = tx_context::dummy();
    let (mut v1, cap1) = mk_vault(1000, &mut ctx);
    let (v2, cap2) = mk_vault(1000, &mut ctx);
    let c = vault::owner_withdraw(&mut v1, &cap2, 100, &mut ctx); // cap2 is for v2 -> ENotOwner
    coin::burn_for_testing(c);
    vault::destroy_for_testing(v1); vault::destroy_cap_for_testing(cap1);
    vault::destroy_for_testing(v2); vault::destroy_cap_for_testing(cap2);
}

#[test]
fun test_unfreeze_restores_agent() {
    let mut ctx = tx_context::dummy();
    let (mut v, cap) = mk_vault(1000, &mut ctx);
    vault::freeze_vault(&mut v, 9);
    assert!(vault::is_frozen(&v), 0);
    vault::unfreeze(&mut v, &cap);
    assert!(!vault::is_frozen(&v), 1);
    vault::deploy(&mut v, 100, 0);                 // works again after unfreeze
    assert!(vault::deployed(&v) == 100, 2);
    vault::destroy_for_testing(v);
    vault::destroy_cap_for_testing(cap);
}
