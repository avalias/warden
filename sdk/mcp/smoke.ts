/**
 * End-to-end smoke: spawn the warden MCP server, do a real MCP handshake over
 * stdio, list its tools, and call a few — proving the whole round-trip works
 * (read tools hit live testnet; build tools return a serialized unsigned tx).
 *
 *   cd sdk/mcp && npm install && npm run smoke
 */
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const here = dirname(fileURLToPath(import.meta.url));

async function main() {
  // launch the server as `node --import tsx server.ts` (cross-platform: no PATH/.cmd)
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ['--import', 'tsx', resolve(here, 'server.ts')],
    cwd: here,
  });
  const client = new Client({ name: 'warden-smoke', version: '0.1.0' }, { capabilities: {} });
  await client.connect(transport);

  const { tools } = await client.listTools();
  console.log('TOOLS:', tools.map((t) => t.name).join(', '), '\n');

  const text = (r: any) => String(r.content?.[0]?.text ?? '');

  console.log('warden_get_vault_state ->');
  console.log(text(await client.callTool({ name: 'warden_get_vault_state', arguments: {} })), '\n');

  console.log('warden_get_ledger_history(3) ->');
  console.log(text(await client.callTool({ name: 'warden_get_ledger_history', arguments: { limit: 3 } })), '\n');

  console.log('warden_build_feed_update -> serialized UNSIGNED tx (first 120 chars):');
  const tx = text(await client.callTool({ name: 'warden_build_feed_update', arguments: { priceE6: '1000000', depth: '1000' } }));
  console.log('  ' + tx.slice(0, 120) + '…\n');

  await client.close();
  console.log('OK — MCP round-trip works: tools listed + called, live state via testnet, unsigned tx built.');
}

main().catch((e) => { console.error('FAILED:', e?.message ?? e); process.exit(1); });
