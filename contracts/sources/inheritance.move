/// L6 — Dead-man-switch inheritance.
///
/// A heartbeat keeps an asset the owner's. The owner `ping`s to stay alive;
/// after a dormancy period with no ping, a named beneficiary may `claim`
/// ownership. The asset stays productive during life — this only governs who
/// controls it. (In production the claim is gated by a Seal `seal_approve`
/// against the on-chain `Clock`; here the Clock check stands in for it.)
module warden::inheritance;

use sui::clock::{Self, Clock};

const ENotOwner: u64 = 0;
const ETooEarly: u64 = 1;

public struct Switch has key, store {
    id: UID,
    owner: address,
    beneficiary: address,
    last_ping_ms: u64,
    dormancy_ms: u64,
}

public struct Inherited has copy, drop { switch: ID, from: address, to: address }

public fun new(beneficiary: address, dormancy_ms: u64, clock: &Clock, ctx: &mut TxContext): Switch {
    Switch {
        id: object::new(ctx),
        owner: ctx.sender(),
        beneficiary,
        last_ping_ms: clock::timestamp_ms(clock),
        dormancy_ms,
    }
}

/// Owner proves liveness; resets the dormancy clock.
public fun ping(s: &mut Switch, clock: &Clock, ctx: &TxContext) {
    assert!(ctx.sender() == s.owner, ENotOwner);
    s.last_ping_ms = clock::timestamp_ms(clock);
}

public fun can_claim(s: &Switch, now_ms: u64): bool {
    now_ms >= s.last_ping_ms + s.dormancy_ms
}

/// After dormancy, the beneficiary inherits control. Resets the switch so
/// the new owner can in turn name a successor.
public fun claim(s: &mut Switch, clock: &Clock): address {
    let now = clock::timestamp_ms(clock);
    assert!(can_claim(s, now), ETooEarly);
    let from = s.owner;
    s.owner = s.beneficiary;
    s.last_ping_ms = now;
    sui::event::emit(Inherited { switch: object::id(s), from, to: s.owner });
    s.owner
}

public fun owner(s: &Switch): address { s.owner }
public fun beneficiary(s: &Switch): address { s.beneficiary }

#[test_only]
public fun destroy_for_testing(s: Switch) {
    let Switch { id, owner: _, beneficiary: _, last_ping_ms: _, dormancy_ms: _ } = s;
    object::delete(id);
}
