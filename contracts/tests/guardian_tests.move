#[test_only]
/// Direct unit tests for L2 — the heart. The guardian is the one subsystem the
/// whole thesis rests on, so every fault branch and boundary is pinned here:
/// the risk re-derivation arithmetic, the divergence tolerance boundary, the
/// hard ceiling, and the safe-direction clamp (both ways). Pure functions, no
/// fixture needed — these assert the invariants the chain enforces on the agent.
module warden::guardian_tests;

use warden::guardian;

// derive_risk_bps: pin the exact arithmetic on known triples.
#[test]
fun test_derive_known_triples() {
    // exposure 1e6, price 1.0, deep book (depth 1e7) → notional 1e6, bps = 1e6*1e4/1e7 = 1000
    assert!(guardian::derive_risk_bps(1_000_000, 1_000_000, 10_000_000) == 1000, 0);
    // thin book (depth 1000) → bps explodes and saturates at the 10000 cap
    assert!(guardian::derive_risk_bps(1_000_000, 1_000_000, 1000) == 10_000, 1);
    // depth == 0 (no liquidity): guarded against divide-by-zero, saturates to max risk
    assert!(guardian::derive_risk_bps(1_000_000, 1_000_000, 0) == 10_000, 2);
}

// FAULT_DIVERGED(1): the chain does not trust the agent's claimed number.
// derived = 1000 for (1e6, 1e6, 1e7); tolerance is 200.
#[test]
fun test_divergence_boundary() {
    // |1000 - 800| == 200 → within tolerance → accepted
    let a = guardian::evaluate(800, guardian::dir_increase(), 1_000_000, 1_000_000, 10_000_000);
    assert!(guardian::ok(&a), 0);
    // |1000 - 799| == 201 > 200 → FAULT_DIVERGED
    let b = guardian::evaluate(799, guardian::dir_increase(), 1_000_000, 1_000_000, 10_000_000);
    assert!(!guardian::ok(&b) && guardian::fault(&b) == 1, 1);
}

// FAULT_CEILING(2): derived = 8000 > 7000 ceiling. A truthful claim and a
// de-risking direction do NOT save it — the hard ceiling fires regardless.
#[test]
fun test_ceiling_fault() {
    let a = guardian::evaluate(8000, guardian::dir_reduce(), 8_000_000, 1_000_000, 10_000_000);
    assert!(!guardian::ok(&a) && guardian::fault(&a) == 2, 0);
}

// FAULT_UNSAFE_DIR(3): the headline clamp. derived = 5000 is in the danger
// zone (> ceiling/2 = 3500); an exposure-INCREASING trade is rejected.
#[test]
fun test_unsafe_dir_increase_freezes() {
    let a = guardian::evaluate(5000, guardian::dir_increase(), 5_000_000, 1_000_000, 10_000_000);
    assert!(!guardian::ok(&a) && guardian::fault(&a) == 3, 0);
}

// The other side of the clamp: same danger-zone risk, but a de-risking
// (REDUCE) trade is always allowed through.
#[test]
fun test_unsafe_dir_reduce_accepts() {
    let a = guardian::evaluate(5000, guardian::dir_reduce(), 5_000_000, 1_000_000, 10_000_000);
    assert!(guardian::ok(&a), 0);
}

// Robustness: adversarial near-u64::MAX exposure must SATURATE to 10000,
// never overflow or abort the settle path (a freeze, not a DoS).
#[test]
fun test_extreme_inputs_saturate() {
    let bps = guardian::derive_risk_bps(18_446_744_073_709_551_615, 1_000_000, 1);
    assert!(bps == 10_000, 0);
}
