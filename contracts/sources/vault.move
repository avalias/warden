/// L0 — Non-custodial custody.
///
/// Funds live inside a user-owned `Vault`. The ONLY path that removes
/// capital is `owner_withdraw`, gated by the `OwnerCap`. The agent fleet
/// can steer capital (deploy notional into strategies) but can never
/// withdraw it. Freezing halts the agent — it NEVER blocks the owner.
module warden::vault;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;

const ENotOwner: u64 = 0;
const EFrozen: u64 = 1;
const EReserveBreached: u64 = 2;
const EInsufficient: u64 = 3;

public struct Vault<phantom T> has key {
    id: UID,
    owner: address,
    idle: Balance<T>,   // capital sitting in the vault
    deployed: u64,      // notional the agent has steered into strategies
    shares: u64,        // total depositor shares (1:1 in the MVP)
    frozen: bool,
}

/// The withdraw right. `store` so the owner can custody it; only its
/// holder can ever remove funds.
public struct OwnerCap has key, store {
    id: UID,
    vault: ID,
}

public struct Deposited has copy, drop { vault: ID, who: address, amount: u64 }
public struct Withdrawn has copy, drop { vault: ID, amount: u64 }
public struct VaultFrozen has copy, drop { vault: ID, reason: u8 }

/// Create a fresh vault and its owner capability.
public fun new<T>(ctx: &mut TxContext): (Vault<T>, OwnerCap) {
    let v = Vault<T> {
        id: object::new(ctx),
        owner: ctx.sender(),
        idle: balance::zero<T>(),
        deployed: 0,
        shares: 0,
        frozen: false,
    };
    let cap = OwnerCap { id: object::new(ctx), vault: object::id(&v) };
    (v, cap)
}

/// Anyone can deposit. Mints 1:1 shares in the MVP (PT/YT split is a
/// roadmap layer).
public fun deposit<T>(v: &mut Vault<T>, c: Coin<T>, ctx: &TxContext) {
    let amount = coin::value(&c);
    assert!(amount > 0, EInsufficient);
    balance::join(&mut v.idle, coin::into_balance(c));
    v.shares = v.shares + amount;
    event::emit(Deposited { vault: object::id(v), who: ctx.sender(), amount });
}

/// The non-custodial guarantee: ONLY the OwnerCap holder withdraws, and
/// it works even while the agent is frozen.
public fun owner_withdraw<T>(
    v: &mut Vault<T>, cap: &OwnerCap, amount: u64, ctx: &mut TxContext,
): Coin<T> {
    assert!(cap.vault == object::id(v), ENotOwner);
    assert!(balance::value(&v.idle) >= amount, EInsufficient);
    v.shares = if (v.shares > amount) { v.shares - amount } else { 0 };
    event::emit(Withdrawn { vault: object::id(v), amount });
    coin::from_balance(balance::split(&mut v.idle, amount), ctx)
}

/// Freeze the agent. Callable by the guardian path on a detected fault.
public fun freeze_vault<T>(v: &mut Vault<T>, reason: u8) {
    v.frozen = true;
    event::emit(VaultFrozen { vault: object::id(v), reason });
}

/// Only the owner can lift a freeze (stands in for DAO/owner governance).
public fun unfreeze<T>(v: &mut Vault<T>, cap: &OwnerCap) {
    assert!(cap.vault == object::id(v), ENotOwner);
    v.frozen = false;
}

public fun share<T>(v: Vault<T>) { transfer::share_object(v) }

// ---- agent-facing internal ops (package only) — never a withdraw ----

/// Steer notional into a strategy. Aborts if frozen or if the move would
/// break the reserve floor. Funds never leave the vault object.
public(package) fun deploy<T>(v: &mut Vault<T>, amount: u64, reserve_floor: u64) {
    assert!(!v.frozen, EFrozen);
    assert!(balance::value(&v.idle) >= amount + reserve_floor, EReserveBreached);
    v.deployed = v.deployed + amount;
}

public fun is_frozen<T>(v: &Vault<T>): bool { v.frozen }
public fun idle_value<T>(v: &Vault<T>): u64 { balance::value(&v.idle) }
public fun deployed<T>(v: &Vault<T>): u64 { v.deployed }
public fun shares<T>(v: &Vault<T>): u64 { v.shares }
public fun vault_id<T>(v: &Vault<T>): ID { object::id(v) }

#[test_only]
public fun destroy_for_testing<T>(v: Vault<T>) {
    let Vault { id, owner: _, idle, deployed: _, shares: _, frozen: _ } = v;
    balance::destroy_for_testing(idle);
    object::delete(id);
}

#[test_only]
public fun destroy_cap_for_testing(cap: OwnerCap) {
    let OwnerCap { id, vault: _ } = cap;
    object::delete(id);
}
