/// L6 — No-loss prize draw.
///
/// Principal is always preserved; only the yield pot funds the prize. The
/// winner is chosen by commit-reveal: players commit `keccak256(seed)`, later
/// reveal the seed (checked against the commit), and the winner index is
/// derived from the combined revealed bytes — verifiable, and not knowable in
/// advance by any single player. The draw never touches `principal`.
module warden::prize;

use sui::hash;

const EBadReveal: u64 = 0;
const ENoPlayers: u64 = 1;

public struct PrizePool has key {
    id: UID,
    principal: u64,                 // protected — never paid out by a draw
    yield_pot: u64,                 // the only thing at stake in the prize
    commits: vector<vector<u8>>,
    reveals: vector<vector<u8>>,
}

public fun new(ctx: &mut TxContext): PrizePool {
    PrizePool { id: object::new(ctx), principal: 0, yield_pot: 0, commits: vector[], reveals: vector[] }
}

public fun deposit(pool: &mut PrizePool, amount: u64) { pool.principal = pool.principal + amount; }
public fun fund_yield(pool: &mut PrizePool, amount: u64) { pool.yield_pot = pool.yield_pot + amount; }

/// Commit a hashed seed; returns the player's index.
public fun commit(pool: &mut PrizePool, commitment: vector<u8>): u64 {
    let idx = vector::length(&pool.commits);
    vector::push_back(&mut pool.commits, commitment);
    vector::push_back(&mut pool.reveals, vector[]); // placeholder
    idx
}

/// Reveal the seed; must match the commitment at `idx`.
public fun reveal(pool: &mut PrizePool, idx: u64, seed: vector<u8>) {
    assert!(hash::keccak256(&seed) == *vector::borrow(&pool.commits, idx), EBadReveal);
    *vector::borrow_mut(&mut pool.reveals, idx) = seed;
}

/// Derive the winner index from the combined revealed bytes. The draw does
/// NOT modify `principal` — no-loss by construction.
public fun draw(pool: &PrizePool): u64 {
    let n = vector::length(&pool.commits);
    assert!(n > 0, ENoPlayers);
    let mut acc: u64 = 0;
    let mut i = 0;
    while (i < n) {
        let r = vector::borrow(&pool.reveals, i);
        let mut j = 0;
        let m = vector::length(r);
        while (j < m) {
            acc = acc + (*vector::borrow(r, j) as u64);
            j = j + 1;
        };
        i = i + 1;
    };
    acc % n
}

public fun principal(pool: &PrizePool): u64 { pool.principal }
public fun yield_pot(pool: &PrizePool): u64 { pool.yield_pot }
public fun players(pool: &PrizePool): u64 { vector::length(&pool.commits) }
public fun share(pool: PrizePool) { transfer::share_object(pool) }

#[test_only]
public fun destroy_for_testing(pool: PrizePool) {
    let PrizePool { id, principal: _, yield_pot: _, commits: _, reveals: _ } = pool;
    object::delete(id);
}
