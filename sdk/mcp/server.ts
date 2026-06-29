/**
 * warden MCP server — exposes the WARDEN custody package to any MCP-speaking
 * agent runtime (Cursor and other MCP clients) as tools. Built on @warden/sdk:
 *
 *   read tools  — live on-chain truth (vault NAV, ledger hash-chain head, the
 *                 unforgeable market feed, the accepted/rejected track record).
 *   build tools — assemble UNSIGNED transactions and hand them back serialized.
 *                 The server never holds keys or signs; the agent's wallet does.
 *
 * Speaks MCP over stdio. Wire it into a client's mcpServers config (see README).
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { WardenClient, type WardenAddresses } from '../src/warden.ts';

const here = dirname(fileURLToPath(import.meta.url));

function loadAddresses(): WardenAddresses {
  for (const name of ['../../warden.config.json', '../../warden.config.example.json']) {
    try {
      const raw = JSON.parse(readFileSync(resolve(here, name), 'utf8'));
      if (typeof raw.vault === 'string' && raw.vault.startsWith('0x') && raw.vault.length > 10) {
        const { package: pkg, vault, policy, gen_registry, critic_registry, critic_cap, ledger, feed } = raw;
        return { package: pkg, vault, policy, gen_registry, critic_registry, critic_cap, ledger, feed };
      }
    } catch { /* try next */ }
  }
  throw new Error('no usable warden.config.json (copy warden.config.example.json and fill in your ids)');
}

const network = (process.env.WARDEN_NETWORK ?? 'testnet') as 'testnet' | 'mainnet' | 'devnet' | 'localnet';
const sui = new SuiClient({ url: getFullnodeUrl(network) });
const warden = new WardenClient(sui, loadAddresses());

const J = (v: unknown) => JSON.stringify(v, (_k, x) => (typeof x === 'bigint' ? x.toString() : x), 2);
function hexToBytes(h?: string): number[] {
  if (!h) return [];
  const s = h.startsWith('0x') ? h.slice(2) : h;
  const out: number[] = [];
  for (let i = 0; i + 1 < s.length; i += 2) out.push(parseInt(s.slice(i, i + 2), 16));
  return out;
}

const TOOLS = [
  { name: 'warden_get_vault_state', description: 'Live custody state: owner, idle, deployed, NAV (idle+deployed — conserved by every agent op), shares, frozen.', inputSchema: { type: 'object', properties: {} } },
  { name: 'warden_get_ledger_state', description: 'Append-only ledger head: monotonic seq, count, and the keccak hash-chain head (tamper-evidence).', inputSchema: { type: 'object', properties: {} } },
  { name: 'warden_get_feed_state', description: 'The market feed the agent cannot forge: price_e6, depth, and whether a read would be rejected as stale right now.', inputSchema: { type: 'object', properties: {} } },
  { name: 'warden_get_ledger_history', description: 'Recent trade records — accepted AND rejected — newest first. The chain records what the agent was NOT allowed to do.', inputSchema: { type: 'object', properties: { limit: { type: 'number', description: 'how many entries (default 10)' } } } },
  { name: 'warden_build_feed_update', description: 'Build an UNSIGNED feed_update transaction (the keeper posts market data). Returns the serialized tx for your wallet to sign.', inputSchema: { type: 'object', properties: { priceE6: { type: 'string', description: 'price * 1e6' }, depth: { type: 'string', description: 'order-book depth' } }, required: ['priceE6', 'depth'] } },
  { name: 'warden_build_agent_trade', description: 'Build an UNSIGNED agent_trade transaction. On submit it flows through all five gates atomically; a guardian fault freezes the vault and records the rejection. Returns the serialized tx to sign.', inputSchema: { type: 'object', properties: { amount: { type: 'string' }, direction: { type: 'number', enum: [0, 1], description: '0 = reduce risk, 1 = increase' }, claimedRiskBps: { type: 'string', description: "the agent's claimed risk in bps (the chain re-derives the truth and checks it)" }, walrusBlobHex: { type: 'string' }, teeAttestationHex: { type: 'string' } }, required: ['amount', 'direction', 'claimedRiskBps'] } },
];

const server = new Server({ name: 'warden', version: '0.1.0' }, { capabilities: { tools: {} } });

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const name = req.params.name;
  const args = (req.params.arguments ?? {}) as Record<string, any>;
  const run = async (): Promise<string> => {
    switch (name) {
      case 'warden_get_vault_state': return J(await warden.getVaultState());
      case 'warden_get_ledger_state': return J(await warden.getLedgerState());
      case 'warden_get_feed_state': return J(await warden.getFeedState());
      case 'warden_get_ledger_history': return J(await warden.getLedgerHistory(Number(args.limit ?? 10)));
      case 'warden_build_feed_update':
        return warden.buildFeedUpdateTx({ priceE6: BigInt(args.priceE6), depth: BigInt(args.depth) }).serialize();
      case 'warden_build_agent_trade':
        return warden.buildAgentTradeTx({
          amount: BigInt(args.amount),
          direction: Number(args.direction) === 1 ? 1 : 0,
          claimedRiskBps: BigInt(args.claimedRiskBps),
          walrusBlob: hexToBytes(args.walrusBlobHex),
          teeAttestation: hexToBytes(args.teeAttestationHex),
        }).serialize();
      default: throw new Error(`unknown tool: ${name}`);
    }
  };
  try {
    return { content: [{ type: 'text', text: await run() }] };
  } catch (e: any) {
    return { content: [{ type: 'text', text: `error: ${e?.message ?? e}` }], isError: true };
  }
});

await server.connect(new StdioServerTransport());
console.error(`warden MCP server ready (stdio, ${network})`); // stderr — stdout is the MCP channel
