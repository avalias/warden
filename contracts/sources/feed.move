/// On-chain market data feed.
///
/// Price and order-book depth live in a SHARED object whose values are written
/// only by a designated `feeder` (in production, a keeper that pulls Pyth +
/// DeepBook each block). The agent cannot forge it — it can only *reference* it.
///
/// This is what makes the Guardian's re-derivation trustworthy: the chain reads
/// the market state the agent does **not** control, rather than numbers the
/// agent passed in. Without this, "the chain re-derives risk" only catches an
/// agent lying about its risk number while being honest about the market; with
/// it, the agent cannot supply fake market data at all.
module warden::feed;

use sui::clock::{Self, Clock};

const ENotFeeder: u64 = 0;
const EStale: u64 = 1;

public struct OracleFeed has key {
    id: UID,
    feeder: address,     // keeper authority (production: Pyth-pulling oracle)
    price_e6: u64,
    depth: u64,
    updated_ms: u64,
    max_age_ms: u64,     // reads older than this are rejected as stale
}

public struct Updated has copy, drop { feed: ID, price_e6: u64, depth: u64, ts_ms: u64 }

public fun new(feeder: address, max_age_ms: u64, clock: &Clock, ctx: &mut TxContext): OracleFeed {
    OracleFeed {
        id: object::new(ctx),
        feeder,
        price_e6: 0,
        depth: 0,
        updated_ms: clock::timestamp_ms(clock),
        max_age_ms,
    }
}

/// Only the feeder can write market data.
public fun update(feed: &mut OracleFeed, price_e6: u64, depth: u64, clock: &Clock, ctx: &TxContext) {
    assert!(ctx.sender() == feed.feeder, ENotFeeder);
    feed.price_e6 = price_e6;
    feed.depth = depth;
    feed.updated_ms = clock::timestamp_ms(clock);
    sui::event::emit(Updated { feed: object::id(feed), price_e6, depth, ts_ms: feed.updated_ms });
}

/// Read (price, depth) with a freshness check. This is the only way the
/// Guardian obtains market data — never from a caller argument.
public fun read(feed: &OracleFeed, clock: &Clock): (u64, u64) {
    assert!(clock::timestamp_ms(clock) <= feed.updated_ms + feed.max_age_ms, EStale);
    (feed.price_e6, feed.depth)
}

public fun price_e6(feed: &OracleFeed): u64 { feed.price_e6 }
public fun depth(feed: &OracleFeed): u64 { feed.depth }
public fun share(feed: OracleFeed) { transfer::share_object(feed) }

#[test_only]
public fun destroy_for_testing(feed: OracleFeed) {
    let OracleFeed { id, feeder: _, price_e6: _, depth: _, updated_ms: _, max_age_ms: _ } = feed;
    object::delete(id);
}
