// Devnet validation: library/dao-voting
//
// Drives propose -> vote -> close on a real KDA-CE node. Node-critical
// evidence: MEMBER-AUTH binds a config-table read before its enforce (the
// REPL-invisible class). The proposal deadline is set ~90s out and the run
// polls real chain time until it passes - no clock manipulation.
import {
  send, sendExpectFail, localCall, fund, persona, ksData,
  loadTemplate, saveResults, chainTime,
} from './lib.js';

const SLUG = 'dao-voting';
const iso = (d: Date) => d.toISOString().replace(/\.\d+Z$/, 'Z');

async function pickName(base: string): Promise<string> {
  for (let i = 0; ; i++) {
    const name = i === 0 ? base : `${base}-v${i + 1}`;
    try { await localCall(`(describe-module "free.${name}")`); }
    catch { return name; }
  }
}

const main = async () => {
  console.log(`\n=== devnet-validate: ${SLUG} ===`);
  const MOD = await pickName('dao-voting');
  const { code, govKeyset } = loadTemplate(SLUG, 'dao-voting.pact', 'dao-voting-gov', MOD);
  const M = `free.${MOD}`;
  const src = code.replace('(module dao-voting GOV', `(module ${MOD} GOV`);

  const gov = persona('gov');
  const alice = persona('alice');
  const bob = persona('bob');
  const carol = persona('carol');
  const eve = persona('eve');
  for (const kp of [gov, alice, bob, carol, eve]) await fund(kp, 5.0);

  await send({
    code: `(namespace "free") (define-keyset "${govKeyset}" (read-keyset "g"))`,
    label: `define ${govKeyset}`,
    signers: [{ kp: gov }],
    data: ksData('g', gov),
  });
  await send({
    code: `${src}\n(create-table ${M}.config)(create-table ${M}.member-guards)(create-table ${M}.proposals)`,
    label: `deploy ${M} + tables`,
    signers: [{ kp: gov }],
  });
  await send({
    code: `(${M}.init ["${alice.account}" "${bob.account}" "${carol.account}"]
             [(read-keyset "a") (read-keyset "b") (read-keyset "c")] 50 60)`,
    label: 'init 3 members, quorum 50, threshold 60',
    signers: [{ kp: gov }],
    data: { ...ksData('a', alice), ...ksData('b', bob), ...ksData('c', carol) },
  });

  const now = await chainTime();
  const deadline = iso(new Date(now.getTime() + 90_000)); // ~90s of voting

  // NODE-CRITICAL: MEMBER-AUTH bound config read -> enforce, on-node.
  await send({
    code: `(${M}.propose "p1" "${alice.account}" "Devnet validation motion" (time "${deadline}"))`,
    label: 'propose p1 (MEMBER-AUTH on node)',
    signers: [{ kp: alice, caps: (wc) => [wc(`${M}.MEMBER-AUTH`, alice.account), wc('coin.GAS')] }],
  });

  await sendExpectFail({
    code: `(${M}.vote "p1" "${eve.account}" "yes")`,
    label: 'non-member vote',
    signers: [{ kp: eve, caps: (wc) => [wc(`${M}.MEMBER-AUTH`, eve.account), wc('coin.GAS')] }],
  }, 'not a member');

  await send({
    code: `(${M}.vote "p1" "${alice.account}" "yes")`,
    label: 'alice votes yes',
    signers: [{ kp: alice, caps: (wc) => [wc(`${M}.MEMBER-AUTH`, alice.account), wc('coin.GAS')] }],
  });
  await send({
    code: `(${M}.vote "p1" "${bob.account}" "yes")`,
    label: 'bob votes yes',
    signers: [{ kp: bob, caps: (wc) => [wc(`${M}.MEMBER-AUTH`, bob.account), wc('coin.GAS')] }],
  });
  await send({
    code: `(${M}.vote "p1" "${carol.account}" "no")`,
    label: 'carol votes no',
    signers: [{ kp: carol, caps: (wc) => [wc(`${M}.MEMBER-AUTH`, carol.account), wc('coin.GAS')] }],
  });

  await sendExpectFail({
    code: `(${M}.vote "p1" "${alice.account}" "no")`,
    label: 'double vote',
    signers: [{ kp: alice, caps: (wc) => [wc(`${M}.MEMBER-AUTH`, alice.account), wc('coin.GAS')] }],
  }, 'already voted');

  // wait for the REAL chain clock to pass the deadline (poll, never sleep-guess)
  process.stdout.write('  … waiting for chain time to pass the deadline ');
  for (;;) {
    const t = await chainTime();
    if (t.getTime() >= new Date(deadline).getTime()) break;
    process.stdout.write('.');
    await new Promise((res) => setTimeout(res, 10_000));
  }
  console.log(' reached');

  // permissionless close by a non-member
  await send({
    code: `(${M}.close "p1")`,
    label: 'close p1 (permissionless, after deadline)',
    signers: [{ kp: eve }],
  });
  const p = await localCall(`(${M}.get-proposal "p1")`);
  const status = (p as any).status;
  const yes = Number((p as any)['final-yes'].int ?? (p as any)['final-yes']);
  if (status !== 'passed' || yes !== 2) {
    throw new Error(`expected passed with 2 yes, got status=${status} yes=${yes}`);
  }
  console.log(`  ✓ p1 settled: passed (2 yes / 1 no, quorum + threshold met on-node)`);

  saveResults(SLUG, { module: M, hash: await localCall(`(at 'hash (describe-module "${M}"))`) });
};

main().catch((e) => { console.error(`\nFAILED: ${e.message ?? e}`); process.exit(1); });
