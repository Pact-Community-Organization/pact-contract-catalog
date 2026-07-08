// Devnet marketplace simulation: library/royalty-sale
//
// The REPL suite (examples/royalty-sale-market-sim.repl) proves the economics
// deterministically; THIS run proves the settlement's node-only behavior on a
// live KDA-CE node, where table reads in read-only contexts diverge from the
// REPL (the F1 class). Mined to confirmation:
//
//   - a 4-hop RESALE CHAIN (creator->A->B->C->D) on a sale-only 5% token
//     through two marketplaces at different fee rates - the creator's royalty
//     accrues on EVERY hop and each settlement conserves on-node;
//   - a full primary + secondary sale in a NON-coin fungible-v2 (the library
//     token-fungible template) - node evidence that the settlement path
//     (precision read, managed-TRANSFER install, escrow guard) is
//     currency-agnostic, which the F1 run (coin-only) did not cover;
//   - adversarial rejections ON-NODE: non-owner delist, front-run repricing
//     against a committed buyer cap, broke buyer, sale-only transfer;
//   - escrow dust-griefing: the next sale settles to the donated baseline;
//   - per-tx gas recorded against the 150k ceiling (GAS_LIMIT enforces it).
import {
  send, sendExpectFail, localCall, coinBalance, fund, persona, ksData,
  loadTemplate, saveResults, recordSteps,
  ensureStandardInterfaces, substPcoNs,
} from './lib.js';

const SLUG = 'royalty-sale-market-sim';
const near = (a: number, b: number, eps = 1e-11) => Math.abs(a - b) <= eps;
// balances of accounts that paid gas in KDA drift by gasUsed * 1e-8 (< 0.002)
const nearGas = (a: number, b: number) => a <= b + 1e-11 && b - a <= 0.01;
const assert = (cond: boolean, msg: string) => {
  if (!cond) throw new Error(`ASSERT FAILED: ${msg}`);
  console.log(`  ✓ ${msg}`);
};

async function pickName(base: string): Promise<string> {
  for (let i = 0; ; i++) {
    const name = i === 0 ? base : `${base}-v${i + 1}`;
    try { await localCall(`(describe-module "free.${name}")`); }
    catch { return name; }
  }
}

const main = async () => {
  console.log(`\n=== devnet marketplace simulation: ${SLUG} ===`);
  const MOD = await pickName('royalty-market');
  const TOK = await pickName('sim-tok');
  const M = `free.${MOD}`;
  const T = `free.${TOK}`;

  const rs = loadTemplate('royalty-sale', 'royalty-sale.pact', 'royalty-sale-gov', MOD);
  // 4 = the two implements lines + the two projected schema types
  const rsSrc = substPcoNs(rs.code, 4).replace('(module royalty-sale GOV', `(module ${MOD} GOV`);
  const tk = loadTemplate('token-fungible', 'token.pact', 'token-gov', TOK);
  const tkSrc = tk.code.replace('(module token GOV', `(module ${TOK} GOV`);

  // the cast — same roles as the REPL sim
  const gov = persona('gov');
  const alice = persona('alice');   // creator of chain-1
  const dana = persona('dana');     // creator of dna-tok (token-currency artist)
  const bob = persona('bob');       // collector A
  const carol = persona('carol');   // collector B
  const frank = persona('frank');   // collector C
  const gina = persona('gina');     // collector D
  const mkt1 = persona('mkt1');     // marketplace #1 (2.5%)
  const mkt2 = persona('mkt2');     // marketplace #2 (5%)
  const eve = persona('eve');       // adversary
  await fund(gov, 5.0); await fund(alice, 5.0); await fund(dana, 5.0);
  await fund(bob, 120.0); await fund(carol, 210.0); await fund(frank, 120.0);
  await fund(gina, 300.0); await fund(mkt1, 2.0); await fund(mkt2, 2.0);
  await fund(eve, 3.0);

  // the standard interfaces must exist before a qualified implements can load
  await ensureStandardInterfaces(gov);

  // ---- deploy both templates under free/ ----------------------------------
  await send({
    code: `(namespace "free") (define-keyset "${rs.govKeyset}" (read-keyset "g")) (define-keyset "${tk.govKeyset}" (read-keyset "g"))`,
    label: 'define governance keysets',
    signers: [{ kp: gov }],
    data: ksData('g', gov),
  });
  await send({
    code: `${rsSrc}\n(create-table ${M}.tokens)(create-table ${M}.listings)`,
    label: `deploy ${M} + tables`,
    signers: [{ kp: gov }],
  });
  await send({
    code: `${tkSrc}\n(create-table ${T}.token-table)`,
    label: `deploy ${T} (currency #2) + table`,
    signers: [{ kp: gov }],
  });
  const escrow: string = await localCall(`(${M}.get-escrow-account)`);
  console.log(`  escrow: ${escrow}`);

  // ---- catalog -------------------------------------------------------------
  await send({
    code: `(${M}.mint "chain-1" "${alice.account}" (read-keyset "a") "${alice.account}" (read-keyset "a") 500 false "ipfs://chain-1")`,
    label: 'alice mints chain-1 (5% royalty, SALE-ONLY)',
    signers: [{ kp: alice }],
    data: ksData('a', alice),
  });
  await send({
    code: `(${M}.mint "dna-tok" "${dana.account}" (read-keyset "d") "${dana.account}" (read-keyset "d") 250 true "ipfs://dna-tok")`,
    label: 'dana mints dna-tok (2.5% royalty)',
    signers: [{ kp: dana }],
    data: ksData('d', dana),
  });

  // =====================================================================
  // THE RESALE CHAIN (coin): alice -> bob -> carol -> frank -> gina
  //   hop1 100.0 mkt1 2.5% | hop2 160.0 mkt2 5% | hop3 80.0 mkt1 2.5% | hop4 250.0 no fee
  //   creator royalty 5% on EVERY hop: 5 + 8 + 4 + 12.5 = 29.5 = 5% x 590
  // =====================================================================
  type Hop = { seller: typeof alice; buyer: typeof alice; price: number; mkt?: typeof alice; mktName?: string; bps: number; };
  const hops: Hop[] = [
    { seller: alice, buyer: bob, price: 100.0, mkt: mkt1, mktName: 'mkt1', bps: 250 },
    { seller: bob, buyer: carol, price: 160.0, mkt: mkt2, mktName: 'mkt2', bps: 500 },
    { seller: carol, buyer: frank, price: 80.0, mkt: mkt1, mktName: 'mkt1', bps: 250 },
    { seller: frank, buyer: gina, price: 250.0, bps: 0 },
  ];
  const aliceStart = await coinBalance(alice.account);
  let royaltyAccrued = 0;
  let volume = 0;
  for (const [i, h] of hops.entries()) {
    const n = i + 1;
    const listCode = h.mkt
      ? `(${M}.list-token-with-fee "chain-1" ${h.price.toFixed(1)} coin "${h.mkt.account}" (read-keyset "m") ${h.bps})`
      : `(${M}.list-token-with-fee "chain-1" ${h.price.toFixed(1)} coin "" (read-keyset "m") 0)`;
    await send({
      code: listCode,
      label: `hop ${n}: list chain-1 at ${h.price} (${h.mkt ? `${h.mktName} ${h.bps} bps` : 'no fee'})`,
      signers: [{ kp: h.seller, caps: (wc) => [wc(`${M}.OWNER`, 'chain-1'), wc('coin.GAS')] }],
      data: ksData('m', h.mkt ?? h.seller),
    });
    const royalty = (h.price * 500) / 10000;
    const fee = (h.price * h.bps) / 10000;
    const proceeds = h.price - royalty - fee;
    const sBefore = await coinBalance(h.seller.account);
    const aBefore = await coinBalance(alice.account);
    const mBefore = h.mkt ? await coinBalance(h.mkt.account) : 0;
    await send({
      code: `(${M}.buy "chain-1" "${h.buyer.account}" (read-keyset "b"))`,
      label: `hop ${n}: ${h.seller.account.slice(0, 10)}… sells to ${h.buyer.account.slice(0, 10)}… for ${h.price}`,
      signers: [{ kp: h.buyer, caps: (wc) => [wc('coin.TRANSFER', h.buyer.account, escrow, { decimal: h.price.toFixed(1) }), wc('coin.GAS')] }],
      data: ksData('b', h.buyer),
    });
    royaltyAccrued += royalty;
    volume += h.price;
    const esc = await coinBalance(escrow);
    assert(near(esc, 0), `hop ${n}: escrow settled to 0 on-node`);
    if (i === 0) {
      // primary hop: creator == seller — royalty + proceeds arrive MERGED
      assert(near(await coinBalance(alice.account) - aBefore, royalty + proceeds),
        `hop 1: creator==seller merged payout ${royalty + proceeds}`);
    } else {
      assert(near(await coinBalance(alice.account) - aBefore, royalty),
        `hop ${n}: creator royalty ${royalty} reached alice (seller was someone else)`);
      assert(near(await coinBalance(h.seller.account) - sBefore, proceeds),
        `hop ${n}: seller netted price - royalty - fee = ${proceeds}`);
    }
    if (h.mkt) {
      assert(near(await coinBalance(h.mkt.account) - mBefore, fee),
        `hop ${n}: ${h.mktName} fee ${fee} accrued`);
    }
    const owner = await localCall(`(${M}.owner-of "chain-1")`);
    assert(owner === h.buyer.account, `hop ${n}: ownership flipped to the buyer`);
  }
  assert(near(royaltyAccrued, 29.5) && near(volume * 0.05, royaltyAccrued),
    `RESALE CHAIN: creator royalty 29.5 == 5% x ${volume} volume, on-node`);
  assert(nearGas(await coinBalance(alice.account), aliceStart + 122.0),
    `alice's cumulative take from the chain is 122.0 (97.5 primary + 24.5 royalties), minus gas`);

  // =====================================================================
  // MULTI-CURRENCY: primary + secondary sale in the NON-coin fungible
  // (token balances have NO gas noise — assertions are exact to 12 dp)
  // =====================================================================
  await send({
    code: `(${T}.mint "${carol.account}" (read-keyset "c") 1000.0)(${T}.mint "${frank.account}" (read-keyset "f") 300.0)`,
    label: `governance mints 1300 ${TOK} to carol + frank`,
    signers: [{ kp: gov }],
    data: { ...ksData('c', carol), ...ksData('f', frank) },
  });
  await send({
    code: `(${M}.list-token-with-fee "dna-tok" 500.0 ${T} "${mkt2.account}" (read-keyset "m") 500)`,
    label: `dana lists dna-tok at 500.0 ${TOK} (mkt2 5%)`,
    signers: [{ kp: dana, caps: (wc) => [wc(`${M}.OWNER`, 'dna-tok'), wc('coin.GAS')] }],
    data: ksData('m', mkt2),
  });
  await send({
    code: `(${M}.buy "dna-tok" "${carol.account}" (read-keyset "b"))`,
    label: `carol buys dna-tok with ${TOK} (NON-coin settlement, on-node)`,
    signers: [{ kp: carol, caps: (wc) => [wc(`${T}.TRANSFER`, carol.account, escrow, { decimal: '500.0' }), wc('coin.GAS')] }],
    data: ksData('b', carol),
  });
  const tokBal = (acct: string) => localCall(`(${T}.get-balance "${acct}")`).then(Number).catch(() => 0);
  assert(near(await tokBal(dana.account), 475.0), `dana (creator==seller) merged 475.0 ${TOK}`);
  assert(near(await tokBal(mkt2.account), 25.0), `mkt2 fee 25.0 ${TOK}`);
  assert(near(await tokBal(carol.account), 500.0), `carol paid exactly 500.0 ${TOK}`);
  assert(near(await tokBal(escrow), 0.0), `token-side escrow settled to 0 on-node`);

  await send({
    code: `(${M}.list-token-with-fee "dna-tok" 200.0 ${T} "" (read-keyset "m") 0)`,
    label: `carol re-lists dna-tok at 200.0 ${TOK} (no fee)`,
    signers: [{ kp: carol, caps: (wc) => [wc(`${M}.OWNER`, 'dna-tok'), wc('coin.GAS')] }],
    data: ksData('m', carol),
  });
  await send({
    code: `(${M}.buy "dna-tok" "${frank.account}" (read-keyset "b"))`,
    label: `frank buys dna-tok — dana's royalty accrues in ${TOK}`,
    signers: [{ kp: frank, caps: (wc) => [wc(`${T}.TRANSFER`, frank.account, escrow, { decimal: '200.0' }), wc('coin.GAS')] }],
    data: ksData('b', frank),
  });
  assert(near(await tokBal(dana.account), 480.0), `dana's secondary royalty landed: 480.0 ${TOK}`);
  assert(near(await tokBal(carol.account), 695.0), `carol netted 195.0 ${TOK}`);
  assert(near(await tokBal(frank.account), 100.0), `frank paid exactly 200.0 ${TOK}`);
  assert(near(await tokBal(escrow), 0.0), `token-side escrow -> 0 again`);
  const tokSum = (await tokBal(dana.account)) + (await tokBal(carol.account))
    + (await tokBal(frank.account)) + (await tokBal(mkt2.account)) + (await tokBal(escrow));
  assert(near(tokSum, 1300.0), `GLOBAL ${TOK} CONSERVATION: all balances sum to the 1300 minted`);

  // =====================================================================
  // ADVERSARIAL, ON-NODE (each rejection mined against the live node)
  // =====================================================================
  // gina (current owner) lists chain-1 at 30 — a buyer will commit to this
  await send({
    code: `(${M}.list-token-with-fee "chain-1" 30.0 coin "" (read-keyset "m") 0)`,
    label: 'gina lists chain-1 at 30.0',
    signers: [{ kp: gina, caps: (wc) => [wc(`${M}.OWNER`, 'chain-1'), wc('coin.GAS')] }],
    data: ksData('m', gina),
  });
  await sendExpectFail({
    code: `(${M}.delist "chain-1")`,
    label: 'eve (non-owner) tries to delist the live listing',
    signers: [{ kp: eve, caps: (wc) => [wc(`${M}.OWNER`, 'chain-1'), wc('coin.GAS')] }],
  }, 'Keyset failure');
  await sendExpectFail({
    code: `(${M}.transfer "chain-1" "${eve.account}" (read-keyset "e"))`,
    label: 'sale-only token cannot be free-transferred (no non-paying exit)',
    signers: [{ kp: gina, caps: (wc) => [wc(`${M}.OWNER`, 'chain-1'), wc('coin.GAS')] }],
    data: ksData('e', eve),
  }, 'sale-only');
  // FRONT-RUN: gina reprices to 40 AFTER carol signed a 30-cap
  await send({
    code: `(${M}.list-token-with-fee "chain-1" 40.0 coin "" (read-keyset "m") 0)`,
    label: 'FRONT-RUN: gina reprices the live listing to 40.0',
    signers: [{ kp: gina, caps: (wc) => [wc(`${M}.OWNER`, 'chain-1'), wc('coin.GAS')] }],
    data: ksData('m', gina),
  });
  await sendExpectFail({
    code: `(${M}.buy "chain-1" "${carol.account}" (read-keyset "b"))`,
    label: 'carol\'s stale 30-cap buy aborts — she cannot be made to overpay',
    signers: [{ kp: carol, caps: (wc) => [wc('coin.TRANSFER', carol.account, escrow, { decimal: '30.0' }), wc('coin.GAS')] }],
    data: ksData('b', carol),
  }, 'TRANSFER exceeded');
  await sendExpectFail({
    code: `(${M}.buy "chain-1" "${eve.account}" (read-keyset "b"))`,
    label: 'broke buyer (eve, 3 KDA) cannot settle the 40.0 listing',
    signers: [{ kp: eve, caps: (wc) => [wc('coin.TRANSFER', eve.account, escrow, { decimal: '40.0' }), wc('coin.GAS')] }],
    data: ksData('b', eve),
  }, 'Insufficient funds');

  // DUST GRIEFING + final settle over the dust baseline (F1 regression)
  await send({
    code: `(coin.transfer-create "${eve.account}" "${escrow}" (${M}.create-escrow-guard) 0.000000000001)`,
    label: 'eve donates dust to the shared escrow',
    signers: [{ kp: eve, caps: (wc) => [wc('coin.TRANSFER', eve.account, escrow, { decimal: '0.000000000001' }), wc('coin.GAS')] }],
  });
  const aliceBefore = await coinBalance(alice.account);
  const ginaBefore = await coinBalance(gina.account);
  await send({
    code: `(${M}.buy "chain-1" "${carol.account}" (read-keyset "b"))`,
    label: 'carol accepts the 40.0 price — sale settles OVER the dust',
    signers: [{ kp: carol, caps: (wc) => [wc('coin.TRANSFER', carol.account, escrow, { decimal: '40.0' }), wc('coin.GAS')] }],
    data: ksData('b', carol),
  });
  assert(near(await coinBalance(escrow), 1e-12), 'escrow returned to the DUST baseline (not zero) — conservation held on-node');
  assert(near(await coinBalance(alice.account) - aliceBefore, 2.0), 'creator royalty 2.0 on the 5th chain-1 sale');
  assert(near(await coinBalance(gina.account) - ginaBefore, 38.0), 'gina netted 38.0');
  assert(await localCall(`(${M}.owner-of "chain-1")`) === carol.account, 'carol owns chain-1');

  // =====================================================================
  // GAS: every mined tx above ran under GAS_LIMIT 150000 or it would have
  // failed. Report the per-operation numbers.
  // =====================================================================
  const steps = recordSteps();
  const maxGas = Math.max(...steps.map((s) => s.gas));
  const buys = steps.filter((s) => /sells to|buys|settles OVER|carol buys/.test(s.label));
  console.log(`\n  gas: max ${maxGas} / 150000 ceiling; buy txs: ${buys.map((s) => s.gas).join(', ')}`);
  assert(maxGas < 150000, `every operation cleared the 150k ceiling (max ${maxGas})`);

  saveResults(SLUG, {
    module: M,
    tokenModule: T,
    hash: await localCall(`(at 'hash (describe-module "${M}"))`),
    chain1: { sales: 5, volume: volume + 40.0, creatorRoyalty: royaltyAccrued + 2.0, ratePct: 5 },
    dnaTok: { sales: 2, volume: 700.0, creatorRoyaltyToken: 17.5, ratePct: 2.5 },
    maxGas,
  });
};

main().catch((e) => { console.error(`\nFAILED: ${e.message ?? e}`); process.exit(1); });
