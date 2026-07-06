// Devnet validation: library/token-fungible
//
// Drives mint -> transfer -> rotate on a real KDA-CE node. Node-critical
// evidence: DEBIT let-binds the sender's stored guard (read token-table)
// before enforce-guard - the exact CRITICAL that this template's v0.2.0 fix
// closed. An unfixed DEBIT (guard read inside enforce, or no guard at all)
// would either abort here or let a foreign key drain; this run proves the
// fixed path works on-node and the negative path is rejected.
import {
  send, sendExpectFail, localCall, fund, persona, ksData,
  loadTemplate, saveResults,
} from './lib.js';

const SLUG = 'token-fungible';

async function pickName(base: string): Promise<string> {
  for (let i = 0; ; i++) {
    const name = i === 0 ? base : `${base}-v${i + 1}`;
    try { await localCall(`(describe-module "free.${name}")`); }
    catch { return name; }
  }
}

const main = async () => {
  console.log(`\n=== devnet-validate: ${SLUG} ===`);
  const MOD = await pickName('token');
  const { code, govKeyset } = loadTemplate(SLUG, 'token.pact', 'token-gov', MOD);
  const M = `free.${MOD}`;
  const src = code.replace('(module token GOV', `(module ${MOD} GOV`);

  const sfx = MOD.replace('token', '').replace(/^-/, '') || 'r1';
  const gov = persona('gov');
  // alice is a VANITY token account (guarded by alice's key) so we can
  // demonstrate rotate — coin/this token forbid rotating a k: principal's
  // guard (correct protocol behavior, unrelated to the DEBIT node-safety
  // this run proves). bob/eve stay k: principals.
  const alice = { ...persona('alice'), account: `alice-${sfx}` };
  const bob = persona('bob');
  const eve = persona('eve');
  for (const kp of [gov, alice, bob, eve]) await fund(kp, 5.0);

  await send({
    code: `(namespace "free") (define-keyset "${govKeyset}" (read-keyset "g"))`,
    label: `define ${govKeyset}`,
    signers: [{ kp: gov }],
    data: ksData('g', gov),
  });
  await send({
    code: `${src}\n(create-table ${M}.token-table)`,
    label: `deploy ${M} + table`,
    signers: [{ kp: gov }],
  });

  // governance-gated mint (creates alice's account)
  await sendExpectFail({
    code: `(${M}.mint "${alice.account}" (read-keyset "a") 1000.0)`,
    label: 'mint without governance',
    signers: [{ kp: eve }],
    data: ksData('a', alice),
  }, 'Keyset failure');

  await send({
    code: `(${M}.mint "${alice.account}" (read-keyset "a") 1000.0)`,
    label: 'governance mints 1000 to alice',
    signers: [{ kp: gov }],
    data: ksData('a', alice),
  });
  if (Number(await localCall(`(${M}.get-balance "${alice.account}")`)) !== 1000)
    throw new Error('mint balance wrong');
  console.log('  ✓ alice minted 1000');

  // NODE-CRITICAL negative: eve scopes TRANSFER but is not the sender's guard.
  // The v0.2.0 DEBIT reads alice's stored guard and enforces it -> reject.
  await send({
    code: `(${M}.create-account "${bob.account}" (read-keyset "b"))`,
    label: 'create bob token account',
    signers: [{ kp: bob }],
    data: ksData('b', bob),
  });
  await sendExpectFail({
    code: `(${M}.transfer "${alice.account}" "${bob.account}" 100.0)`,
    label: 'foreign-key transfer (DEBIT guard enforcement)',
    signers: [{ kp: eve, caps: (wc) => [wc(`${M}.TRANSFER`, alice.account, bob.account, { decimal: '100.0' }), wc('coin.GAS')] }],
  }, 'Keyset failure');

  // NODE-CRITICAL positive: alice's own key satisfies the stored-guard read.
  await send({
    code: `(${M}.transfer "${alice.account}" "${bob.account}" 250.0)`,
    label: 'authorized transfer (DEBIT let-bound guard on node)',
    signers: [{ kp: alice, caps: (wc) => [wc(`${M}.TRANSFER`, alice.account, bob.account, { decimal: '250.0' }), wc('coin.GAS')] }],
  });
  if (Number(await localCall(`(${M}.get-balance "${bob.account}")`)) !== 250)
    throw new Error('transfer balance wrong');
  console.log('  ✓ authorized transfer moved 250 (alice 750 / bob 250)');

  // rotate alice's guard, then prove the OLD key can no longer debit
  const alice2 = persona('alice2');
  await send({
    code: `(${M}.rotate "${alice.account}" (read-keyset "a2"))`,
    label: 'alice rotates her guard',
    signers: [{ kp: alice, caps: (wc) => [wc(`${M}.ROTATE`, alice.account), wc('coin.GAS')] }],
    data: ksData('a2', alice2),
  });
  await sendExpectFail({
    code: `(${M}.transfer "${alice.account}" "${bob.account}" 10.0)`,
    label: 'old key after rotate (stored-guard read reflects new guard)',
    signers: [{ kp: alice, caps: (wc) => [wc(`${M}.TRANSFER`, alice.account, bob.account, { decimal: '10.0' }), wc('coin.GAS')] }],
  }, 'Keyset failure');
  console.log('  ✓ rotate updated the stored guard the DEBIT read enforces');

  saveResults(SLUG, { module: M, hash: await localCall(`(at 'hash (describe-module "${M}"))`) });
};

main().catch((e) => { console.error(`\nFAILED: ${e.message ?? e}`); process.exit(1); });
