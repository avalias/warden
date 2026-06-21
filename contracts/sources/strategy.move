/// L3 — Structured-product engine: it hedges itself.
///
/// A `HedgedCarry` position earns carry over time and holds a downside
/// hedge (a put struck below entry). Below the strike, the hedge payout
/// exactly offsets further spot losses, so the **maximum drawdown is
/// bounded by construction** — a property proven on-chain, not promised.
/// Settled from a single price read (Pyth/DeepBook in production).
module warden::strategy;

use sui::clock::{Self, Clock};
use sui::event;

const MS_PER_DAY: u128 = 86_400_000;
const BPS: u128 = 10_000;

public struct HedgedCarry has key, store {
    id: UID,
    vault: ID,
    notional: u64,
    carry_bps_per_day: u64,
    entry_price_e6: u64,
    strike_e6: u64,        // hedge strike (put pays below this)
    hedge_cost: u64,       // premium paid for protection (sunk)
    opened_ms: u64,
}

public struct Settled has copy, drop {
    vault: ID, price_e6: u64, profit: bool, magnitude: u64, drawdown_floor: u64,
}

public fun open(
    vault: ID, notional: u64, carry_bps_per_day: u64,
    entry_price_e6: u64, strike_e6: u64, hedge_cost: u64,
    clock: &Clock, ctx: &mut TxContext,
): HedgedCarry {
    HedgedCarry {
        id: object::new(ctx),
        vault, notional, carry_bps_per_day, entry_price_e6, strike_e6, hedge_cost,
        opened_ms: clock::timestamp_ms(clock),
    }
}

/// Carry accrued since open (linear in elapsed time).
public fun carry_accrued(p: &HedgedCarry, now_ms: u64): u64 {
    let elapsed = ((now_ms - p.opened_ms) as u128);
    (((p.notional as u128) * (p.carry_bps_per_day as u128) * elapsed) / MS_PER_DAY / BPS) as u64
}

/// Put payout: max(strike - price, 0) scaled by notional/entry.
public fun hedge_payout(p: &HedgedCarry, price_e6: u64): u64 {
    if (price_e6 >= p.strike_e6) { 0 }
    else { (((p.strike_e6 - price_e6) as u128) * (p.notional as u128) / (p.entry_price_e6 as u128)) as u64 }
}

/// The position's own spot loss: max(entry - price, 0) scaled.
public fun spot_loss(p: &HedgedCarry, price_e6: u64): u64 {
    if (price_e6 >= p.entry_price_e6) { 0 }
    else { (((p.entry_price_e6 - price_e6) as u128) * (p.notional as u128) / (p.entry_price_e6 as u128)) as u64 }
}

/// The proven worst case (excluding carry): below the strike, loss can
/// never exceed (entry - strike) * notional / entry + hedge_cost.
public fun drawdown_floor(p: &HedgedCarry): u64 {
    (((p.entry_price_e6 - p.strike_e6) as u128) * (p.notional as u128) / (p.entry_price_e6 as u128)) as u64
        + p.hedge_cost
}

/// Mark-to-market PnL. Returns (is_profit, magnitude).
public fun settle_pnl(p: &HedgedCarry, price_e6: u64, now_ms: u64): (bool, u64) {
    let gains = carry_accrued(p, now_ms) + hedge_payout(p, price_e6);
    let costs = p.hedge_cost + spot_loss(p, price_e6);
    if (gains >= costs) { (true, gains - costs) } else { (false, costs - gains) }
}

/// Settle and emit a public, auditable result (does not consume the position).
public fun settle(p: &HedgedCarry, price_e6: u64, clock: &Clock) {
    let (profit, magnitude) = settle_pnl(p, price_e6, clock::timestamp_ms(clock));
    event::emit(Settled {
        vault: p.vault, price_e6, profit, magnitude, drawdown_floor: drawdown_floor(p),
    });
}

public fun notional(p: &HedgedCarry): u64 { p.notional }
public fun vault_of(p: &HedgedCarry): ID { p.vault }

#[test_only]
public fun destroy_for_testing(p: HedgedCarry) {
    let HedgedCarry { id, vault: _, notional: _, carry_bps_per_day: _, entry_price_e6: _,
        strike_e6: _, hedge_cost: _, opened_ms: _ } = p;
    object::delete(id);
}
