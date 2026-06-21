#[test_only]
module warden::strategy_tests;

use sui::tx_context;
use sui::clock;
use warden::strategy;

// fixed test position: 1_000_000 notional, 0.5%/day carry, entry 1.0,
// put struck at 0.9, premium 2_000.
fun pos(ctx: &mut TxContext, clk: &clock::Clock): strategy::HedgedCarry {
    strategy::open(object::id_from_address(@0x1), 1_000_000, 50, 1_000_000, 900_000, 2_000, clk, ctx)
}

#[test]
fun test_carry_accrues_linearly() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let p = pos(&mut ctx, &clk);
    // +2 days
    clock::increment_for_testing(&mut clk, 172_800_000);
    assert!(strategy::carry_accrued(&p, clock::timestamp_ms(&clk)) == 10_000, 1);
    strategy::destroy_for_testing(p);
    clock::destroy_for_testing(clk);
}

#[test]
fun test_hedge_pays_below_strike_only() {
    let mut ctx = tx_context::dummy();
    let clk = clock::create_for_testing(&mut ctx);
    let p = pos(&mut ctx, &clk);
    assert!(strategy::hedge_payout(&p, 950_000) == 0, 1);        // above strike: no payout
    assert!(strategy::hedge_payout(&p, 800_000) == 100_000, 2);  // below strike: pays
    strategy::destroy_for_testing(p);
    clock::destroy_for_testing(clk);
}

#[test]
fun test_drawdown_is_bounded() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let p = pos(&mut ctx, &clk);
    clock::increment_for_testing(&mut clk, 172_800_000); // 2 days carry = 10_000
    let now = clock::timestamp_ms(&clk);

    // loss at price just below strike
    let (prof1, mag1) = strategy::settle_pnl(&p, 800_000, now);
    // loss at total wipeout (price = 0)
    let (prof2, mag2) = strategy::settle_pnl(&p, 0, now);

    assert!(!prof1 && !prof2, 1);
    assert!(mag1 == mag2, 2);                       // loss does NOT grow below strike
    assert!(mag1 == 92_000, 3);                     // floor(102_000) - carry(10_000)
    assert!(mag1 <= strategy::drawdown_floor(&p), 4); // never exceeds the proven floor

    strategy::destroy_for_testing(p);
    clock::destroy_for_testing(clk);
}
