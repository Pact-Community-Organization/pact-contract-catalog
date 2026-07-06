// Devnet validation: library/oracle-feed
//
// Drives enroll -> post -> read on a real KDA-CE node. Node-critical
// evidence: PUBLISH-AUTH binds a config read before its enforce; get-price's
// whole read pipeline (map/with-default-read/filter/sort/median) runs
// on-node, both via /local and inside an executed transaction (a consumer
// exec), plus the staleness fail-closed path against real block timestamps.
import {
  send, sendExpectFail, localCall, localExpectFail, fund, persona, ksData,
  loadTemplate, saveResults,
} from './lib.js';

const SLUG = 'oracle-feed';

async function pickName(base: string): Promise<string> {
  for (let i = 0; ; i++) {
    const name = i === 0 ? base : `${base}-v${i + 1}`;
    try { await localCall(`(describe-module "free.${name}")`); }
    catch { return name; }
  }
}

const main = async () => {
  console.log(`\n=== devnet-validate: ${SLUG} ===`);
  const MOD = await pickName('oracle-feed');
  const { code, govKeyset } = loadTemplate(SLUG, 'oracle-feed.pact', 'oracle-feed-gov', MOD);
  const M = `free.${MOD}`;
  const src = code.replace('(module oracle-feed GOV', `(module ${MOD} GOV`);

  const gov = persona('gov');
  // Publisher accounts are named nodes, NOT k: principals: the template bans
  // ':' in publisher names (obs-key injectivity, auditor F1), and k: names
  // contain a colon. Use vanity names guarded by each node's own key.
  const sfx = MOD.replace('oracle-feed', '').replace(/^-/, '') || 'r1'; // unique per run
  const n1 = { ...persona('node1'), account: `node-1-${sfx}` };
  const n2 = { ...persona('node2'), account: `node-2-${sfx}` };
  const n3 = { ...persona('node3'), account: `node-3-${sfx}` };
  const eve = { ...persona('eve'), account: `eve-${sfx}` };
  for (const kp of [gov, n1, n2, n3, eve]) await fund(kp, 5.0);

  await send({
    code: `(namespace "free") (define-keyset "${govKeyset}" (read-keyset "g"))`,
    label: `define ${govKeyset}`,
    signers: [{ kp: gov }],
    data: ksData('g', gov),
  });
  await send({
    code: `${src}\n(create-table ${M}.config)(create-table ${M}.publisher-guards)(create-table ${M}.feeds)(create-table ${M}.observations)`,
    label: `deploy ${M} + tables`,
    signers: [{ kp: gov }],
  });
  await send({
    code: `(${M}.init ["${n1.account}" "${n2.account}" "${n3.account}"]
             [(read-keyset "a") (read-keyset "b") (read-keyset "c")])
           (${M}.create-feed "KDA/USD" "KDA spot (devnet validation)" 2)`,
    label: 'init 3 publishers + create feed (quorum 2)',
    signers: [{ kp: gov }],
    data: { ...ksData('a', n1), ...ksData('b', n2), ...ksData('c', n3) },
  });

  await sendExpectFail({
    code: `(${M}.post "KDA/USD" "${eve.account}" 1.0)`,
    label: 'non-publisher post',
    signers: [{ kp: eve, caps: (wc) => [wc(`${M}.PUBLISH-AUTH`, eve.account), wc('coin.GAS')] }],
  }, 'not an enrolled publisher');

  // below-quorum read must fail closed BEFORE enough posts exist
  await localExpectFail(`(${M}.get-price "KDA/USD" 3600.0)`, 'insufficient fresh answers');
  console.log('  ✓ below-quorum read fails closed (local)');

  // NODE-CRITICAL: PUBLISH-AUTH bound config read -> enforce, on-node.
  await send({
    code: `(${M}.post "KDA/USD" "${n1.account}" 1.00)`,
    label: 'node1 posts 1.00 (PUBLISH-AUTH on node)',
    signers: [{ kp: n1, caps: (wc) => [wc(`${M}.PUBLISH-AUTH`, n1.account), wc('coin.GAS')] }],
  });
  await send({
    code: `(${M}.post "KDA/USD" "${n2.account}" 1.10)`,
    label: 'node2 posts 1.10',
    signers: [{ kp: n2, caps: (wc) => [wc(`${M}.PUBLISH-AUTH`, n2.account), wc('coin.GAS')] }],
  });
  await send({
    code: `(${M}.post "KDA/USD" "${n3.account}" 99.9)`,
    label: 'node3 posts 99.9 (outlier)',
    signers: [{ kp: n3, caps: (wc) => [wc(`${M}.PUBLISH-AUTH`, n3.account), wc('coin.GAS')] }],
  });

  const p = Number(await localCall(`(${M}.get-price "KDA/USD" 3600.0)`));
  if (p !== 1.1) throw new Error(`median expected 1.1, got ${p}`);
  console.log(`  ✓ median swallows the outlier on-node: ${p}`);

  // the read pipeline inside an EXECUTED tx (consumer path), not just /local
  await send({
    code: `(enforce (= 1.1 (${M}.get-price "KDA/USD" 3600.0)) "unexpected price")`,
    label: 'consumer exec reads the median in a mined tx',
    signers: [{ kp: eve }],
  });

  // staleness fail-closed against REAL block timestamps: a 1-second window
  // cannot contain observations from earlier blocks
  await localExpectFail(`(${M}.get-price "KDA/USD" 1.0)`, 'insufficient fresh answers');
  console.log('  ✓ staleness window fails closed against real block timestamps');

  // rotation revokes the outlier's standing observation immediately
  await send({
    code: `(${M}.rotate-publishers ["${n1.account}" "${n2.account}"]
             [(read-keyset "a") (read-keyset "b")])`,
    label: 'rotate node3 out',
    signers: [{ kp: gov }],
    data: { ...ksData('a', n1), ...ksData('b', n2) },
  });
  const p2 = Number(await localCall(`(${M}.get-price "KDA/USD" 3600.0)`));
  if (Math.abs(p2 - 1.05) > 1e-9) throw new Error(`post-rotation median expected 1.05, got ${p2}`);
  console.log(`  ✓ rotation revoked the outlier: median now ${p2}`);

  saveResults(SLUG, { module: M, hash: await localCall(`(at 'hash (describe-module "${M}"))`) });
};

main().catch((e) => { console.error(`\nFAILED: ${e.message ?? e}`); process.exit(1); });
