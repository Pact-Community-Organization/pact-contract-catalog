// Devnet validation: library/multisig-treasury
//
// Drives the full M-of-N cycle on a real KDA-CE node. This is the required
// evidence for the template's F1 class: SIGNER-AUTH binds a config-table read
// before its enforce, and account-exists try-reads coin - both REPL-green
// patterns that this run proves on-node (an unfixed variant would abort here
// with "Operation is not allowed in read-only or system-only mode").
import {
  send, sendExpectFail, localCall, coinBalance, fund, persona, ksData,
  loadTemplate, saveResults, SENDER00,
} from './lib.js';

const SLUG = 'multisig-treasury';

async function pickName(base: string): Promise<string> {
  for (let i = 0; ; i++) {
    const name = i === 0 ? base : `${base}-v${i + 1}`;
    try { await localCall(`(describe-module "free.${name}")`); }
    catch { return name; }
  }
}

const main = async () => {
  console.log(`\n=== devnet-validate: ${SLUG} ===`);
  const MOD = await pickName('treasury');
  const { code, govKeyset } = loadTemplate(SLUG, 'treasury.pact', 'treasury-gov', MOD);
  const M = `free.${MOD}`;
  const src = code.replace('(module treasury GOV', `(module ${MOD} GOV`);

  const gov = persona('gov');
  const alice = persona('alice');
  const bob = persona('bob');
  const carol = persona('carol');
  const dana = persona('dana');   // recipient
  const eve = persona('eve');     // non-signer attacker

  // gas money for the personas that submit txs themselves
  for (const kp of [gov, alice, bob, carol, eve]) await fund(kp, 5.0);
  await fund(dana, 1.0); // recipient must exist (propose enforces it via try-read)

  await send({
    code: `(namespace "free") (define-keyset "${govKeyset}" (read-keyset "g"))`,
    label: `define ${govKeyset}`,
    signers: [{ kp: gov }],
    data: ksData('g', gov),
  });

  await send({
    code: `${src}\n(create-table ${M}.config)(create-table ${M}.proposals)(create-table ${M}.signer-guards)`,
    label: `deploy ${M} + tables`,
    signers: [{ kp: gov }],
    gasLimit: 150000,
  });

  await send({
    code: `(${M}.init ["${alice.account}" "${bob.account}" "${carol.account}"] 2
             [(read-keyset "a") (read-keyset "b") (read-keyset "c")])`,
    label: 'init 2-of-3 signer set',
    signers: [{ kp: gov }],
    data: { ...ksData('a', alice), ...ksData('b', bob), ...ksData('c', carol) },
  });

  const vaultAcct: string = await localCall(`(${M}.get-vault-account)`);
  await send({
    code: `(coin.transfer-create "sender00" "${vaultAcct}" (${M}.create-vault-guard) 10.0)`,
    label: 'fund vault with 10 KDA',
    signers: [{
      kp: SENDER00,
      caps: (wc) => [wc('coin.TRANSFER', 'sender00', vaultAcct, { decimal: '10.0' }), wc('coin.GAS')],
    }],
  });

  // NODE-CRITICAL: propose acquires SIGNER-AUTH (bound config read -> enforce)
  // and runs the recipient-exists try-read against the real node.
  await send({
    code: `(${M}.propose "p1" "${alice.account}" "${dana.account}" 3.5)`,
    label: 'propose p1 (SIGNER-AUTH + try-read on node)',
    signers: [{ kp: alice, caps: (wc) => [wc(`${M}.SIGNER-AUTH`, alice.account), wc('coin.GAS')] }],
  });

  await sendExpectFail({
    code: `(${M}.propose "p2" "${eve.account}" "${dana.account}" 1.0)`,
    label: 'non-signer propose',
    signers: [{ kp: eve, caps: (wc) => [wc(`${M}.SIGNER-AUTH`, eve.account), wc('coin.GAS')] }],
  }, 'not an authorized signer');

  await sendExpectFail({
    code: `(${M}.execute "p1")`,
    label: 'execute below threshold',
    signers: [{ kp: eve }],
  }, 'below threshold');

  await send({
    code: `(${M}.approve "p1" "${bob.account}")`,
    label: 'approve p1 (2nd of 2)',
    signers: [{ kp: bob, caps: (wc) => [wc(`${M}.SIGNER-AUTH`, bob.account), wc('coin.GAS')] }],
  });

  const danaBefore = await coinBalance(dana.account);
  await send({
    code: `(${M}.execute "p1")`,
    label: 'execute p1 (permissionless, vault debits via SPEND)',
    signers: [{ kp: carol }],
  });
  const danaAfter = await coinBalance(dana.account);
  if (Math.abs(danaAfter - danaBefore - 3.5) > 1e-9) {
    throw new Error(`recipient balance wrong: ${danaBefore} -> ${danaAfter}`);
  }
  console.log(`  ✓ recipient received exactly 3.5 KDA (${danaBefore} -> ${danaAfter})`);

  const vault = await localCall(`(${M}.vault-balance)`);
  if (Math.abs(Number(vault) - 6.5) > 1e-9) throw new Error(`vault balance wrong: ${vault}`);
  console.log(`  ✓ vault conserved: 6.5 KDA remain`);

  saveResults(SLUG, { module: M, hash: await localCall(`(at 'hash (describe-module "${M}"))`) });
};

main().catch((e) => { console.error(`\nFAILED: ${e.message ?? e}`); process.exit(1); });
