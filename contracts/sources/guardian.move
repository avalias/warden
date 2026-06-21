/// L2 — The chain never trusts the AI. (The heart.)
///
/// A deterministic, pure re-derivation of position risk from raw inputs
/// the agent cannot forge (oracle price, order-book depth, exposure). The
/// agent's CLAIMED risk is checked against the chain's own computation;
/// divergence beyond tolerance is a fault. Above a danger threshold the
/// agent is clamped to the risk-reducing direction only, and a hard
/// surface-anchored ceiling is enforced.
module warden::guardian;

const DIR_REDUCE: u8 = 0;
const DIR_INCREASE: u8 = 1;

const FAULT_NONE: u8 = 0;
const FAULT_DIVERGED: u8 = 1;
const FAULT_CEILING: u8 = 2;
const FAULT_UNSAFE_DIR: u8 = 3;

/// Result of the on-chain assessment. `ok = false` means the caller must
/// freeze the vault rather than execute.
public struct Assessment has copy, drop {
    ok: bool,
    derived_bps: u64,
    fault: u8,
}

/// Re-derive position risk (basis points) from raw market state. Thin
/// books and large exposure ⇒ high risk. Pure, monotone, and impossible
/// for the agent to spoof, because it is recomputed on-chain.
public fun derive_risk_bps(exposure: u64, price_e6: u64, depth: u64): u64 {
    let notional = (exposure as u128) * (price_e6 as u128) / 1_000_000;
    let d = if (depth == 0) { 1u128 } else { (depth as u128) };
    let bps = notional * 10_000 / d;
    if (bps > 10_000) { 10_000 } else { (bps as u64) }
}

public fun max_divergence_bps(): u64 { 200 }   // 2% tolerance on the agent's claim
public fun risk_ceiling_bps(): u64 { 7_000 }   // 70% hard, surface-anchored ceiling

/// The heart check. Never aborts — returns a verdict so the orchestrator
/// can freeze-and-record on a fault instead of silently reverting.
public fun evaluate(
    claimed_bps: u64,
    direction: u8,
    exposure_after: u64,
    price_e6: u64,
    depth: u64,
): Assessment {
    let derived = derive_risk_bps(exposure_after, price_e6, depth);

    // 1) the chain does not trust the agent's number
    let diff = if (derived > claimed_bps) { derived - claimed_bps } else { claimed_bps - derived };
    if (diff > max_divergence_bps()) {
        return Assessment { ok: false, derived_bps: derived, fault: FAULT_DIVERGED }
    };

    // 2) hard surface-anchored ceiling
    if (derived > risk_ceiling_bps()) {
        return Assessment { ok: false, derived_bps: derived, fault: FAULT_CEILING }
    };

    // 3) safe-direction clamp: in the danger zone, only de-risking is allowed
    if (derived > risk_ceiling_bps() / 2 && direction != DIR_REDUCE) {
        return Assessment { ok: false, derived_bps: derived, fault: FAULT_UNSAFE_DIR }
    };

    Assessment { ok: true, derived_bps: derived, fault: FAULT_NONE }
}

public fun ok(a: &Assessment): bool { a.ok }
public fun derived(a: &Assessment): u64 { a.derived_bps }
public fun fault(a: &Assessment): u8 { a.fault }
public fun dir_reduce(): u8 { DIR_REDUCE }
public fun dir_increase(): u8 { DIR_INCREASE }
