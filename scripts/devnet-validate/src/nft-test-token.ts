// nft-test-token — a second fungible-v2 token on the local devnet so the nft site can price sales in
// something other than KDA (founder 2026-10-12: "we want to integrate all tokens"). The catalog's
// token-fungible template, renamed `<ns>.test-token`, governed by the same throwaway key the
// nft-site-devnet deployer keeps; 1,000,000 TEST minted to sender00, from which the site's devnet
// panel hands out test amounts. Idempotent per chain.
//   DEVNET_HOST=http://localhost:8095 NFT_NS=user NFT_CHAINS=0,1 npm run nft-test-token
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ChainId } from '@kadena/client';
import { send, localCall, SENDER00, DEVNET_HOST, NETWORK_ID, saveResults, type Keypair } from './lib.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..', '..');
const KEYS_FILE = join(HERE, '..', 'results', 'nft-site-devnet-keys.json');
const NS = process.env.NFT_NS ?? 'user';
const CHAINS = (process.env.NFT_CHAINS ?? '0,1').split(',').map((c) => c.trim()) as ChainId[];
const MODULE = 'test-token';
const GOV_KS = `${NS}.nft-test-token-gov`;
const SUPPLY = 1_000_000;

async function main() {
  if (!existsSync(KEYS_FILE)) throw new Error(`${KEYS_FILE} missing — run nft-site-devnet first`);
  const gov: Keypair = JSON.parse(readFileSync(KEYS_FILE, 'utf8')).gov;
  console.log(`nft-test-token — ${DEVNET_HOST} (${NETWORK_ID}), ${NS}.${MODULE} on chains ${CHAINS.join(',')}`);
  const template = readFileSync(join(ROOT, 'contracts', 'library', 'token-fungible', 'token.pact'), 'utf8');
  const code = `(namespace "${NS}")\n(define-keyset "${GOV_KS}" (read-keyset "g"))\n`
    + template.replace(/\(module token GOV/, `(module ${MODULE} GOV`).replace(/"token-gov"/g, `"${GOV_KS}"`)
    + `\n(create-table ${NS}.${MODULE}.token-table)`;
  const data = { g: { keys: [gov.publicKey], pred: 'keys-all' } };
  for (const chainId of CHAINS) {
    const exists = await localCall(`(describe-module "${NS}.${MODULE}")`, chainId).then(() => true).catch(() => false);
    if (exists) console.log(`  · ${NS}.${MODULE} present on chain ${chainId}`);
    else await send({ code, label: `ch${chainId}: deploy ${NS}.${MODULE} (+table)`, signers: [{ kp: SENDER00 }, { kp: gov }], data, chainId });
    const bal = await localCall(`(try 0.0 (${NS}.${MODULE}.get-balance "sender00"))`, chainId);
    if (Number(bal) >= SUPPLY) { console.log(`  · sender00 already holds ${bal} TEST on chain ${chainId}`); continue; }
    await send({
      code: `(${NS}.${MODULE}.mint "sender00" (read-keyset "s") ${SUPPLY}.0)`, label: `ch${chainId}: mint ${SUPPLY} TEST to sender00 (gov)`,
      signers: [{ kp: SENDER00 }, { kp: gov }], data: { s: { keys: [SENDER00.publicKey], pred: 'keys-all' } }, chainId,
    });
  }
  saveResults('nft-test-token', { module: `${NS}.${MODULE}`, chains: CHAINS, govKeyset: GOV_KS, supplyToSender00: SUPPLY });
}
main().catch((e) => { console.error(e); process.exit(1); });
