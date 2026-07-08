// Devnet validation: library/royalty-sale
//
// Proves the node-only class the auditor flagged (F1): buy reads the escrow
// balance in a plain `let` AFTER funding it, never inside a `try`/enforce
// read-only context. Drives a full settlement on a FRESH escrow (first sale)
// and again over a DUST-carrying escrow (griefer donation) - both must settle
// and conserve on a real KDA-CE node. Also exercises mint/list and the
// creator+marketplace+seller payout split end to end.
import {
  send, localCall, coinBalance, fund, persona, loadTemplate, saveResults, CHAIN,
  ensureStandardInterfaces, substPcoNs,
} from './lib.js';

const SLUG = 'royalty-sale';
const near = (a: number, b: number, eps = 1e-11) => Math.abs(a - b) <= eps;

async function pickName(base: string): Promise<string> {
  for (let i = 0; ; i++) {
    const name = i === 0 ? base : `${base}-v${i + 1}`;
    try { await localCall(`(describe-module "free.${name}")`); }
    catch { return name; }
  }
}

const main = async () => {
  console.log(`\n=== devnet-validate: ${SLUG} ===`);
  const MOD = await pickName('royalty-sale');
  const { code, govKeyset } = loadTemplate(SLUG, 'royalty-sale.pact', 'royalty-sale-gov', MOD);
  const M = `free.${MOD}`;
  // 4 = the two implements lines + the two projected schema types
  const src = substPcoNs(code, 4).replace('(module royalty-sale GOV', `(module ${MOD} GOV`);

  const gov = persona('gov');
  const creator = persona('creator');   // mints + is the primary seller
  const mkt = persona('mkt');            // marketplace fee payee
  const buyer1 = persona('buyer1');
  const buyer2 = persona('buyer2');
  for (const kp of [gov, creator, mkt]) await fund(kp, 5.0);
  await fund(buyer1, 60.0);  // pays for a purchase
  await fund(buyer2, 60.0);

  // the standard interfaces must exist before a qualified implements can load
  await ensureStandardInterfaces(gov);

  await send({
    code: `(namespace "free") (define-keyset "${govKeyset}" (read-keyset "g"))`,
    label: `define ${govKeyset}`,
    signers: [{ kp: gov }],
    data: { g: { keys: [gov.publicKey], pred: 'keys-all' } },
  });
  await send({
    code: `${src}\n(create-table ${M}.tokens)(create-table ${M}.listings)`,
    label: `deploy ${M} + tables`,
    signers: [{ kp: gov }],
  });

  // mint: creator signs unscoped (satisfies MINT-AUTH + gas). k: principals.
  await send({
    code: `(${M}.mint "art-1" "${creator.account}" (read-keyset "c") "${creator.account}" (read-keyset "c") 500 false "ipfs://art-1")`,
    label: 'mint sale-only art-1 (5% royalty)',
    signers: [{ kp: creator }],
    data: { c: { keys: [creator.publicKey], pred: 'keys-all' } },
  });

  // list at 40 with a 2.5% marketplace fee to mkt
  await send({
    code: `(${M}.list-token-with-fee "art-1" 40.0 coin "${mkt.account}" (read-keyset "m") 250)`,
    label: 'list art-1 at 40 (2.5% fee)',
    signers: [{ kp: creator, caps: (wc) => [wc(`${M}.OWNER`, 'art-1'), wc('coin.GAS')] }],
    data: { m: { keys: [mkt.publicKey], pred: 'keys-all' } },
  });

  const escrow: string = await localCall(`(${M}.get-escrow-account)`);
  const cBefore = await coinBalance(creator.account);
  const mBefore = await coinBalance(mkt.account);

  // BUY #1 — FRESH escrow. This is the F1-critical path on-node: fund escrow,
  // then read its balance in a plain let, settle, assert escrow returns to 0.
  await send({
    code: `(${M}.buy "art-1" "${buyer1.account}" (read-keyset "b"))`,
    label: 'buy art-1 over a FRESH escrow (F1 first-sale, on-node)',
    signers: [{ kp: buyer1, caps: (wc) => [wc('coin.TRANSFER', buyer1.account, escrow, { decimal: '40.0' }), wc('coin.GAS')] }],
    data: { b: { keys: [buyer1.publicKey], pred: 'keys-all' } },
  });

  const cAfter = await coinBalance(creator.account);
  const mAfter = await coinBalance(mkt.account);
  const esc1 = await coinBalance(escrow);
  // royalty 2.0 to creator; but creator IS the seller (primary sale) -> merged:
  // creator gets royalty(2) + proceeds(37) = 39; mkt gets fee(1). Total 40.
  if (!near(cAfter - cBefore, 39.0)) throw new Error(`creator payout wrong: ${cAfter - cBefore} (want 39)`);
  if (!near(mAfter - mBefore, 1.0)) throw new Error(`marketplace fee wrong: ${mAfter - mBefore} (want 1)`);
  if (!near(esc1, 0.0)) throw new Error(`escrow not settled to 0: ${esc1}`);
  if (await localCall(`(${M}.owner-of "art-1")`) !== buyer1.account) throw new Error('ownership did not flip');
  console.log(`  ✓ fresh-escrow sale settled on-node: creator +39, mkt +1, escrow -> 0, owner -> buyer1`);

  // DUST DONATION — griefer sends dust to the shared escrow.
  await send({
    code: `(coin.transfer-create "${gov.account}" "${escrow}" (${M}.create-escrow-guard) 0.000000000001)`,
    label: 'griefer donates dust to the escrow',
    signers: [{ kp: gov, caps: (wc) => [wc('coin.TRANSFER', gov.account, escrow, { decimal: '0.000000000001' }), wc('coin.GAS')] }],
  });
  const escDust = await coinBalance(escrow);
  if (!near(escDust, 1e-12)) throw new Error(`escrow should carry dust: ${escDust}`);

  // buyer1 (now owner) lists, buyer2 buys — over the DUST-carrying escrow.
  await send({
    code: `(${M}.list-token-with-fee "art-1" 20.0 coin "" (read-keyset "b1") 0)`,
    label: 'buyer1 re-lists art-1 at 20 (no fee)',
    signers: [{ kp: buyer1, caps: (wc) => [wc(`${M}.OWNER`, 'art-1'), wc('coin.GAS')] }],
    data: { b1: { keys: [buyer1.publicKey], pred: 'keys-all' } },
  });
  await send({
    code: `(${M}.buy "art-1" "${buyer2.account}" (read-keyset "b2"))`,
    label: 'buy art-1 over a DUST-carrying escrow (F1 donation case, on-node)',
    signers: [{ kp: buyer2, caps: (wc) => [wc('coin.TRANSFER', buyer2.account, escrow, { decimal: '20.0' }), wc('coin.GAS')] }],
    data: { b2: { keys: [buyer2.publicKey], pred: 'keys-all' } },
  });
  const escFinal = await coinBalance(escrow);
  // conservation: escrow returns to its baseline (the donated dust), not zero
  if (!near(escFinal, 1e-12)) throw new Error(`escrow should return to dust baseline: ${escFinal}`);
  if (await localCall(`(${M}.owner-of "art-1")`) !== buyer2.account) throw new Error('second sale ownership did not flip');
  console.log(`  ✓ dust-carrying-escrow sale settled on-node: escrow -> baseline (dust), owner -> buyer2`);

  saveResults(SLUG, { module: M, hash: await localCall(`(at 'hash (describe-module "${M}"))`) });
};

main().catch((e) => { console.error(`\nFAILED: ${e.message ?? e}`); process.exit(1); });
