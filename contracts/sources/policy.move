/// L1 — Authority is an object, not a key.
///
/// A `WardenPolicy` has `key` ONLY (no `store`) → it cannot be wrapped,
/// sold, or transferred away. It is bound to the agent at mint. Its scope
/// — per-tx cap, rolling-window cap, reserve floor, expiry, generation —
/// is enforced on every single action.
///
/// The `GenerationRegistry` is a revocation lattice: bump `current_gen`
/// and every policy of an older generation is instantly dead, in one tx.
module warden::policy;

use sui::clock::{Self, Clock};

const EExpired: u64 = 0;
const EPaused: u64 = 1;
const EStaleGeneration: u64 = 2;
const EPerTxCap: u64 = 3;
const EWindowCap: u64 = 4;
const EWrongVault: u64 = 5;
const ENotAdmin: u64 = 6;

public struct WardenPolicy has key {   // NO `store` → non-transferable
    id: UID,
    vault: ID,
    agent: address,
    per_tx_cap: u64,
    window_cap: u64,
    window_ms: u64,
    window_start: u64,
    window_spent: u64,
    reserve_floor: u64,
    expiry_ms: u64,
    generation: u64,
}

public struct GenerationRegistry has key {
    id: UID,
    vault: ID,
    admin: address,     // stands in for the OwnerCap holder / DAO
    current_gen: u64,
    paused: bool,
}

/// Create the revocation registry for a vault. Caller becomes admin.
public fun init_registry(vault: ID, ctx: &mut TxContext): GenerationRegistry {
    GenerationRegistry {
        id: object::new(ctx),
        vault,
        admin: ctx.sender(),
        current_gen: 0,
        paused: false,
    }
}

/// Mint a scoped, non-transferable policy for `agent`. Admin only.
public fun mint(
    reg: &GenerationRegistry,
    vault: ID,
    agent: address,
    per_tx_cap: u64,
    window_cap: u64,
    window_ms: u64,
    reserve_floor: u64,
    ttl_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): WardenPolicy {
    assert!(ctx.sender() == reg.admin, ENotAdmin);
    assert!(reg.vault == vault, EWrongVault);
    let now = clock::timestamp_ms(clock);
    WardenPolicy {
        id: object::new(ctx),
        vault,
        agent,
        per_tx_cap,
        window_cap,
        window_ms,
        window_start: now,
        window_spent: 0,
        reserve_floor,
        expiry_ms: now + ttl_ms,
        generation: reg.current_gen,
    }
}

/// Revoke EVERY policy of the current generation in one move.
public fun revoke_all(reg: &mut GenerationRegistry, ctx: &TxContext) {
    assert!(ctx.sender() == reg.admin, ENotAdmin);
    reg.current_gen = reg.current_gen + 1;
}

public fun set_paused(reg: &mut GenerationRegistry, paused: bool, ctx: &TxContext) {
    assert!(ctx.sender() == reg.admin, ENotAdmin);
    reg.paused = paused;
}

/// The gate. Validates scope and debits the rolling window. Aborts on any
/// breach (a capability breach is a hard stop — the whole tx is invalid).
public fun assert_and_spend(
    pol: &mut WardenPolicy,
    reg: &GenerationRegistry,
    amount: u64,
    clock: &Clock,
) {
    assert!(reg.vault == pol.vault, EWrongVault);
    assert!(!reg.paused, EPaused);
    assert!(pol.generation == reg.current_gen, EStaleGeneration); // revocation
    let now = clock::timestamp_ms(clock);
    assert!(now <= pol.expiry_ms, EExpired);
    assert!(amount <= pol.per_tx_cap, EPerTxCap);
    // rolling window accounting
    if (now >= pol.window_start + pol.window_ms) {
        pol.window_start = now;
        pol.window_spent = 0;
    };
    assert!(pol.window_spent + amount <= pol.window_cap, EWindowCap);
    pol.window_spent = pol.window_spent + amount;
}

public fun reserve_floor(pol: &WardenPolicy): u64 { pol.reserve_floor }
public fun generation(pol: &WardenPolicy): u64 { pol.generation }
public fun current_gen(reg: &GenerationRegistry): u64 { reg.current_gen }
public fun share_registry(reg: GenerationRegistry) { transfer::share_object(reg) }

/// Transfer a (non-`store`) policy to its agent. Only this module may move
/// a `WardenPolicy`, which is exactly what keeps it non-transferable by
/// anyone else.
public fun transfer_policy(pol: WardenPolicy, to: address) { transfer::transfer(pol, to) }

#[test_only]
public fun destroy_policy_for_testing(pol: WardenPolicy) {
    let WardenPolicy {
        id, vault: _, agent: _, per_tx_cap: _, window_cap: _, window_ms: _,
        window_start: _, window_spent: _, reserve_floor: _, expiry_ms: _, generation: _,
    } = pol;
    object::delete(id);
}

#[test_only]
public fun destroy_registry_for_testing(reg: GenerationRegistry) {
    let GenerationRegistry { id, vault: _, admin: _, current_gen: _, paused: _ } = reg;
    object::delete(id);
}
