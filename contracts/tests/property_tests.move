#[test_only]
/// Property / adversarial sweeps for the invariants the whole thesis rests on:
/// "the agent is structurally incapable of harm." Where `gate_tests` pins each
/// abort code with one hand-picked case, this module sweeps THOUSANDS of
/// synthetic market states, agent claims, and op sequences and asserts the
/// safety invariants hold for ALL of them — empirical evidence, not a single
/// happy path. Deterministic (a tiny LCG + fixed grids), so it is reproducible
/// and runs under `sui move test` with no external toolchain.
module warden::property_tests;

use sui::tx_context;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use std::bcs;
use warden::guardian;
use warden::vault;
use warden::ledger;

fun mk_vault(amount: u64, ctx: &mut TxContext): (vault::Vault<SUI>, vault::OwnerCap) {
    let (mut v, cap) = vault::new<SUI>(ctx);
    let c = coin::mint_for_testing<SUI>(amount, ctx);
    vault::deposit(&mut v, c, ctx);
    (v, cap)
}

// ---------- L2 guardian: the chain never approves an unsafe trade ----------

#[test]
/// Sweep a grid of (exposure, price, depth, claimed_risk, direction) and assert,
/// for every approved trade: it is under the ceiling, the agent's claim is within
/// tolerance of the chain's own number, and in the danger zone only de-risking is
/// allowed. Also asserts the dual: a claim that lowballs the truth is NEVER ok.
fun prop_guardian_never_approves_unsafe() {
    let exposures = vector[0u64, 1_000, 50_000, 500_000, 5_000_000, 50_000_000];
    let prices    = vector[1u64, 1_000_000, 2_000_000, 5_000_000, 20_000_000];
    let depths    = vector[0u64, 1_000, 100_000, 10_000_000, 1_000_000_000];
    let claims    = vector[0u64, 1_500, 3_400, 3_600, 5_000, 6_900, 7_100, 10_000];
    let dirs      = vector[0u8, 1u8];

    let ceiling = guardian::risk_ceiling_bps();
    let tol = guardian::max_divergence_bps();

    let mut ok_count = 0u64;
    let mut fault_count = 0u64;
    let mut lie_caught = 0u64;
    let mut iters = 0u64;

    let ne = vector::length(&exposures);
    let np = vector::length(&prices);
    let nd = vector::length(&depths);
    let nc = vector::length(&claims);
    let ndir = vector::length(&dirs);

    let mut ie = 0;
    while (ie < ne) {
        let e = *vector::borrow(&exposures, ie);
        let mut ip = 0;
        while (ip < np) {
            let p = *vector::borrow(&prices, ip);
            let mut id = 0;
            while (id < nd) {
                let d = *vector::borrow(&depths, id);
                let truth = guardian::derive_risk_bps(e, p, d);
                assert!(truth <= 10_000, 100);                 // derive is bounded
                let mut ic = 0;
                while (ic < nc) {
                    let claimed = *vector::borrow(&claims, ic);
                    let mut idir = 0;
                    while (idir < ndir) {
                        let dir = *vector::borrow(&dirs, idir);
                        let a = guardian::evaluate(claimed, dir, e, p, d);
                        iters = iters + 1;
                        assert!(guardian::derived(&a) == truth, 101); // evaluate agrees with pure derive
                        if (guardian::ok(&a)) {
                            ok_count = ok_count + 1;
                            assert!(guardian::derived(&a) <= ceiling, 1);            // INV1: under the ceiling
                            let diff = if (truth > claimed) { truth - claimed } else { claimed - truth };
                            assert!(diff <= tol, 2);                                 // INV2: claim within tolerance
                            if (truth > ceiling / 2) {
                                assert!(dir == guardian::dir_reduce(), 3);           // INV3: danger zone => de-risk only
                            };
                        } else {
                            fault_count = fault_count + 1;
                        };
                        if (claimed + tol < truth) {                                 // a lowballed risk claim...
                            assert!(!guardian::ok(&a), 4);                           // ...is never approved
                            lie_caught = lie_caught + 1;
                        };
                        idir = idir + 1;
                    };
                    ic = ic + 1;
                };
                id = id + 1;
            };
            ip = ip + 1;
        };
        ie = ie + 1;
    };

    // the sweep is real: it covered both verdicts and actually caught lies
    assert!(iters >= 2_000, 10);
    assert!(ok_count > 0, 11);
    assert!(fault_count > 0, 12);
    assert!(lie_caught > 0, 13);
}

#[test]
/// The risk re-derivation is monotone the way the thesis needs: bigger exposure
/// or price ⇒ not-less risk; deeper book ⇒ not-more risk. A book the agent
/// cannot thin into looking safe.
fun prop_derive_is_monotone() {
    // non-decreasing in exposure
    let mut prev = 0u64; let mut e = 0u64;
    while (e <= 2_000_000) {
        let r = guardian::derive_risk_bps(e, 1_000_000, 100_000);
        assert!(r >= prev, 1); prev = r; e = e + 100_000;
    };
    // non-decreasing in price
    let mut prevp = 0u64; let mut pr = 0u64;
    while (pr <= 20_000_000) {
        let r = guardian::derive_risk_bps(500_000, pr, 100_000);
        assert!(r >= prevp, 2); prevp = r; pr = pr + 1_000_000;
    };
    // non-increasing in depth (depth grows ×10 from 1)
    let mut prevd = 10_001u64; let mut dd = 1u64;
    while (dd <= 100_000_000) {
        let r = guardian::derive_risk_bps(1_000_000, 1_000_000, dd);
        assert!(r <= prevd, 3); prevd = r; dd = dd * 10;
    };
}

// ---------- L0 vault: custody is conserved; only the owner can shrink it ----------

#[test]
/// 400 pseudo-random deploy/undeploy moves by the "agent". After every single
/// move the vault's NAV is unchanged — steering capital can never create or
/// destroy it. Then the owner withdraws, and that is the ONLY thing that moves NAV.
fun prop_custody_nav_conserved_under_agent_ops() {
    let mut ctx = tx_context::dummy();
    let deposit_amt = 1_000_000u64;
    let (mut v, cap) = mk_vault(deposit_amt, &mut ctx);
    assert!(vault::nav(&v) == deposit_amt, 0);

    let mut seed = 12_345u64;
    let mut k = 0u64;
    while (k < 400) {
        seed = (seed * 1_103_515_245 + 12_345) % 2_147_483_648;  // 31-bit LCG, no overflow
        if (seed % 2 == 0) {
            let idle = vault::idle_value(&v);
            let amt = if (idle == 0) { 0 } else { seed % (idle + 1) };
            vault::deploy(&mut v, amt, 0);              // amt <= idle, floor 0 => never aborts
        } else {
            let dep = vault::deployed(&v);
            let amt = if (dep == 0) { 0 } else { seed % (dep + 1) };
            vault::undeploy(&mut v, amt);
        };
        assert!(vault::nav(&v) == deposit_amt, 1);                       // NAV conserved
        assert!(vault::idle_value(&v) + vault::deployed(&v) == deposit_amt, 2);
        k = k + 1;
    };

    // pull everything home, then the owner — and ONLY the owner — reduces NAV
    let dep = vault::deployed(&v);
    vault::undeploy(&mut v, dep);
    let w = 250_000u64;
    let coinout = vault::owner_withdraw(&mut v, &cap, w, &mut ctx);
    assert!(coin::value(&coinout) == w, 3);
    assert!(vault::nav(&v) == deposit_amt - w, 4);

    coin::burn_for_testing(coinout);
    vault::destroy_for_testing(v);
    vault::destroy_cap_for_testing(cap);
}

#[test]
/// For every deploy the reserve permits, the reserve floor still sits in idle
/// afterwards and NAV is conserved. The agent can steer, but never raid the floor.
fun prop_reserve_floor_always_respected() {
    let mut ctx = tx_context::dummy();
    let floors = vector[0u64, 100, 1_000, 5_000];
    let amounts = vector[0u64, 1, 500, 4_000, 9_000];
    let total = 10_000u64;
    let nf = vector::length(&floors);
    let na = vector::length(&amounts);
    let mut checks = 0u64;

    let mut jf = 0;
    while (jf < nf) {
        let r = *vector::borrow(&floors, jf);
        let mut ja = 0;
        while (ja < na) {
            let amt = *vector::borrow(&amounts, ja);
            if (amt + r <= total) {                         // only the deploys the floor allows
                let (mut v, cap) = mk_vault(total, &mut ctx);
                vault::deploy(&mut v, amt, r);
                assert!(vault::idle_value(&v) >= r, 1);     // floor preserved
                assert!(vault::idle_value(&v) == total - amt, 2);
                assert!(vault::deployed(&v) == amt, 3);
                assert!(vault::nav(&v) == total, 4);        // still conserved
                vault::destroy_for_testing(v);
                vault::destroy_cap_for_testing(cap);
                checks = checks + 1;
            };
            ja = ja + 1;
        };
        jf = jf + 1;
    };
    assert!(checks > 0, 5);
}

// ---------- L4 ledger: the hash chain is monotone and tamper-evident ----------

#[test]
/// Append 200 distinct entries. The sequence never skips, the keccak chain head
/// is a 32-byte digest that advances on every append (so a dropped or forged
/// entry breaks the chain), and each receipt carries the matching chain head.
fun prop_ledger_chain_advances_and_is_monotone() {
    let mut ctx = tx_context::dummy();
    let mut clk = clock::create_for_testing(&mut ctx);
    let mut l = ledger::new(object::id_from_address(@0x11), &mut ctx);

    let n = 200u64;
    let mut i = 0u64;
    let mut prev_head = vector::empty<u8>();
    while (i < n) {
        let dig = bcs::to_bytes(&i);                                   // distinct digest per entry
        let r = ledger::record(&mut l, 1_000 + i, i, ((i % 2) as u8), true, 0, dig, b"w", b"t", &clk);
        assert!(ledger::seq(&l) == i + 1, 1);                          // monotonic, no gaps
        assert!(ledger::count(&l) == i + 1, 2);
        let head = ledger::chain_head(&l);
        assert!(vector::length(&head) == 32, 3);                       // keccak head present
        assert!(head != prev_head, 4);                                 // chain moves every append
        assert!(ledger::receipt_entry_digest(&r) == head, 5);          // receipt anchors to the head
        prev_head = head;
        clock::increment_for_testing(&mut clk, 1);                     // non-backdated time
        i = i + 1;
    };
    assert!(ledger::seq(&l) == n, 6);

    ledger::destroy_for_testing(l);
    clock::destroy_for_testing(clk);
}
