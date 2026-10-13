// nft-site-devnet — deploy the WHOLE nft framework (every policy, both auctions, the pack engine
// with the pinned drand verifier, and the reference arena game) on a local devnet so the local
// nft.smartpacts.io site can drive it. Idempotent: a module that already exists on a chain is
// skipped, so a rerun completes a partial deployment instead of burning names.
//
// Why a second deployer next to nft-framework.ts: that one is a CAMPAIGN (random personas, a
// fresh admin keyset per run, nothing kept), which is right for evidence and wrong for a site —
// the governance key of its deployment is gone, so no sale contract can be registered on it and
// no protocol fee set. This one KEEPS its keys (results/nft-site-devnet-keys.json — devnet
// throwaways, worthless by construction, never reuse them anywhere real) and writes the facts the
// site needs (namespace, chains, protocol payee) to results/nft-site-devnet.json.
//
//   DEVNET_HOST=http://localhost:8095 NFT_NS=user NFT_CHAINS=0,1 npm run nft-site-devnet
//
// The namespace defaults to `user` (devnets predefine `free` and `user`; `free.*` on the long-running
// devnet is taken by the campaign's one-shot deployment). The arena module references the framework
// as `nft.*`; that prefix is substituted textually to the chosen namespace at deploy time.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ChainId } from '@kadena/client';
import {
  send, localCall, persona, SENDER00, DEVNET_HOST, NETWORK_ID, saveResults, type Keypair,
} from './lib.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..', '..');
const NFT = join(ROOT, 'contracts', 'nft');
const RESULTS = join(HERE, '..', 'results');
const KEYS_FILE = join(RESULTS, 'nft-site-devnet-keys.json');

const NS = process.env.NFT_NS ?? 'user';
const CHAINS = (process.env.NFT_CHAINS ?? '0,1').split(',').map((c) => c.trim()) as ChainId[];
const ADMIN_KS = `${NS}.nft-site-admin`;
const ARENA_KS = `${NS}.nft-site-arena-admin`;
const PROTOCOL_BPS = 50;
const UPGRADE = (process.env.UPGRADE ?? '').split(',').map((x) => x.trim()).filter(Boolean);
const SWAP_FEE = 0.5;   // flat KDA per accepted swap — a devnet placeholder, the founder's figure at the ceremony

type Keys = { gov: Keypair; pco: Keypair };
function loadOrCreateKeys(): Keys {
  if (existsSync(KEYS_FILE)) {
    const k = JSON.parse(readFileSync(KEYS_FILE, 'utf8')) as Keys;
    console.log(`keys: reusing ${KEYS_FILE} (gov ${k.gov.publicKey.slice(0, 12)}…)`);
    return k;
  }
  const k: Keys = { gov: persona('gov'), pco: persona('pco') };
  mkdirSync(RESULTS, { recursive: true });
  writeFileSync(KEYS_FILE, JSON.stringify({ note: 'DEVNET THROWAWAY KEYS — guard nothing of value; never reuse', ...k }, null, 2));
  console.log(`keys: created ${KEYS_FILE}`);
  return k;
}

const src = (rel: string) => readFileSync(join(NFT, rel), 'utf8');
const ks = (kp: Keypair) => ({ keys: [kp.publicKey], pred: 'keys-all' });
const tables = (mod: string, names: string[]) => names.map((t) => `(create-table ${NS}.${mod}.${t})`).join('');

async function moduleExists(name: string, chainId: ChainId): Promise<boolean> {
  try { await localCall(`(describe-module "${NS}.${name}")`, chainId); return true; }
  catch { return false; }
}

type Mod = { name: string; file: string; tables?: string[]; transform?: (code: string) => string };
const MODULES: Mod[] = [
  { name: 'util', file: 'core/util.pact' },
  { name: 'venue-registry', file: 'core/venue-registry.pact', tables: ['venues'] },
  { name: 'policy-manager', file: 'core/policy-manager.pact', tables: ['ledgers', 'quotes', 'sale-contracts', 'params', 'creation-venues', 'quote-expiry'] },
  { name: 'ledger', file: 'core/ledger.pact', tables: ['ledger-table', 'tokens'] },
  { name: 'royalty-policy', file: 'policies/royalty-policy.pact', tables: ['royalties'] },
  { name: 'non-fungible-policy', file: 'policies/non-fungible-policy.pact', tables: ['minted-table'] },
  { name: 'guard-policy', file: 'policies/guard-policy.pact', tables: ['op-guards'] },
  { name: 'collection-policy', file: 'policies/collection-policy.pact', tables: ['collections', 'collection-tokens'] },
  { name: 'non-updatable-uri-policy', file: 'policies/non-updatable-uri-policy.pact' },
  { name: 'guarded-uri-policy', file: 'policies/guarded-uri-policy.pact', tables: ['uri-guards', 'uri-history'] },
  { name: 'issuance-policy', file: 'policies/issuance-policy.pact', tables: ['issuance'] },
  { name: 'transfer-mode-policy', file: 'policies/transfer-mode-policy.pact', tables: ['modes'] },
  { name: 'attributes-policy', file: 'policies/attributes-policy.pact', tables: ['specs', 'attributes', 'attr-history'] },
  { name: 'conventional-auction', file: 'sale/conventional-auction.pact', tables: ['auctions'] },
  { name: 'dutch-auction', file: 'sale/dutch-auction.pact', tables: ['auctions'] },
  { name: 'drand-verifier', file: 'core/drand-verifier.pact' },
  { name: 'pack-engine', file: 'core/pack-engine.pact', tables: ['verifiers', 'series-table', 'pool', 'requests', 'queues'] },
  { name: 'swap', file: 'core/swap.pact', tables: ['offers', 'params'] },
  // the reference game: its framework references are written as nft.*; the deployment substitutes
  { name: 'arena', file: 'examples/arena/arena.pact', tables: ['matches'], transform: (c) => c.replace(/\bnft\./g, `${NS}.`) },
];
const INTERFACES = [
  'interfaces/account-protocols.pact', 'interfaces/token-policy.pact', 'interfaces/poly-fungible.pact',
  'interfaces/ledger-iface.pact', 'interfaces/sale.pact', 'interfaces/beacon-verifier.pact',
];

async function deployChain(chainId: ChainId, keys: Keys): Promise<void> {
  console.log(`\n== chain ${chainId}: ${NS}.* ==`);
  const data = {
    ns: NS, 'admin-ks': ADMIN_KS, g: ks(keys.gov),
    'arena-ns': NS, 'arena-admin-ks': ARENA_KS, 'arena-admin': ks(keys.gov),
  };
  const gov = [{ kp: SENDER00 }, { kp: keys.gov }];
  const plain = [{ kp: SENDER00 }];

  if (!(await moduleExists('util', chainId))) {
    await send({ code: `(namespace "${NS}")(define-keyset "${ADMIN_KS}" (read-keyset "g"))(define-keyset "${ARENA_KS}" (read-keyset "arena-admin"))`,
      label: `ch${chainId}: define ${ADMIN_KS} + ${ARENA_KS}`, signers: gov, data, chainId });
    await send({ code: INTERFACES.map(src).join('\n'), label: `ch${chainId}: deploy the interfaces`, signers: plain, data, chainId });
  } else console.log(`  · keysets + interfaces present (util exists)`);

  for (const m of MODULES) {
    const present = await moduleExists(m.name, chainId);
    if (present && !UPGRADE.includes(m.name)) { console.log(`  · ${NS}.${m.name} present, skipped`); continue; }
    const body = (m.transform ?? ((c: string) => c))(src(m.file));
    if (!present) {
      await send({ code: body + '\n' + tables(m.name, m.tables ?? []), label: `ch${chainId}: deploy ${m.name}${m.tables?.length ? ` (+${m.tables.length} tables)` : ''}`, signers: plain, data, chainId });
      continue;
    }
    // UPGRADE (UPGRADE=name,name): the module's governance keyset signs; an upgrade creates no table
    // (memory: pact_upgrade_does_not_create_tables), so every table the new code names is probed and
    // created when missing — the one-shot a schema change otherwise forgets
    await send({ code: body, label: `ch${chainId}: UPGRADE ${m.name} (gov)`, signers: gov, data, chainId });
    for (const t of m.tables ?? []) {
      // 🔴 `describe-table` answers from the module's DECLARATION and resolves for a table that was never
      // created (devnet, 2026-10-13: it said quote-expiry was present while every read failed "Table …
      // not found"). Only a real read proves the table exists.
      const exists = await localCall(`(keys ${NS}.${m.name}.${t})`, chainId).then(() => true).catch(() => false);
      // Pact 5: top-level `create-table` needs the module's admin acquired explicitly (the gov keyset signs)
      if (!exists) await send({ code: `(acquire-module-admin ${NS}.${m.name}) (create-table ${NS}.${m.name}.${t})`, label: `ch${chainId}: create ${m.name}.${t}`, signers: gov, data, chainId });
      else console.log(`  · table ${m.name}.${t} present`);
    }
  }

  // governance wiring — each call is idempotent-guarded by a read, so a rerun does not fail
  const ledgerSet = await localCall(`(try false (let ((l:module{${NS}.ledger-iface} (${NS}.policy-manager.retrieve-ledger))) true))`, chainId).catch(() => false);
  if (!ledgerSet) {
    await send({ code: `(${NS}.policy-manager.init ${NS}.ledger)`, label: `ch${chainId}: manager init (gov)`, signers: gov, data, chainId });
  } else console.log('  · manager already initialised');
  for (const sc of ['conventional-auction', 'dutch-auction']) {
    const registered = await localCall(`(try false (at 'enabled (read ${NS}.policy-manager.sale-contracts "${NS}.${sc}")))`, chainId).catch(() => false);
    if (registered) { console.log(`  · ${sc} already registered`); continue; }
    await send({ code: `(${NS}.policy-manager.register-sale-contract ${NS}.${sc})`, label: `ch${chainId}: register ${sc} (gov)`, signers: gov, data, chainId });
  }
  const bps = await localCall(`(${NS}.policy-manager.protocol-bps)`, chainId).catch(() => 0);
  if (bps !== PROTOCOL_BPS) {
    await send({ code: `(${NS}.policy-manager.set-protocol-fee ${PROTOCOL_BPS} "${keys.pco.account}" (read-keyset "pco"))`,
      label: `ch${chainId}: protocol fee ${PROTOCOL_BPS} bps -> ${keys.pco.account.slice(0, 14)}… (gov)`,
      signers: gov, data: { ...data, pco: ks(keys.pco) }, chainId });
  } else console.log(`  · protocol fee already ${PROTOCOL_BPS} bps`);
  const swapFee = await localCall(`(at 'fee (${NS}.swap.get-swap-fee))`, chainId).catch(() => 0);
  if (Number(swapFee) !== SWAP_FEE) {
    await send({ code: `(${NS}.swap.set-swap-fee ${SWAP_FEE.toFixed(1)} "${keys.pco.account}" (read-keyset "pco"))`,
      label: `ch${chainId}: swap fee ${SWAP_FEE} KDA -> ${keys.pco.account.slice(0, 14)}… (gov)`,
      signers: gov, data: { ...data, pco: ks(keys.pco) }, chainId });
  } else console.log(`  · swap fee already ${SWAP_FEE}`);
  const verifier = await localCall(`(try false (let ((v (${NS}.pack-engine.verifier))) true))`, chainId).catch(() => false);
  if (!verifier) {
    await send({ code: `(${NS}.pack-engine.set-verifier ${NS}.drand-verifier)`, label: `ch${chainId}: pack-engine verifier (gov)`, signers: gov, data, chainId });
  } else console.log('  · pack-engine verifier already set');
}

async function main() {
  console.log(`nft-site-devnet — ${DEVNET_HOST} (${NETWORK_ID}), namespace ${NS}, chains ${CHAINS.join(',')}`);
  const keys = loadOrCreateKeys();
  for (const c of CHAINS) await deployChain(c, keys);
  const hashes: Record<string, string> = {};
  for (const m of MODULES) hashes[`${NS}.${m.name}`] = String((await localCall(`(at 'hash (describe-module "${NS}.${m.name}"))`, CHAINS[0])) ?? '');
  saveResults('nft-site-devnet', {
    ns: NS, chains: CHAINS, adminKeyset: ADMIN_KS, arenaKeyset: ARENA_KS,
    govPublicKey: keys.gov.publicKey, protocolBps: PROTOCOL_BPS, protocolAccount: keys.pco.account,
    moduleHashes: hashes,
  });
}

main().catch((e) => { console.error(e); process.exit(1); });
