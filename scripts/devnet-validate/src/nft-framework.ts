// nft framework — Phase 5 devnet campaign: the marketplace-hop scenario on
// REAL chains with a REAL SPV continuation.
//
//   alice CREATES an NFT on chain 0 (10% royalty, strict 1/1)
//     -> lists on MARKETPLACE A (fee identity "the gallery", 2.5%, price 100)
//     -> bob BUYS it (defpact continuation)
//     -> bob RELOCATES it to chain 1 (transfer-crosschain + SPV proof)
//     -> bob auctions it on MARKETPLACE B ("the bazaar", 5% fee,
//        conventional-auction) -> carol WINS at 200 (third-party settle)
//
// This is the evidence tier the REPL cannot produce: SPV verification, the
// FIRST-ARRIVAL materialization of the token row on a chain that has never
// seen it, node-mode table-read semantics, and real gas per entry point.
//
// The framework deploys under `free` (its namespace is a deploy-time
// parameter). One-shot per devnet: module names are fixed by cross-module
// references, so a re-run needs a devnet reset.
import {
  CHAIN, SENDER00, type Keypair, persona, fund, send, localCall,
  coinBalance, chainTime, saveResults, recordSteps, client, Pact, NETWORK_ID,
  GAS_PRICE, signerFor,
} from './lib.js';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ChainId, IUnsignedCommand } from '@kadena/client';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const NFT = join(ROOT, 'contracts', 'nft');
const CH0: ChainId = '0';
const CH1: ChainId = '1';
const NS = 'free';
const RUN = Date.now().toString(36);
const ADMIN_KS = `free.nftfw-admin-${RUN}`;

const COIN_REF = { refName: { name: 'coin', namespace: null }, refSpec: [{ name: 'fungible-v2', namespace: null }] };

const src = (rel: string) => readFileSync(join(NFT, rel), 'utf8');
const ks = (kp: Keypair) => ({ keys: [kp.publicKey], pred: 'keys-all' });

async function deployStack(chainId: ChainId, gov: Keypair): Promise<void> {
  console.log(`\n== deploying the framework on chain ${chainId} ==`);
  const deployData = { ns: NS, 'admin-ks': ADMIN_KS, g: ks(gov) };
  // the framework admin keyset (namespaced, gov persona)
  await send({
    code: `(namespace "free")(define-keyset "${ADMIN_KS}" (read-keyset "g"))`,
    label: `ch${chainId}: define ${ADMIN_KS}`,
    signers: [{ kp: SENDER00 }, { kp: gov }],
    data: deployData, chainId,
  });
  const interfaces = [
    'interfaces/account-protocols.pact', 'interfaces/token-policy.pact',
    'interfaces/poly-fungible.pact', 'interfaces/ledger-iface.pact',
    'interfaces/sale.pact',
  ].map(src).join('\n');
  await send({
    code: interfaces, label: `ch${chainId}: deploy the six interfaces`,
    signers: [{ kp: SENDER00 }], data: deployData, chainId,
  });
  await send({
    code: src('core/util.pact'), label: `ch${chainId}: deploy util`,
    signers: [{ kp: SENDER00 }], data: deployData, chainId,
  });
  await send({
    code: src('core/policy-manager.pact')
      + '\n(create-table free.policy-manager.ledgers)'
      + '(create-table free.policy-manager.quotes)'
      + '(create-table free.policy-manager.sale-contracts)',
    label: `ch${chainId}: deploy policy-manager (+tables)`,
    signers: [{ kp: SENDER00 }], data: deployData, chainId,
  });
  await send({
    code: src('core/ledger.pact')
      + '\n(create-table free.ledger.ledger-table)(create-table free.ledger.tokens)',
    label: `ch${chainId}: deploy ledger (+tables)`,
    signers: [{ kp: SENDER00 }], data: deployData, chainId,
  });
  await send({
    code: src('policies/royalty-policy.pact') + '\n(create-table free.royalty-policy.royalties)',
    label: `ch${chainId}: deploy royalty-policy (+table)`,
    signers: [{ kp: SENDER00 }], data: deployData, chainId,
  });
  await send({
    code: src('policies/non-fungible-policy.pact') + '\n(create-table free.non-fungible-policy.minted-table)',
    label: `ch${chainId}: deploy non-fungible-policy (+table)`,
    signers: [{ kp: SENDER00 }], data: deployData, chainId,
  });
  await send({
    code: src('sale/conventional-auction.pact') + '\n(create-table free.conventional-auction.auctions)',
    label: `ch${chainId}: deploy conventional-auction (+table)`,
    signers: [{ kp: SENDER00 }], data: deployData, chainId,
  });
  // gov-gated wiring: register the ledger + the auction contract
  await send({
    code: `(free.policy-manager.init free.ledger)(free.policy-manager.register-sale-contract free.conventional-auction)`,
    label: `ch${chainId}: manager init + auction whitelist (gov)`,
    signers: [{ kp: SENDER00 }, { kp: gov }], data: deployData, chainId,
  });
}

// continuation tx (same-chain or cross-chain with proof)
async function continuePact(o: {
  pactId: string; chainId: ChainId; label: string; proof?: string;
  data?: Record<string, any>; signers: { kp: Keypair; caps?: any }[];
  gasLimit?: number;
}): Promise<any> {
  let b: any = Pact.builder.continuation({
    pactId: o.pactId, step: 1, rollback: false, proof: o.proof ?? null,
  });
  for (const s of o.signers) b = s.caps ? b.addSigner(s.kp.publicKey, s.caps) : b.addSigner(s.kp.publicKey);
  for (const [k, v] of Object.entries(o.data ?? {})) b = b.addData(k, v);
  const tx: IUnsignedCommand = b.setMeta({
    chainId: o.chainId, senderAccount: o.signers[0].kp.account,
    gasLimit: o.gasLimit ?? 150000, gasPrice: GAS_PRICE,
  }).setNetworkId(NETWORK_ID).createTransaction();
  let signed: any = tx;
  for (const s of o.signers) signed = await signerFor(s.kp)(signed);
  const desc = await client.submit(signed);
  const r = await client.pollOne(desc, { timeout: 600_000, interval: 4_000 });
  if (r.result.status !== 'success') {
    throw new Error(`${o.label} FAILED: ${JSON.stringify((r.result as any).error)}`);
  }
  recordSteps().push({ label: o.label, requestKey: desc.requestKey, gas: (r as any).gas });
  console.log(`  ✓ ${o.label}  (gas ${(r as any).gas}, rk ${desc.requestKey.slice(0, 12)}…)`);
  return (r.result as any).data;
}

async function waitForChainTime(chainId: ChainId, target: number, label: string): Promise<void> {
  process.stdout.write(`  … waiting for chain ${chainId} time to pass ${target} (${label}) `);
  for (;;) {
    const t = Math.floor((await chainTime(chainId)).getTime() / 1000);
    if (t > target) { console.log(`reached (${t})`); return; }
    process.stdout.write('.');
    await new Promise((res) => setTimeout(res, 5_000));
  }
}

const near = (a: number, b: number, eps = 0.01) => Math.abs(a - b) <= eps;
function assertNear(label: string, actual: number, expected: number): void {
  if (!near(actual, expected)) throw new Error(`${label}: expected ~${expected}, got ${actual}`);
  console.log(`  ✓ ${label} = ${actual}`);
}

async function main(): Promise<void> {
  console.log(`nft framework devnet campaign — run ${RUN} on ${NETWORK_ID}`);
  const gov = persona('gov'), alice = persona('alice'), bob = persona('bob'), carol = persona('carol');
  const gallery = persona('gallery'), bazaar = persona('bazaar');

  // funding (gas + purchase money). alice never touches chain 1 herself:
  // her royalty account there is CREATED by the settlement.
  process.env.DEVNET_CHAIN; // (chain passed per call)
  await fund(alice, 20);                        // ch0 gas
  await fund(bob, 150);                         // ch0: buy 100 + gas
  await send({                                  // ch1 funding
    code: `(coin.transfer-create "sender00" "${bob.account}" (read-keyset "g") 20.0)
           (coin.transfer-create "sender00" "${carol.account}" (read-keyset "h") 250.0)`,
    label: 'fund bob + carol on chain 1',
    signers: [{ kp: SENDER00, caps: (wc: any) => [
      wc('coin.TRANSFER', 'sender00', bob.account, { decimal: '20.0' }),
      wc('coin.TRANSFER', 'sender00', carol.account, { decimal: '250.0' }),
      wc('coin.GAS')] }],
    data: { g: ks(bob), h: ks(carol) }, chainId: CH1,
  });

  await deployStack(CH0, gov);
  await deployStack(CH1, gov);

  // =========================================================================
  // ACT 1 — chain 0: create + mint (10% royalty, strict 1/1)
  // =========================================================================
  console.log('\n== ACT 1: alice creates the painting on chain 0 ==');
  const tokenId: string = await (async () => {
    const r = await send({
      code: `(let ((id (free.ledger.create-token-id
                { 'uri: "ipfs://the-painting", 'precision: 0
                , 'policies: [free.non-fungible-policy free.royalty-policy] }
                (read-keyset 'alice_ks))))
        (free.ledger.create-token id 0 "ipfs://the-painting"
          [free.non-fungible-policy free.royalty-policy] (read-keyset 'alice_ks))
        (free.ledger.mint id "${alice.account}" (read-keyset 'alice_ks) 1.0)
        id)`,
      label: 'create + mint on chain 0',
      signers: [{ kp: alice }],
      data: {
        alice_ks: ks(alice),
        royalty_spec: { creator: alice.account, 'creator-guard': ks(alice), bps: { int: '1000' }, 'sale-only': false },
      },
      chainId: CH0,
    });
    return (r.result as any).data as string;
  })();
  console.log(`  token id: ${tokenId}`);

  // =========================================================================
  // ACT 2 — chain 0, marketplace A (the gallery): fixed price 100, fee 2.5%
  // =========================================================================
  console.log('\n== ACT 2: sold on marketplace A (the gallery) ==');
  const sale1 = await send({
    code: `(free.ledger.sale "${tokenId}" "${alice.account}" 1.0 0)`,
    label: 'offer at 100 through the gallery',
    signers: [{ kp: alice, caps: (wc: any) => [
      wc('free.ledger.OFFER', tokenId, alice.account, { decimal: '1.0' }, { int: '0' }),
      wc('coin.GAS')] }],
    data: { quote: {
      fungible: COIN_REF, price: { decimal: '100.0' },
      'seller-account': alice.account, 'seller-guard': ks(alice),
      'fee-account': gallery.account, 'fee-guard': ks(gallery),
      'fee-bps': { int: '250' }, 'sale-contract': '' } },
    chainId: CH0,
  });
  const saleId1 = (sale1 as any).reqKey ?? (sale1 as any).metaData?.requestKey ?? recordSteps().at(-1)!.requestKey;
  const escrow1: string = await localCall(`(free.policy-manager.escrow-account "${saleId1}")`, CH0);
  const aliceBefore = await coinBalance(alice.account, CH0);
  const galleryBefore = await coinBalance(gallery.account, CH0);

  await continuePact({
    pactId: saleId1, chainId: CH0, label: 'bob buys on the gallery',
    data: { buyer: bob.account, 'buyer-guard': ks(bob), buyer_fungible_account: bob.account },
    signers: [{ kp: bob, caps: (wc: any) => [
      wc('free.ledger.BUY', tokenId, alice.account, bob.account, { decimal: '1.0' }, saleId1),
      wc('coin.TRANSFER', bob.account, escrow1, { decimal: '100.0' }),
      wc('coin.GAS')] }],
  });
  assertNear('bob owns the painting on chain 0',
    await localCall(`(free.ledger.get-balance "${tokenId}" "${bob.account}")`, CH0), 1.0);
  assertNear('alice netted 97.5 (royalty 10 + proceeds 87.5, merged)',
    (await coinBalance(alice.account, CH0)) - aliceBefore, 97.5);
  assertNear('the gallery earned its 2.5% fee',
    (await coinBalance(gallery.account, CH0)) - galleryBefore, 2.5);
  assertNear('sale-1 escrow empty (conservation)', await coinBalance(escrow1, CH0), 0);

  // =========================================================================
  // ACT 3 — the chain hop: transfer-crosschain + REAL SPV proof
  // =========================================================================
  console.log('\n== ACT 3: bob relocates the painting to chain 1 (SPV) ==');
  await send({
    code: `(free.ledger.transfer-crosschain "${tokenId}" "${bob.account}" "${bob.account}" (read-keyset 'rg) "1" 1.0)`,
    label: 'x-chain step 0 on chain 0 (passports yielded)',
    signers: [{ kp: bob, caps: (wc: any) => [
      wc('free.ledger.XTRANSFER', tokenId, bob.account, bob.account, '1', { decimal: '1.0' }),
      wc('coin.GAS')] }],
    data: { rg: ks(bob) }, chainId: CH0,
  });
  const hopRk = recordSteps().at(-1)!.requestKey;
  assertNear('the painting left chain 0 (supply 0)',
    await localCall(`(free.ledger.total-supply "${tokenId}")`, CH0), 0);

  console.log('  … requesting the SPV proof (chain 0 -> 1)');
  const proof = await client.pollCreateSpv(
    { requestKey: hopRk, chainId: CH0, networkId: NETWORK_ID }, CH1,
    { timeout: 600_000, interval: 5_000 });
  console.log(`  ✓ SPV proof obtained (${proof.length} chars)`);

  await continuePact({
    pactId: hopRk, chainId: CH1, proof,
    label: 'x-chain step 1 on chain 1 (SPV-verified arrival)',
    signers: [{ kp: SENDER00 }],
  });
  assertNear('bob holds the painting on chain 1',
    await localCall(`(free.ledger.get-balance "${tokenId}" "${bob.account}")`, CH1), 1.0);
  assertNear('the royalty passport re-bound on chain 1 (bps)',
    await localCall(`(at 'bps (free.royalty-policy.get-royalty "${tokenId}"))`, CH1), 1000);
  const marker = await localCall(`(free.non-fungible-policy.is-minted "${tokenId}")`, CH1);
  if (marker !== true) throw new Error('1/1 marker did not travel');
  console.log('  ✓ the 1/1 once-ever marker traveled');

  // =========================================================================
  // ACT 4 — chain 1, marketplace B (the bazaar): ascending auction, fee 5%
  // =========================================================================
  console.log('\n== ACT 4: auctioned on marketplace B (the bazaar) ==');
  await send({
    code: `(free.ledger.sale "${tokenId}" "${bob.account}" 1.0 0)`,
    label: 'offer through the bazaar auction (price discovered)',
    signers: [{ kp: bob, caps: (wc: any) => [
      wc('free.ledger.OFFER', tokenId, bob.account, { decimal: '1.0' }, { int: '0' }),
      wc('coin.GAS')] }],
    data: { quote: {
      fungible: COIN_REF, price: { decimal: '0.0' },
      'seller-account': bob.account, 'seller-guard': ks(bob),
      'fee-account': bazaar.account, 'fee-guard': ks(bazaar),
      'fee-bps': { int: '500' }, 'sale-contract': 'free.conventional-auction' } },
    chainId: CH1,
  });
  const saleId2 = recordSteps().at(-1)!.requestKey;

  const now = Math.floor((await chainTime(CH1)).getTime() / 1000);
  const start = now + 30, end = start + 60, grace = 30;
  await send({
    code: `(free.conventional-auction.create-auction "${saleId2}" "${tokenId}" ${start} ${end} 50.0 10.0 ${grace})`,
    label: `create the auction (reserve 50, start +30s, end +90s)`,
    signers: [{ kp: bob }], chainId: CH1,
  });

  const bidEscrow: string = await localCall(`(free.conventional-auction.bid-escrow-account "${saleId2}")`, CH1);
  await waitForChainTime(CH1, start, 'auction start');
  await send({
    code: `(free.conventional-auction.place-bid "${saleId2}" "${carol.account}" (read-keyset 'cg) 200.0)`,
    label: 'carol bids 200',
    signers: [{ kp: carol, caps: (wc: any) => [
      wc('coin.TRANSFER', carol.account, bidEscrow, { decimal: '200.0' }),
      wc('free.conventional-auction.PLACE-BID', ks(carol)),
      wc('coin.GAS')] }],
    data: { cg: ks(carol) }, chainId: CH1,
  });
  assertNear('the bazaar escrowed the bid', await coinBalance(bidEscrow, CH1), 200);

  await waitForChainTime(CH1, end, 'auction end');
  const escrow2: string = await localCall(`(free.policy-manager.escrow-account "${saleId2}")`, CH1);
  const bobBefore1 = await coinBalance(bob.account, CH1);
  await continuePact({
    pactId: saleId2, chainId: CH1,
    label: 'the auction settles (third-party crank: sender00)',
    data: { buyer: carol.account, 'buyer-guard': ks(carol),
            buyer_fungible_account: bidEscrow, quoted_price: { decimal: '200.0' } },
    signers: [{ kp: SENDER00, caps: (wc: any) => [
      wc('free.ledger.BUY', tokenId, bob.account, carol.account, { decimal: '1.0' }, saleId2),
      wc('coin.TRANSFER', bidEscrow, escrow2, { decimal: '200.0' }),
      wc('coin.GAS')] }],
  });

  // =========================================================================
  // THE LEDGER OF THE WHOLE STORY
  // =========================================================================
  console.log('\n== final reconciliation ==');
  assertNear('carol holds the painting on chain 1',
    await localCall(`(free.ledger.get-balance "${tokenId}" "${carol.account}")`, CH1), 1.0);
  assertNear('supply on chain 1 is exactly 1',
    await localCall(`(free.ledger.total-supply "${tokenId}")`, CH1), 1.0);
  assertNear('ALICE was paid the 10% royalty ON CHAIN 1 (account created by settlement)',
    await coinBalance(alice.account, CH1), 20);
  assertNear('the bazaar earned its 5% fee', await coinBalance(bazaar.account, CH1), 10);
  assertNear('bob received the 170 proceeds', (await coinBalance(bob.account, CH1)) - bobBefore1, 170);
  assertNear('sale-2 settlement escrow empty', await coinBalance(escrow2, CH1), 0);
  assertNear('the bid escrow empty', await coinBalance(bidEscrow, CH1), 0);

  const maxGas = Math.max(...recordSteps().map((s) => s.gas));
  console.log(`\n  max gas across ${recordSteps().length} txs: ${maxGas} (ceiling 150000)`);
  saveResults('nft-framework', { tokenId, saleId1, saleId2, hopRk, maxGas });
}

main().catch((e) => { console.error(`\nCAMPAIGN FAILED: ${e.message ?? e}`); process.exit(1); });
