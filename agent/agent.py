#!/usr/bin/env python3
"""
WARDEN — the autonomous AI trading agent.

This is the "agent" half of the agentic fund: a Claude-powered loop that reads
the on-chain market feed, reasons about whether and how to trade within the
vault's policy bounds, and submits an `agent_trade` proposal to the chain.

The crucial point: the agent only *proposes*. Whatever it decides, the on-chain
Guardian re-derives risk from the same feed and freezes the vault if the agent's
claim diverges from the chain's own computation. So even a hallucinating,
mis-calibrated, or adversarial agent cannot move the fund out of bounds — the
chain is the backstop. This script is the thing the trust-minimization layer is
built to contain.

Usage:
    export ANTHROPIC_API_KEY=...            # never hardcode the key
    python agent/agent.py --config warden.config.json            # dry-run
    python agent/agent.py --config warden.config.json --submit   # send the tx

`warden.config.json` holds the package id + the shared/owned object ids printed
by `scripts/demo.sh` (open_vault) — see warden.config.example.json.

Requires: pip install anthropic ; the `sui` CLI on PATH (only for --submit).
"""
import argparse, hashlib, json, os, struct, subprocess, sys, urllib.request

RPC = "https://fullnode.testnet.sui.io:443"


def rpc(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(RPC, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)["result"]


def read_object_fields(object_id):
    res = rpc("sui_getObject", [object_id, {"showContent": True}])
    return res["data"]["content"]["fields"]


def get_market(feed_id):
    f = read_object_fields(feed_id)
    return int(f["price_e6"]), int(f["depth"])


def get_vault(vault_id):
    f = read_object_fields(vault_id)
    return {"idle": int(f["idle"]), "deployed": int(f["deployed"]), "frozen": bool(f["frozen"])}


def trade_digest(amount, direction, claimed_risk_bps, exposure_after):
    """Bind the digest the critic signs to the actual trade contents, instead of
    random bytes — so the signature commits to (amount, direction, risk,
    exposure). (On-chain re-derivation of this digest is a roadmap item; today
    the chain checks digest consistency, not that it binds the fields.)"""
    body = struct.pack("<QBQQ", amount, direction, claimed_risk_bps, exposure_after)
    return "0x" + hashlib.sha3_256(body).hexdigest()


# ---- the AI decision ----

SYSTEM = """You are WARDEN, an autonomous trading agent managing a non-custodial vault on Sui.
You may only PROPOSE a trade; an on-chain Guardian independently re-derives risk from the
same market feed and will FREEZE the vault if your claimed risk diverges from its own.
So: be honest about risk, and stay within policy. Your job is to allocate prudently.

Direction: 0 = reduce/keep risk (de-risking, allowed even in stress); 1 = increase exposure.
Risk rule of thumb the chain uses: thin order-book depth + large exposure => high risk (bps).
If the book is thin or the vault is stressed, propose a small, de-risking trade (direction 0)."""


def decide(market_price_e6, depth, vault, per_tx_cap, reserve_floor):
    import anthropic
    from pydantic import BaseModel, Field

    class TradeIntent(BaseModel):
        amount: int = Field(description="notional to deploy this trade, in MIST; must be <= per_tx_cap")
        direction: int = Field(description="0 = reduce/keep risk, 1 = increase exposure")
        claimed_risk_bps: int = Field(description="your honest estimate of resulting risk in basis points (0-10000)")
        confidence: int = Field(description="0-100")
        rationale: str = Field(description="one or two sentences explaining the decision")

    client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from the environment
    user = (
        f"Market feed: price_e6={market_price_e6}, order-book depth={depth}.\n"
        f"Vault: idle={vault['idle']} MIST, deployed={vault['deployed']} MIST, frozen={vault['frozen']}.\n"
        f"Policy: per_tx_cap={per_tx_cap} MIST, reserve_floor={reserve_floor} MIST.\n\n"
        f"Propose one trade within policy. Keep amount <= per_tx_cap and leave the reserve intact."
    )
    resp = client.messages.parse(
        model="claude-opus-4-8",
        max_tokens=2000,
        system=SYSTEM,
        messages=[{"role": "user", "content": user}],
        output_format=TradeIntent,
    )
    return resp.parsed_output


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True, help="warden.config.json with package + object ids")
    ap.add_argument("--submit", action="store_true", help="actually send the agent_trade tx via sui CLI")
    args = ap.parse_args()

    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("Set ANTHROPIC_API_KEY in your environment (never hardcode it).")

    cfg = json.load(open(args.config))
    try:
        price, depth = get_market(cfg["feed"])
        vault = get_vault(cfg["vault"])
    except Exception as e:
        sys.exit(f"[error] could not read on-chain state via RPC: {e}")
    per_tx_cap = int(cfg.get("per_tx_cap", 50_000_000))
    reserve_floor = int(cfg.get("reserve_floor", 20_000_000))

    print(f"[market] price_e6={price} depth={depth}")
    print(f"[vault ] idle={vault['idle']} deployed={vault['deployed']} frozen={vault['frozen']}")
    print("[agent ] asking Claude (claude-opus-4-8) to decide...")

    try:
        intent = decide(price, depth, vault, per_tx_cap, reserve_floor)
    except Exception as e:
        sys.exit(f"[error] agent decision failed (LLM call or schema validation): {e}")
    amount = min(int(intent.amount), per_tx_cap)
    print(f"[agent ] proposal: amount={amount} direction={intent.direction} "
          f"claimed_risk_bps={intent.claimed_risk_bps} confidence={intent.confidence}")
    print(f"[agent ] rationale: {intent.rationale}")

    # bind the digest the critic signs to the trade contents (not random bytes)
    exposure_after = vault["deployed"] + amount
    digest = trade_digest(amount, int(intent.direction), int(intent.claimed_risk_bps), exposure_after)
    call = [
        "sui", "client", "call", "--package", cfg["package"], "--module", "app",
        "--function", "agent_trade", "--args",
        cfg["vault"], cfg["policy"], cfg["gen_registry"], cfg["critic_registry"],
        cfg["critic_cap"], cfg["ledger"], cfg["feed"],
        str(amount), str(int(intent.direction)), str(int(intent.claimed_risk_bps)),
        digest, "0x" + "7761726c7573",  # walrus_blob placeholder
        "0x" + "746565",                # tee_attestation placeholder
        "0x6", "--gas-budget", "60000000",
    ]

    if args.submit:
        print("[chain ] submitting agent_trade; the Guardian will vet it on-chain...")
        out = subprocess.run(call + ["--json"], capture_output=True, text=True)
        if out.returncode != 0:
            sys.exit("sui call failed:\n" + out.stderr[-800:])
        d = json.loads(out.stdout)
        events = [e["type"].split("::")[-1] for e in d.get("events", [])]
        print(f"[chain ] tx {d['digest']} events={events}")
        if "VaultFrozen" in events:
            print("[chain ] ❄  the chain caught a divergence and FROZE the vault — agent contained.")
        else:
            print("[chain ] ✅ trade accepted within the leash.")
    else:
        print("[dry-run] would run:\n  " + " ".join(call))
        print("[dry-run] re-run with --submit to send it (the chain will vet it).")


if __name__ == "__main__":
    main()
