#[test_only]
module warden::l5_l6_tests;

use sui::tx_context;
use sui::clock;
use sui::hash;
use warden::compliance;
use warden::oracle;
use warden::inheritance;
use warden::prize;

const A: address = @0xA;
const B: address = @0xB;

// ---------- L5: compliance ----------

#[test]
fun test_kyc_gates_recipients() {
    let mut ctx = tx_context::dummy();
    let mut reg = compliance::init_registry(&mut ctx);
    compliance::set_verified(&mut reg, A, true, &ctx);
    assert!(compliance::is_verified(&reg, A), 1);
    assert!(!compliance::is_verified(&reg, B), 2);
    compliance::assert_can_receive(&reg, A); // ok
    compliance::set_verified(&mut reg, A, false, &ctx); // revoke
    assert!(!compliance::is_verified(&reg, A), 3);
    compliance::destroy_for_testing(reg);
}

#[test]
#[expected_failure(abort_code = 0, location = compliance)] // ENotVerified
fun test_unverified_recipient_aborts() {
    let mut ctx = tx_context::dummy();
    let reg = compliance::init_registry(&mut ctx);
    compliance::assert_can_receive(&reg, B); // B never verified
    compliance::destroy_for_testing(reg);
}

// ---------- L5: optimistic oracle ----------

#[test]
fun test_oracle_finalizes_after_window() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let mut c = oracle::propose(b"BTC>100k?", @0x0, 7, 1000, 1000, &clk, &mut ctx);
    clock::increment_for_testing(&mut clk, 1000);
    let o = oracle::finalize(&mut c, &clk);
    assert!(o == 7 && oracle::is_final(&c), 1);
    oracle::destroy_for_testing(c);
    clock::destroy_for_testing(clk);
}

#[test]
#[expected_failure(abort_code = 0, location = oracle)] // EWindowOpen
fun test_oracle_finalize_before_window_aborts() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let mut c = oracle::propose(b"q", @0x0, 1, 1000, 1000, &clk, &mut ctx);
    oracle::finalize(&mut c, &clk); // window still open
    oracle::destroy_for_testing(c);
    clock::destroy_for_testing(clk);
}

#[test]
fun test_oracle_dispute_then_resolver_decides() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let mut c = oracle::propose(b"q", @0x0, 1, 1000, 1000, &clk, &mut ctx);
    oracle::dispute(&mut c, &clk);            // within window
    assert!(oracle::disputed(&c), 1);
    let o = oracle::resolve(&mut c, 9, &ctx);  // resolver == sender == @0x0
    assert!(o == 9 && oracle::is_final(&c), 2);
    oracle::destroy_for_testing(c);
    clock::destroy_for_testing(clk);
}

// ---------- L6: dead-man-switch inheritance ----------

#[test]
fun test_inheritance_claim_after_dormancy() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let mut s = inheritance::new(B, 1000, &clk, &mut ctx); // owner == @0x0
    clock::increment_for_testing(&mut clk, 1000);
    let new_owner = inheritance::claim(&mut s, &clk);
    assert!(new_owner == B && inheritance::owner(&s) == B, 1);
    inheritance::destroy_for_testing(s);
    clock::destroy_for_testing(clk);
}

#[test]
#[expected_failure(abort_code = 1, location = inheritance)] // ETooEarly
fun test_inheritance_claim_too_early_aborts() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let mut s = inheritance::new(B, 1000, &clk, &mut ctx);
    inheritance::claim(&mut s, &clk); // no dormancy elapsed
    inheritance::destroy_for_testing(s);
    clock::destroy_for_testing(clk);
}

#[test]
fun test_inheritance_ping_resets_clock() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let mut s = inheritance::new(B, 1000, &clk, &mut ctx);
    clock::increment_for_testing(&mut clk, 600);
    inheritance::ping(&mut s, &clk, &ctx);      // reset at t=600
    clock::increment_for_testing(&mut clk, 600); // t=1200, but last_ping=600
    assert!(!inheritance::can_claim(&s, clock::timestamp_ms(&clk)), 1);
    inheritance::destroy_for_testing(s);
    clock::destroy_for_testing(clk);
}

// ---------- L6: no-loss prize draw ----------

#[test]
fun test_prize_commit_reveal_draw_no_loss() {
    let mut ctx = tx_context::dummy();
    let mut pool = prize::new(&mut ctx);
    prize::deposit(&mut pool, 1_000_000);
    prize::fund_yield(&mut pool, 5_000);

    let i0 = prize::commit(&mut pool, hash::keccak256(&b"alice-seed"));
    let i1 = prize::commit(&mut pool, hash::keccak256(&b"bob-seed"));
    prize::reveal(&mut pool, i0, b"alice-seed");
    prize::reveal(&mut pool, i1, b"bob-seed");

    let w = prize::draw(&pool);
    assert!(w < 2, 1);                          // a valid winner index
    assert!(prize::principal(&pool) == 1_000_000, 2); // principal untouched — no loss
    assert!(prize::players(&pool) == 2, 3);
    prize::destroy_for_testing(pool);
}

#[test]
#[expected_failure(abort_code = 0, location = prize)] // EBadReveal
fun test_prize_bad_reveal_aborts() {
    let mut ctx = tx_context::dummy();
    let mut pool = prize::new(&mut ctx);
    let i0 = prize::commit(&mut pool, hash::keccak256(&b"secret"));
    prize::reveal(&mut pool, i0, b"not-the-secret");
    prize::destroy_for_testing(pool);
}
