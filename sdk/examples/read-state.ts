/**
 * Read-only smoke: pull WARDEN's live state straight from Sui testnet and print
 * it. No keys, no signing, no gas — just proof the readers work against the real,
 * immutable package.
 *
 *   cd sdk && npm install && npm run read-state
 *
 * Reads object ids from ../warden.config.json (or warden.config.example.json as a
 * fallback). Only on-chain ids are used — nothing else from the config is touched.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { WardenClient, type WardenAddresses } from '../src/warden.ts';

const here = dirname(fileURLToPath(import.meta.url));

function loadAddresses(): WardenAddresses {
  for (const name of ['../../warden.config.json', '../../warden.config.example.json']) {
    try {
      const raw = JSON.parse(readFileSync(resolve(here, name), 'utf8'));
      if (typeof raw.vault === 'string' && /^0x[0-9a-fA-F]{64}$/.test(raw.vault)) {
        const { package: pkg, vault, policy, gen_registry, critic_registry, critic_cap, ledger, feed } = raw;
        return { package: pkg, vault, policy, gen_registry, critic_registry, critic_cap, ledger, feed };
      }
    } catch { /* try next */ }
  }
  throw new Error('no usable warden.config.json found — copy warden.config.example.json and fill in your ids');
}

async function main() {
  const addr = loadAddresses();
  const client = new SuiClient({ url: getFullnodeUrl('testnet') });
  const warden = new WardenClient(client, addr);

  console.log(`WARDEN @ ${addr.package}\n  (Sui testnet, read-only)\n`);

  const vault = await warden.getVaultState();
  console.log('VAULT');
  console.log(`  owner     ${vault.owner}`);
  console.log(`  idle      ${vault.idle} MIST`);
  console.log(`  deployed  ${vault.deployed} MIST`);
  console.log(`  NAV       ${vault.nav} MIST   (idle + deployed, conserved by agent ops)`);
  console.log(`  frozen    ${vault.frozen}\n`);

  const feed = await warden.getFeedState();
  console.log('FEED');
  console.log(`  price_e6  ${feed.price_e6}`);
  console.log(`  depth     ${feed.depth}`);
  console.log(`  stale     ${feed.stale}   (max_age ${feed.max_age_ms} ms)\n`);

  const ledger = await warden.getLedgerState();
  console.log('LEDGER');
  console.log(`  seq        ${ledger.seq}`);
  console.log(`  count      ${ledger.count}`);
  console.log(`  chain_head ${ledger.chain_head}\n`);

  const history = await warden.getLedgerHistory(5);
  console.log(`LEDGER HISTORY (latest ${history.length})`);
  for (const e of history) {
    const verdict = e.accepted ? 'ACCEPTED' : `REJECTED(fault=${e.fault})`;
    console.log(`  #${e.seq}  ${verdict}  risk=${e.risk_bps}bps  entry=${e.entry_digest.slice(0, 18)}…`);
  }

  console.log('\nOK — live state read from the immutable package with zero trust in any server.');
}

main().catch((e) => { console.error('FAILED:', e?.message ?? e); process.exit(1); });
