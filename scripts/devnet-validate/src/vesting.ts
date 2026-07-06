// Devnet validation: library/vesting
//
// Drives escrow -> claim -> revoke on a real KDA-CE node. Node-critical
// evidence: CLAIM-AUTH binds a grants-table read before enforce-guard, and
// REVOKE-AUTH reads the funder's LIVE coin guard via coin.details - both
// REPL-green patterns proven here on-node. Grants use past start dates so
// the live clock needs no manipulation; assertions carry a small tolerance
// because vesting accrues per second.
import {
  send, sendExpectFail, localCall, coinBalance, fund, persona, ksData,
  loadTemplate, saveResults, chainTime,
} from './lib.js';

const SLUG = 'vesting';
const DAY = 86_400_000;

const iso = (d: Date) => d.toISOString().replace(/\.\d+Z$/, 'Z');
const near = (a: number, b: number, eps = 0.01) => Math.abs(a - b) <= eps;

async function pickName(base: string): Promise<string> {
  for (let i = 0; ; i++) {
    const name = i === 0 ? base : `${base}-v${i + 1}`;
    try { await localCall(`(describe-module "free.${name}")`); }
    catch { return name; }
  }
}

const main = async () => {
  console.log(`\n=== devnet-validate: ${SLUG} ===`);
  const MOD = await pickName('vesting');
  const { code, govKeyset } = loadTemplate(SLUG, 'vesting.pact', 'vesting-gov', MOD);
  const M = `free.${MOD}`;
  const src = code.replace('(module vesting GOV', `(module ${MOD} GOV`);

  const gov = persona('gov');
  const funder = persona('funder');
  const ben = persona('ben');
  const eve = persona('eve');
  for (const kp of [gov, eve]) await fund(kp, 5.0);
  await fund(funder, 30.0);
  await fund(ben, 2.0);

  await send({
    code: `(namespace "free") (define-keyset "${govKeyset}" (read-keyset "g"))`,
    label: `define ${govKeyset}`,
    signers: [{ kp: gov }],
    data: ksData('g', gov),
  });
  await send({
    code: `${src}\n(create-table ${M}.grants)`,
    label: `deploy ${M} + table`,
    signers: [{ kp: gov }],
  });

  const now = await chainTime();
  const t = (days: number) => iso(new Date(now.getTime() + days * DAY));
  const vaultAcct: string = await localCall(`(${M}.get-vault-account)`);

  // g1: non-revocable, halfway vested (start -100d, cliff -10d, end +100d)
  await send({
    code: `(${M}.create-grant "g1" "${funder.account}" "${ben.account}" (read-keyset "b")
             10.0 (time "${t(-100)}") (time "${t(-10)}") (time "${t(100)}") false)`,
    label: 'create-grant g1 (escrow 10 KDA upfront)',
    signers: [{
      kp: funder,
      caps: (wc) => [wc('coin.TRANSFER', funder.account, vaultAcct, { decimal: '10.0' }), wc('coin.GAS')],
    }],
    data: ksData('b', ben),
  });

  const claimable = Number(await localCall(`(${M}.claimable-amount "g1")`));
  if (!near(claimable, 5.0)) throw new Error(`g1 claimable expected ~5.0, got ${claimable}`);
  console.log(`  ✓ g1 halfway vested: claimable ${claimable}`);

  await sendExpectFail({
    code: `(${M}.claim "g1")`,
    label: 'claim g1 with a foreign key',
    signers: [{ kp: eve, caps: (wc) => [wc(`${M}.CLAIM-AUTH`, 'g1'), wc('coin.GAS')] }],
  }, 'Keyset failure');

  const benBefore = await coinBalance(ben.account);
  // NODE-CRITICAL: CLAIM-AUTH bound read -> enforce-guard, on-node.
  const r = await send({
    code: `(${M}.claim "g1")`,
    label: 'claim g1 (CLAIM-AUTH on node)',
    signers: [{ kp: ben, caps: (wc) => [wc(`${M}.CLAIM-AUTH`, 'g1'), wc('coin.GAS')] }],
  });
  const benAfter = await coinBalance(ben.account);
  const paid = benAfter - benBefore + Number((r as any).gas) * 1e-8;
  if (!near(paid, 5.0)) throw new Error(`g1 payout expected ~5.0, got ${paid}`);
  console.log(`  ✓ ben paid ~5.0 KDA (${paid.toFixed(6)})`);

  // g3: cliff still in the future -> nothing claimable (clean negative on a live clock)
  await send({
    code: `(${M}.create-grant "g3" "${funder.account}" "${ben.account}" (read-keyset "b")
             2.0 (time "${t(-10)}") (time "${t(50)}") (time "${t(100)}") false)`,
    label: 'create-grant g3 (pre-cliff)',
    signers: [{
      kp: funder,
      caps: (wc) => [wc('coin.TRANSFER', funder.account, vaultAcct, { decimal: '2.0' }), wc('coin.GAS')],
    }],
    data: ksData('b', ben),
  });
  await sendExpectFail({
    code: `(${M}.claim "g3")`,
    label: 'pre-cliff claim',
    signers: [{ kp: ben, caps: (wc) => [wc(`${M}.CLAIM-AUTH`, 'g3'), wc('coin.GAS')] }],
  }, 'nothing claimable');

  // g2: revocable, halfway vested; revoke freezes it, refund returns to funder
  await send({
    code: `(${M}.create-grant "g2" "${funder.account}" "${ben.account}" (read-keyset "b")
             5.0 (time "${t(-50)}") (time "${t(-50)}") (time "${t(50)}") true)`,
    label: 'create-grant g2 (revocable, escrow 5 KDA)',
    signers: [{
      kp: funder,
      caps: (wc) => [wc('coin.TRANSFER', funder.account, vaultAcct, { decimal: '5.0' }), wc('coin.GAS')],
    }],
    data: ksData('b', ben),
  });

  await sendExpectFail({
    code: `(${M}.revoke "g2")`,
    label: 'revoke by non-funder',
    signers: [{ kp: eve, caps: (wc) => [wc(`${M}.REVOKE-AUTH`, 'g2'), wc('coin.GAS')] }],
  }, 'Keyset failure');

  const funderBefore = await coinBalance(funder.account);
  // NODE-CRITICAL: REVOKE-AUTH reads the funder's LIVE coin guard (coin.details).
  const rv = await send({
    code: `(${M}.revoke "g2")`,
    label: 'revoke g2 (live coin.details guard on node)',
    signers: [{ kp: funder, caps: (wc) => [wc(`${M}.REVOKE-AUTH`, 'g2'), wc('coin.GAS')] }],
  });
  const funderAfter = await coinBalance(funder.account);
  const refund = funderAfter - funderBefore + Number((rv as any).gas) * 1e-8;
  if (!near(refund, 2.5)) throw new Error(`g2 refund expected ~2.5, got ${refund}`);
  console.log(`  ✓ funder refunded ~2.5 KDA unvested (${refund.toFixed(6)})`);

  await send({
    code: `(${M}.claim "g2")`,
    label: 'claim g2 frozen remainder',
    signers: [{ kp: ben, caps: (wc) => [wc(`${M}.CLAIM-AUTH`, 'g2'), wc('coin.GAS')] }],
  });
  // frozen: total == claimed exactly, no further accrual even as time passes
  await sendExpectFail({
    code: `(${M}.claim "g2")`,
    label: 'claim after revoke exhausts the frozen grant',
    signers: [{ kp: ben, caps: (wc) => [wc(`${M}.CLAIM-AUTH`, 'g2'), wc('coin.GAS')] }],
  }, 'nothing claimable');

  const vault = await coinBalance(vaultAcct);
  // outstanding: g1 remainder (~5 minus per-second dust already claimed) + g3 full 2.0
  if (!near(vault, 7.0, 0.02)) throw new Error(`vault conservation expected ~7.0, got ${vault}`);
  console.log(`  ✓ vault conserved (~7.0 KDA outstanding: g1 remainder + g3): ${vault.toFixed(6)}`);

  saveResults(SLUG, { module: M, hash: await localCall(`(at 'hash (describe-module "${M}"))`) });
};

main().catch((e) => { console.error(`\nFAILED: ${e.message ?? e}`); process.exit(1); });
