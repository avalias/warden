/**
 * WARDEN keeper — DeepBook v3 → OracleFeed.
 *
 * Reads REAL market state from a live DeepBook v3 pool on Sui testnet (mid-price
 * + level-2 order-book depth, via the official SDK's read-only devInspect calls)
 * and posts it into WARDEN's on-chain `OracleFeed` — the feed the Guardian
 * re-derives risk from and the agent cannot forge.
 *
 *   npm install
 *   npm run read     # dry-run: print the live numbers + the exact CLI call
 *   npm run post     # also post: runs `sui client call app::feed_update`
 *                    #   (must be signed by the feed's keeper address)
 *
 * The script itself holds no keys. Posting shells out to the local `sui` CLI
 * (override the binary with SUI_BIN), so the transaction is signed by YOUR
 * configured keypair — which must be the feed's `feeder`.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { SuiJsonRpcClient, getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc';
import { DeepBookClient } from '@mysten/deepbook-v3';

const here = dirname(fileURLToPath(import.meta.url));
const POST = process.argv.includes('--post');
const SUI_BIN = process.env.SUI_BIN ?? 'sui';

// pools to try, most likely to be alive on testnet first
const POOL_KEYS = ['SUI_DBUSDC', 'DEEP_SUI', 'DEEP_DBUSDC', 'DBWETH_DBUSDC'];

function loadConfig(): { package: string; feed: string } {
  for (const name of ['../../warden.config.json', '../../warden.config.example.json']) {
    try {
      const raw = JSON.parse(readFileSync(resolve(here, name), 'utf8'));
      if (typeof raw.feed === 'string' && /^0x[0-9a-fA-F]{64}$/.test(raw.feed)) {
        return { package: raw.package, feed: raw.feed };
      }
    } catch { /* next */ }
  }
  throw new Error('no usable warden.config.json found');
}

async function main() {
  const cfg = loadConfig();
  const sui = new SuiJsonRpcClient({ url: getJsonRpcFullnodeUrl('testnet'), network: 'testnet' });
  const db = new DeepBookClient({ client: sui as never, network: 'testnet', address: '0x0' });

  // 1. find a live pool (mid-price needs both a bid and an ask)
  let poolKey = '';
  let mid = 0;
  for (const k of POOL_KEYS) {
    try {
      const m = await db.midPrice(k);
      if (Number.isFinite(m) && m > 0) { poolKey = k; mid = m; break; }
      console.error(`· ${k}: no crossable book (mid=${m})`);
    } catch (e: any) {
      console.error(`· ${k}: ${String(e?.message ?? e).slice(0, 90)}`);
    }
  }
  if (!poolKey) throw new Error('no live DeepBook v3 pool found on testnet right now');

  // 2. level-2 depth around the mid: sum base quantities on both sides
  const l2 = await db.getLevel2TicksFromMid(poolKey, 10);
  const sum = (a: number[]) => a.reduce((s, x) => s + x, 0);
  const baseQty = sum(l2.bid_quantities ?? []) + sum(l2.ask_quantities ?? []);

  // 3. scale into the feed's integer units:
  //    price_e6 = mid * 1e6 (the same convention the demo used: 1.0 -> 1_000_000)
  //    depth    = total top-10-tick base quantity in atomic units (9 dp)
  const price_e6 = Math.max(1, Math.round(mid * 1e6));
  const depth = Math.max(1, Math.round(baseQty * 1e9));

  const provenance = {
    source: 'DeepBook v3 (Sui testnet)',
    pool: poolKey,
    mid_price: mid,
    bids_top10_base: sum(l2.bid_quantities ?? []),
    asks_top10_base: sum(l2.ask_quantities ?? []),
    posted: { price_e6, depth },
    read_at: new Date().toISOString(),
  };
  console.log(JSON.stringify(provenance, null, 2));

  const argv = [
    'client', 'call',
    '--package', cfg.package, '--module', 'app', '--function', 'feed_update',
    '--args', cfg.feed, String(price_e6), String(depth), '0x6',
    '--gas-budget', '60000000', '--json',
  ];
  console.log(`\nfeed_update call:\n  ${SUI_BIN} ${argv.join(' ')}`);

  if (!POST) { console.log('\n(dry-run — add --post to send it as the feed keeper)'); return; }

  // 4. post it, signed by the local CLI keypair (must be the feed's feeder)
  const r = spawnSync(SUI_BIN, argv, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`sui client call failed:\n${r.stderr || r.stdout}`);
  const out = JSON.parse(r.stdout);
  const status = out?.effects?.status?.status;
  console.log(`\nposted: ${status}  tx ${out.digest}`);
  console.log(`  https://suiscan.xyz/testnet/tx/${out.digest}`);
  if (status !== 'success') throw new Error('tx landed but did not succeed');
}

main().catch((e) => { console.error('FAILED:', e?.message ?? e); process.exit(1); });
