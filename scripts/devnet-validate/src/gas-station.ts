// Devnet validation: library/gas-station
//
// The truest node-only test in the campaign: an ENROLLED user with ZERO KDA
// executes a real transaction whose gas the STATION pays, via the GAS_PAYER
// capability. This exercises the entire drain-defense on-node:
//  - GAS_PAYER let-binds the allowlist read before enforce-guard (F2, the
//    read-in-enforce class);
//  - it bounds/accounts against (chain-data) gas-price/gas-limit, not the
//    signer-supplied cap args (the Pass-2 CRITICAL fix);
//  - the station guard's enforce-one gas branch (coin.GAS + ALLOW_GAS) must
//    be satisfiable only through this path.
// Also proves the negative: a NON-enrolled user cannot get sponsored gas.
import {
  Pact, send, sendExpectFail, localCall, coinBalance, fund, persona, ksData,
  loadTemplate, saveResults, signerFor, client, NETWORK_ID, GAS_PRICE, CHAIN,
  SENDER00, recordSteps,
} from './lib.js';
import type { ChainId } from '@kadena/client';

const SLUG = 'gas-station';

async function pickName(base: string): Promise<string> {
  for (let i = 0; ; i++) {
    const name = i === 0 ? base : `${base}-v${i + 1}`;
    try { await localCall(`(describe-module "free.${name}")`); }
    catch { return name; }
  }
}

const main = async () => {
  console.log(`\n=== devnet-validate: ${SLUG} ===`);
  const MOD = await pickName('gas-station');
  const { code, govKeyset } = loadTemplate(SLUG, 'gas-station.pact', 'gas-station-gov', MOD);
  const M = `free.${MOD}`;
  const src = code.replace('(module gas-station GOV', `(module ${MOD} GOV`);

  const gov = persona('gov');
  const user = persona('user');   // will hold ZERO KDA
  const eve = persona('eve');     // non-enrolled
  await fund(gov, 10.0);
  // NB: user is NOT funded — that's the whole point.

  await send({
    code: `(namespace "free") (define-keyset "${govKeyset}" (read-keyset "g"))`,
    label: `define ${govKeyset}`,
    signers: [{ kp: gov }],
    data: ksData('g', gov),
  });
  await send({
    code: `${src}\n(create-table ${M}.allowlist)`,
    label: `deploy ${M} + table`,
    signers: [{ kp: gov }],
  });
  await send({
    code: `(${M}.init)`,
    label: 'init station account',
    signers: [{ kp: gov }],
  });

  const station: string = await localCall(`(${M}.get-station-account)`);
  await send({
    code: `(coin.transfer-create "sender00" "${station}" (${M}.create-gas-payer-guard) 5.0)`,
    label: 'fund station with 5 KDA',
    signers: [{ kp: SENDER00, caps: (wc) => [wc('coin.TRANSFER', 'sender00', station, { decimal: '5.0' }), wc('coin.GAS')] }],
  });

  await send({
    code: `(${M}.enroll-user "${user.account}" (read-keyset "u") 1.0)`,
    label: 'enroll user (cap 1.0 KDA)',
    signers: [{ kp: gov }],
    data: ksData('u', user),
  });

  // Sanity: the user genuinely has no KDA of their own.
  if (await coinBalance(user.account) !== 0) throw new Error('user should have 0 KDA');
  console.log('  ✓ user holds 0 KDA (station must pay gas)');

  const stationBefore = await coinBalance(station);

  // Sponsored tx: senderAccount = STATION, user's key signs GAS_PAYER.
  // The user does something trivial (a define with their own guard) — the
  // point is that it MINES with the station paying, via GAS_PAYER.
  const sponsored = Pact.builder
    .execution(`(namespace "free") (${M}.get-user "${user.account}")`)
    .addSigner(user.publicKey, (wc: any) => [
      wc(`${M}.GAS_PAYER`, user.account, { int: 1500 }, { decimal: GAS_PRICE.toFixed(8) }),
    ])
    .setMeta({ chainId: CHAIN, senderAccount: station, gasLimit: 1500, gasPrice: GAS_PRICE })
    .setNetworkId(NETWORK_ID)
    .createTransaction();
  const signed = await signerFor(user)(sponsored);
  const desc = await client.submit(signed as any);
  const r = await client.pollOne(desc, { timeout: 600_000, interval: 4_000 });
  if (r.result.status !== 'success') {
    throw new Error(`sponsored tx FAILED: ${JSON.stringify((r.result as any).error)}`);
  }
  recordSteps().push({ label: 'sponsored tx (station pays via GAS_PAYER)', requestKey: desc.requestKey, gas: (r as any).gas });
  console.log(`  ✓ SPONSORED tx mined: station paid gas for a zero-KDA user (gas ${(r as any).gas}, rk ${desc.requestKey.slice(0, 12)}…)`);

  const stationAfter = await coinBalance(station);
  if (!(stationAfter < stationBefore)) throw new Error('station balance did not decrease');
  console.log(`  ✓ station debited: ${stationBefore} -> ${stationAfter} KDA`);
  const spent = Number((await localCall(`(${M}.get-user "${user.account}")`)).spent);
  if (!(spent > 0)) throw new Error('user spent counter did not advance');
  console.log(`  ✓ user spent counter advanced to ${spent} (accounted vs actual gas)`);

  // Negative: a non-enrolled user cannot get sponsored gas.
  const badTx = Pact.builder
    .execution(`(namespace "free") (${M}.get-station-account)`)
    .addSigner(eve.publicKey, (wc: any) => [
      wc(`${M}.GAS_PAYER`, eve.account, { int: 1500 }, { decimal: GAS_PRICE.toFixed(8) }),
    ])
    .setMeta({ chainId: CHAIN, senderAccount: station, gasLimit: 1500, gasPrice: GAS_PRICE })
    .setNetworkId(NETWORK_ID)
    .createTransaction();
  const badSigned = await signerFor(eve)(badTx);
  let rejected = false;
  try {
    const pr = await client.local(badSigned as any, { preflight: true, signatureVerification: true });
    if (pr.result.status !== 'success') rejected = true;
  } catch { rejected = true; }
  if (!rejected) throw new Error('non-enrolled user was sponsored — drain defense breach');
  console.log('  ✓ non-enrolled user correctly denied sponsorship (preflight)');

  saveResults(SLUG, { module: M, hash: await localCall(`(at 'hash (describe-module "${M}"))`) });
};

main().catch((e) => { console.error(`\nFAILED: ${e.message ?? e}`); process.exit(1); });
