// Shared plumbing for the PCO library devnet validation campaign.
//
// Targets a local KDA-CE devnet (default :8090, network `recap-development`).
// sender00 is the devnet genesis faucet (well-known devnet-only key). Every
// run deploys the template under the `free` namespace with its governance
// keyset patched to a namespaced one - exactly the adaptation each template's
// README prescribes for real deployments.
import {
  Pact,
  createClient,
  createSignWithKeypair,
  type ChainId,
  type ICommandResult,
  type IUnsignedCommand,
} from '@kadena/client';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const DEVNET_HOST = process.env.DEVNET_HOST ?? 'http://localhost:8090';
export const NETWORK_ID = process.env.DEVNET_NETWORK_ID ?? 'recap-development';
export const GAS_PRICE = 0.00000001;
export const GAS_LIMIT = 150000; // KDA-CE ceiling
export const CHAIN = (process.env.DEVNET_CHAIN ?? '0') as ChainId;

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

export const client = createClient(
  ({ chainId, networkId }) =>
    `${DEVNET_HOST}/chainweb/0.0/${networkId}/chain/${chainId}/pact`,
);

export type Keypair = { account: string; publicKey: string; secretKey: string };

// Devnet genesis faucet (public devnet key from chainweb-node keys.yaml).
export const SENDER00: Keypair = {
  account: 'sender00',
  publicKey: '368820f80c324bbc7c2b0610688a7da43e39f91d118732671cd9c7500ff43cca',
  secretKey: '251a920c403ae8c8f65f59142316af3c82b631fba46ddea92ee8c95035bd2898',
};

export const signerFor = (kp: Keypair) =>
  createSignWithKeypair({ publicKey: kp.publicKey, secretKey: kp.secretKey });

// Deterministic throwaway personas (devnet-only; derived keys, never reused).
import { genKeyPair } from '@kadena/cryptography-utils';
export function persona(name: string): Keypair {
  const kp = genKeyPair();
  return { account: `k:${kp.publicKey}`, publicKey: kp.publicKey, secretKey: kp.secretKey! };
}

export function unwrap(v: any): any {
  if (v === null || v === undefined) return v;
  if (typeof v === 'object') {
    if ('int' in v) return Number(v.int);
    if ('decimal' in v) return Number(v.decimal);
    if ('time' in v) return v.time;
    if ('timep' in v) return v.timep;
  }
  return v;
}

function assertSuccess(r: ICommandResult, label: string): any {
  if (r.result.status !== 'success') {
    throw new Error(`${label} FAILED: ${JSON.stringify((r.result as any).error)}`);
  }
  return (r.result as any).data;
}

export async function localCall(code: string, chainId: ChainId = CHAIN): Promise<any> {
  const tx: IUnsignedCommand = Pact.builder
    .execution(code)
    .setMeta({ chainId, senderAccount: SENDER00.account, gasLimit: GAS_LIMIT, gasPrice: GAS_PRICE })
    .setNetworkId(NETWORK_ID)
    .createTransaction();
  const r = await client.local(tx, { preflight: false, signatureVerification: false });
  return unwrap(assertSuccess(r, `local(${code.slice(0, 70)})`));
}

export async function localExpectFail(code: string, mustContain: string, chainId: ChainId = CHAIN): Promise<string> {
  try {
    await localCall(code, chainId);
  } catch (e: any) {
    const msg = e?.message ?? String(e);
    if (!msg.toLowerCase().includes(mustContain.toLowerCase())) {
      throw new Error(`expected error containing "${mustContain}", got: ${msg.slice(0, 300)}`);
    }
    return msg;
  }
  throw new Error(`EXPECTED local failure ("${mustContain}") but call succeeded: ${code.slice(0, 80)}`);
}

export async function coinBalance(account: string, chainId: ChainId = CHAIN): Promise<number> {
  try {
    return Number(await localCall(`(coin.get-balance "${account}")`, chainId));
  } catch {
    return 0;
  }
}

export async function chainTime(chainId: ChainId = CHAIN): Promise<Date> {
  const t = await localCall(`(at 'block-time (chain-data))`, chainId);
  return new Date(typeof t === 'string' ? t : (t as any).time);
}

export type CapBuilder = (wc: (n: string, ...a: any[]) => any) => any[];
export type SignerSpec = { kp: Keypair; caps?: CapBuilder };

export type SendOpts = {
  code: string;
  label: string;
  signers: SignerSpec[];        // first signer pays gas
  data?: Record<string, any>;
  chainId?: ChainId;
  gasLimit?: number;
};

export type StepRecord = { label: string; requestKey: string; gas: number };
const steps: StepRecord[] = [];
export function recordSteps(): StepRecord[] { return steps; }

// Submit a multi-signer tx and poll to confirmation. THROWS on failure.
export async function send(o: SendOpts): Promise<ICommandResult> {
  let b: any = Pact.builder.execution(o.code);
  for (const s of o.signers) {
    b = s.caps ? b.addSigner(s.kp.publicKey, s.caps) : b.addSigner(s.kp.publicKey);
  }
  for (const [k, v] of Object.entries(o.data ?? {})) b = b.addData(k, v);
  const tx = b
    .setMeta({
      chainId: o.chainId ?? CHAIN,
      senderAccount: o.signers[0].kp.account,
      gasLimit: o.gasLimit ?? GAS_LIMIT,
      gasPrice: GAS_PRICE,
    })
    .setNetworkId(NETWORK_ID)
    .createTransaction();
  let signed: any = tx;
  for (const s of o.signers) signed = await signerFor(s.kp)(signed);
  const desc = await client.submit(signed);
  const r = await client.pollOne(desc, { timeout: 600_000, interval: 4_000 });
  if (r.result.status !== 'success') {
    throw new Error(`${o.label} FAILED: ${JSON.stringify((r.result as any).error)}`);
  }
  steps.push({ label: o.label, requestKey: desc.requestKey, gas: (r as any).gas });
  console.log(`  ✓ ${o.label}  (gas ${(r as any).gas}, rk ${desc.requestKey.slice(0, 12)}…)`);
  return r;
}

export async function sendExpectFail(o: SendOpts, mustContain: string): Promise<string> {
  let err = '';
  try {
    await send({ ...o, label: `${o.label} [expect-fail]` });
    throw new Error(`EXPECTED FAILURE but ${o.label} SUCCEEDED`);
  } catch (e: any) {
    err = e?.message ?? String(e);
    if (err.includes('EXPECTED FAILURE but')) throw e;
  }
  if (!err.toLowerCase().includes(mustContain.toLowerCase())) {
    throw new Error(`${o.label}: failed but error did not contain "${mustContain}". Got: ${err.slice(0, 300)}`);
  }
  console.log(`  ✓ ${o.label} correctly rejected ("${mustContain}")`);
  return err;
}

// Load a library template's source, patch it for devnet deployment under the
// `free` namespace (namespaced governance keyset), exactly as the README
// prescribes, and return { code, govKeyset }.
// `uniq` should be the (already unique) deployed module name so the gov
// keyset name is unique per run too — redefining an existing keyset requires
// satisfying the OLD keyset, which a fresh persona cannot.
export function loadTemplate(slug: string, file: string, govConst: string, uniq: string): { code: string; govKeyset: string } {
  const src = readFileSync(join(ROOT, 'contracts', 'library', slug, file), 'utf8');
  const govKeyset = `free.pco-${uniq}-gov`;
  const patched = src.replace(`"${govConst}"`, `"${govKeyset}"`);
  if (patched === src) throw new Error(`gov keyset const "${govConst}" not found in ${file}`);
  return { code: `(namespace "free")\n${patched}`, govKeyset };
}

// The NFT standard interfaces live in the PCO-owned principal namespace on
// real networks (testnet06: n_e82dd10f…). The recap devnet cannot create that
// namespace (its `ns` module lacks create-principal-namespace, and past the
// height-700 migration the ns keysets are no longer open), so the devnet
// rehearsal substitutes the pre-existing open `user` namespace — the same
// cross-namespace topology: interfaces in one namespace, module in another,
// implements/dispatch fully qualified.
export const PCO_NS = 'n_e82dd10f74b7e8c253553de95629fdfa35cf8379';
export const DEVNET_IFACE_NS = 'user';

// Substitute the PCO namespace literal for the devnet interface namespace,
// asserting the exact occurrence count so a source drift is caught, not masked.
export function substPcoNs(code: string, expected: number): string {
  const hits = code.split(PCO_NS).length - 1;
  if (hits !== expected) {
    throw new Error(`expected ${expected} PCO-ns literal occurrence(s), found ${hits} — review before deploying`);
  }
  return code.split(PCO_NS).join(DEVNET_IFACE_NS);
}

// Deploy nft-asset-v1 + nft-market-v1 into the devnet interface namespace.
// Idempotent: interfaces are frozen (CannotUpgradeInterface), so if a prior
// run already published them we must skip, not redeploy.
export async function ensureStandardInterfaces(signer: Keypair): Promise<void> {
  try {
    await localCall(`(describe-module "${DEVNET_IFACE_NS}.nft-asset-v1")`);
    console.log(`  standard interfaces already present in ${DEVNET_IFACE_NS}/ — skipping deploy`);
    return;
  } catch { /* not deployed yet */ }
  const asset = readFileSync(join(ROOT, 'contracts', 'standards', 'nft-asset-v1.pact'), 'utf8');
  const market = readFileSync(join(ROOT, 'contracts', 'standards', 'nft-market-v1.pact'), 'utf8');
  await send({
    code: `(namespace "${DEVNET_IFACE_NS}")\n${asset}\n${market}`,
    label: `deploy nft-asset-v1 + nft-market-v1 into ${DEVNET_IFACE_NS}/`,
    signers: [{ kp: signer }],
  });
}

// Fund a persona account from sender00.
export async function fund(kp: Keypair, amount: number): Promise<void> {
  await send({
    code: `(coin.transfer-create "sender00" "${kp.account}" (read-keyset "g") ${amount.toFixed(1)})`,
    label: `fund ${kp.account.slice(0, 14)}… with ${amount} KDA`,
    signers: [{
      kp: SENDER00,
      caps: (wc) => [wc('coin.TRANSFER', 'sender00', kp.account, { decimal: amount.toFixed(1) }), wc('coin.GAS')],
    }],
    data: { g: { keys: [kp.publicKey], pred: 'keys-all' } },
  });
}

export function ksData(name: string, ...kps: Keypair[]): Record<string, any> {
  return { [name]: { keys: kps.map((k) => k.publicKey), pred: 'keys-all' } };
}

// Persist the campaign step log for the report.
export { Pact };

export function saveResults(slug: string, extra: Record<string, any> = {}): void {
  const out = {
    template: slug,
    network: NETWORK_ID,
    host: DEVNET_HOST,
    chain: CHAIN,
    date: new Date().toISOString(),
    steps: recordSteps(),
    ...extra,
  };
  const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'results');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${slug}.json`), JSON.stringify(out, null, 2));
  console.log(`\nRESULT: ${slug} devnet validation PASSED (${recordSteps().length} confirmed txs)`);
}
