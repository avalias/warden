/**
 * Ask the chain itself what the guardian would rule — for hypothetical trades,
 * with no keys, no gas, no state change (devInspect runs the pure re-derivation).
 * This is "the chain re-derives risk" made interactive: preview the leash.
 *
 *   cd sdk && npm install && npx tsx examples/simulate-guardian.ts
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { WardenClient, type WardenAddresses } from '../src/warden.ts';

const here = dirname(fileURLToPath(import.meta.url));
const FAULTS = ['none', 'diverged', 'ceiling', 'unsafe-direction'];

function loadAddresses(): WardenAddresses {
  for (const name of ['../../warden.config.json', '../../warden.config.example.json']) {
    try {
      const raw = JSON.parse(readFileSync(resolve(here, name), 'utf8'));
      if (typeof raw.vault === 'string' && raw.vault.startsWith('0x') && raw.vault.length > 10) {
        const { package: pkg, vault, policy, gen_registry, critic_registry, critic_cap, ledger, feed } = raw;
        return { package: pkg, vault, policy, gen_registry, critic_registry, critic_cap, ledger, feed };
      }
    } catch { /* next */ }
  }
  throw new Error('no usable warden.config.json found');
}

// (label, params, what we expect the chain to rule)
const SCENARIOS = [
  ['small honest trade — should pass',
    { claimedRiskBps: 10, direction: 1 as const, exposure: 1_000_000, priceE6: 1_000_000, depth: 1_000_000_000 }],
  ['agent LIES (claims 100bps on a maxed-out position)',
    { claimedRiskBps: 100, direction: 0 as const, exposure: 1_000_000, priceE6: 1_000_000, depth: 100_000 }],
  ['honest but over the 70% ceiling',
    { claimedRiskBps: 10_000, direction: 0 as const, exposure: 1_000_000, priceE6: 1_000_000, depth: 100_000 }],
  ['danger zone, agent wants to INCREASE risk',
    { claimedRiskBps: 5_000, direction: 1 as const, exposure: 50_000, priceE6: 1_000_000, depth: 100_000 }],
  ['same danger zone, but DE-RISKING — allowed',
    { claimedRiskBps: 5_000, direction: 0 as const, exposure: 50_000, priceE6: 1_000_000, depth: 100_000 }],
] as const;

async function main() {
  const addr = loadAddresses();
  const warden = new WardenClient(new SuiClient({ url: getFullnodeUrl('testnet') }), addr);
  console.log(`Guardian simulation @ ${addr.package}\n  (Sui testnet devInspect — read-only)\n`);

  for (const [label, p] of SCENARIOS) {
    const v = await warden.simulateGuardian(p);
    const verdict = v.ok ? 'APPROVE' : `FREEZE (${FAULTS[v.fault] ?? v.fault})`;
    console.log(`• ${label}`);
    console.log(`    claimed=${p.claimedRiskBps}bps dir=${p.direction === 0 ? 'reduce' : 'increase'}  ->  chain derives ${v.derived_bps}bps  =>  ${verdict}`);
  }

  console.log('\nOK — every verdict came from the chain itself (guardian::evaluate via devInspect).');
}

main().catch((e) => { console.error('FAILED:', e?.message ?? e); process.exit(1); });
