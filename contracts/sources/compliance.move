/// L5 — Compliance (closed-loop KYC).
///
/// A regulated tranche can only move between KYC-verified holders, enforced
/// at the protocol level: `gated_transfer` aborts if the recipient is not in
/// the registry. An `AuditorCap` grants read/audit standing without any spend
/// rights. Admin manages the verified set; the admin can never move funds.
module warden::compliance;

use sui::vec_set::{Self, VecSet};
use sui::coin::{Self, Coin};

const ENotVerified: u64 = 0;
const ENotAdmin: u64 = 1;

public struct KycRegistry has key {
    id: UID,
    admin: address,
    verified: VecSet<address>,
}

/// Read/audit standing — no ability to move value.
public struct AuditorCap has key, store {
    id: UID,
    registry: ID,
}

public fun init_registry(ctx: &mut TxContext): KycRegistry {
    KycRegistry { id: object::new(ctx), admin: ctx.sender(), verified: vec_set::empty() }
}

public fun set_verified(reg: &mut KycRegistry, who: address, ok: bool, ctx: &TxContext) {
    assert!(ctx.sender() == reg.admin, ENotAdmin);
    let present = vec_set::contains(&reg.verified, &who);
    if (ok && !present) { vec_set::insert(&mut reg.verified, who); }
    else if (!ok && present) { vec_set::remove(&mut reg.verified, &who); };
}

public fun is_verified(reg: &KycRegistry, who: address): bool {
    vec_set::contains(&reg.verified, &who)
}

public fun assert_can_receive(reg: &KycRegistry, who: address) {
    assert!(vec_set::contains(&reg.verified, &who), ENotVerified);
}

/// Protocol-gated transfer: regulated value only moves to verified holders.
public fun gated_transfer<T>(reg: &KycRegistry, c: Coin<T>, to: address) {
    assert_can_receive(reg, to);
    transfer::public_transfer(c, to);
}

public fun issue_auditor(reg: &KycRegistry, to: address, ctx: &mut TxContext) {
    assert!(ctx.sender() == reg.admin, ENotAdmin);
    transfer::public_transfer(AuditorCap { id: object::new(ctx), registry: object::id(reg) }, to);
}

public fun share_registry(reg: KycRegistry) { transfer::share_object(reg) }

#[test_only]
public fun destroy_for_testing(reg: KycRegistry) {
    let KycRegistry { id, admin: _, verified: _ } = reg;
    object::delete(id);
}

#[test_only]
public fun burn_coin_for_testing<T>(c: Coin<T>) { coin::burn_for_testing(c); }
