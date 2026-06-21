/// L2 — The independent critic.
///
/// A SECOND agent, holding its OWN capability at a DIFFERENT address than
/// the trader, must approve a trade. The `CriticCap` is its on-chain
/// identity — the moral equivalent of signing with its own separate key.
/// No agent trusts another; the chain is the referee.
module warden::critic;

const ENotRegistered: u64 = 0;
const ERejected: u64 = 1;

/// Held by the critic agent. `key` only → bound to the critic.
public struct CriticCap has key {
    id: UID,
    critic: address,
}

/// The vault's record of which critic identity is sanctioned.
public struct CriticRegistry has key {
    id: UID,
    vault: ID,
    critic: address,
}

/// A signed verdict. No abilities → a hot potato: it must be consumed by
/// settlement, it cannot be stored or dropped on the floor.
public struct Verdict {
    critic: address,
    trade_digest: vector<u8>,
    approved: bool,
}

/// Mint a critic identity for whoever calls (the critic agent's address).
public fun new_cap(ctx: &mut TxContext): CriticCap {
    CriticCap { id: object::new(ctx), critic: ctx.sender() }
}

public fun init_registry(vault: ID, critic: address, ctx: &mut TxContext): CriticRegistry {
    CriticRegistry { id: object::new(ctx), vault, critic }
}

/// The critic judges a trade digest WITH ITS OWN cap (its own identity).
public fun judge(cap: &CriticCap, trade_digest: vector<u8>, approved: bool): Verdict {
    Verdict { critic: cap.critic, trade_digest, approved }
}

/// Settlement consumes the verdict: it must come from the sanctioned
/// critic and must be an approval. Returns the digest it bound to so the
/// caller can check it matches the trade actually being settled.
public fun consume(reg: &CriticRegistry, v: Verdict): vector<u8> {
    let Verdict { critic, trade_digest, approved } = v;
    assert!(critic == reg.critic, ENotRegistered);
    assert!(approved, ERejected);
    trade_digest
}

public fun critic_addr(reg: &CriticRegistry): address { reg.critic }
public fun share_registry(reg: CriticRegistry) { transfer::share_object(reg) }

/// Mint a critic identity bound to `to` and hand it over. Only this module
/// can move a (non-`store`) `CriticCap`.
public fun mint_cap_to(to: address, ctx: &mut TxContext) {
    transfer::transfer(CriticCap { id: object::new(ctx), critic: to }, to)
}

#[test_only]
public fun new_cap_for(critic: address, ctx: &mut TxContext): CriticCap {
    CriticCap { id: object::new(ctx), critic }
}

#[test_only]
public fun destroy_cap_for_testing(cap: CriticCap) {
    let CriticCap { id, critic: _ } = cap;
    object::delete(id);
}

#[test_only]
public fun destroy_registry_for_testing(reg: CriticRegistry) {
    let CriticRegistry { id, vault: _, critic: _ } = reg;
    object::delete(id);
}
