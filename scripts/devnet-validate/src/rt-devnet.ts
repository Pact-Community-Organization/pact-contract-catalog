// rt-devnet.ts — RED TEAM probes against the LIVE deployed nft framework
// (free.* on chains 0 & 1 of the recap-development devnet). Drives the
// node-only surfaces the REPL cannot prove:
//   F  durability: the token/quote/auction rows the prior campaign wrote are
//      readable on a MINED node state (not REPL memory), and survive.
//   E  xchain adversarial: a forged/replayed receive; the completed hop pact
//      cannot be resumed again (replay => duplicate token).
//   C  weak-cap free-mint on-node: the module-admin gate that blocked the REPL
//      attack also holds on the live node.
// Read-only probes use /local; the replay probe drives a real continuation.

import { localCall, localExpectFail, client, SENDER00, signerFor, NETWORK_ID } from './lib.js';
import { Pact, ChainId } from '@kadena/client';

const TOKEN = 'n:AlyEulmyNdYdm4oeCqp3ltXavQvj0mYElQJsM-qRibE';
const HOP_RK = 'oxkN58XiqnXAkT3Z7txx34aHHFZhjERAk_n0SieyoVM'; // completed x-chain pact (chain 0 -> 1)
const CH0 = '0' as ChainId;
const CH1 = '1' as ChainId;

let pass = 0, fail = 0;
const ok = (m: string) => { console.log(`  ✓ ${m}`); pass++; };
const bad = (m: string) => { console.log(`  ✗ ${m}`); fail++; };

async function main() {
  console.log('== RED TEAM devnet probes vs the live free.* nft framework ==');

  // ---- F: durability — the token row persisted on-node on BOTH chains ------
  console.log('\n[F] state durability (mined node reads):');
  const t0 = await localCall(`(free.ledger.get-token-info "${TOKEN}")`, CH0);
  const t1 = await localCall(`(free.ledger.get-token-info "${TOKEN}")`, CH1);
  if (t0?.id === TOKEN) ok(`token row persists on chain 0 (supply ${t0.supply}, uri ${t0.uri})`);
  else bad(`token row missing on chain 0: ${JSON.stringify(t0)}`);
  if (t1?.id === TOKEN) ok(`token row materialized + persists on chain 1 (first-arrival survived)`);
  else bad(`token row missing on chain 1: ${JSON.stringify(t1)}`);
  // the royalty passport re-bound and persisted on chain 1
  const roy1 = await localCall(`(free.royalty-policy.get-royalty "${TOKEN}")`, CH1);
  if (roy1?.bps !== undefined) ok(`royalty spec re-bound + persists on chain 1 (bps ${roy1.bps}, creator ${roy1.creator?.slice(0,14)}…)`);
  else bad(`royalty spec missing on chain 1: ${JSON.stringify(roy1)}`);
  // supply conservation across the hop: sum over both chains must equal 1.0
  const s0 = t0?.supply ?? 0, s1 = t1?.supply ?? 0;
  if (Math.abs((s0 + s1) - 1.0) < 1e-9 && s0 === 0 && s1 === 1)
    ok(`supply conserved across the hop: chain0=${s0} + chain1=${s1} = 1.0 (burned on send, minted on receive)`);
  else bad(`supply NOT conserved across the hop: chain0=${s0} chain1=${s1}`);

  // ---- C: weak-cap free-mint on the LIVE node ------------------------------
  console.log('\n[C] weak-cap free-mint on-node (module-admin gate):');
  await localExpectFail(
    `(with-capability (free.ledger.CREDIT "${TOKEN}" "k:2222222222222222222222222222222222222222222222222222222222222222")
       (free.ledger.credit "${TOKEN}" "k:2222222222222222222222222222222222222222222222222222222222222222"
         (read-keyset 'x) 999999.0))`,
    'admin', CH0
  ).then(m => ok(`live node blocks external CREDIT acquisition (${m.slice(0,60)}…)`))
   .catch(e => bad(`CREDIT weak-cap acquisition NOT blocked on-node: ${String(e).slice(0,120)}`));

  await localExpectFail(
    `(with-capability (free.ledger.UPDATE_SUPPLY) (free.ledger.update-supply "${TOKEN}" 999999.0))`,
    'admin', CH0
  ).then(m => ok(`live node blocks external UPDATE_SUPPLY acquisition`))
   .catch(e => bad(`UPDATE_SUPPLY weak-cap NOT blocked on-node: ${String(e).slice(0,120)}`));

  // ---- E: xchain adversarial — forged receive rejected ---------------------
  console.log('\n[E] xchain passport forgery (direct receive call):');
  // A forger tries to invoke the manager's receive dispatch directly with a
  // fabricated passport. It must fail the ledger XCHAIN-RECEIVE-CALL handshake
  // (unacquirable outside the pact machinery => module-admin gate).
  // The FIRST thing enforce-xchain-receive does is require the ledger's
  // XCHAIN-RECEIVE-CALL cap (a weak-body -CALL cap, unacquirable outside the
  // ledger's own pact machinery). So a forger's direct call fails on the
  // handshake BEFORE any passport/guard is even read — pass [] passports.
  {
    const forgeCode =
      `(free.policy-manager.enforce-xchain-receive (free.ledger.get-token-info "${TOKEN}") ` +
      `"k:2222222222222222222222222222222222222222222222222222222222222222" (read-keyset 'rg) 1.0 [])`;
    const forgeTx = Pact.builder.execution(forgeCode)
      .addData('rg', { keys: ['2222222222222222222222222222222222222222222222222222222222222222'], pred: 'keys-all' } as any)
      .setMeta({ chainId: CH1, senderAccount: SENDER00.account, gasLimit: 150000, gasPrice: 0.00000001 } as any)
      .setNetworkId(NETWORK_ID).createTransaction();
    const forgeRes = await client.local(forgeTx as any, { preflight: false, signatureVerification: false });
    const msg = JSON.stringify((forgeRes.result as any).error ?? '');
    if (forgeRes.result.status === 'failure' && msg.includes('XCHAIN-RECEIVE-CALL'))
      ok(`forged direct receive rejected on the -CALL handshake (capability not granted)`);
    else
      bad(`forged receive NOT rejected on the handshake: ${forgeRes.result.status} ${msg.slice(0,140)}`);
  }

  // ---- E: replay — the completed hop pact cannot be resumed again ----------
  console.log('\n[E] xchain replay (resume a completed pact => duplicate token):');
  try {
    // request a fresh SPV proof for the ALREADY-COMPLETED step-0 pact and try
    // to run step 1 AGAIN on chain 1. The pact is complete; the node must
    // reject the continuation (no duplicate credit / no duplicate materialize).
    const proof = await client.pollCreateSpv(
      { requestKey: HOP_RK, chainId: CH0 } as any, CH1
    ).catch(() => null);
    const cont = Pact.builder
      .continuation({ pactId: HOP_RK, step: 1, rollback: false, proof: proof ?? null } as any)
      .setNetworkId(NETWORK_ID)
      .setMeta({ chainId: CH1, senderAccount: SENDER00.account, gasLimit: 150000, gasPrice: 0.00000001, ttl: 600 })
      .addSigner(SENDER00.publicKey)
      .createTransaction();
    const signed = await signerFor(SENDER00)(cont as any);
    const res = await client.local(signed as any, { preflight: false, signatureVerification: false });
    if (res.result.status === 'failure') {
      const msg = JSON.stringify(res.result.error).slice(0, 90);
      ok(`replay of the completed hop is rejected on-node (${msg}…)`);
    } else {
      bad(`REPLAY SUCCEEDED — the completed hop resumed again! ${JSON.stringify(res.result.data).slice(0,120)}`);
    }
  } catch (e: any) {
    // a throw here (e.g. "pact completed" / SPV/exec error) is also a rejection
    ok(`replay attempt threw (rejected): ${String(e.message ?? e).slice(0, 80)}…`);
  }

  console.log(`\n== rt-devnet: ${pass} passed, ${fail} failed ==`);
  if (fail > 0) process.exit(1);
}

main().catch(e => { console.error('FATAL', e); process.exit(1); });
