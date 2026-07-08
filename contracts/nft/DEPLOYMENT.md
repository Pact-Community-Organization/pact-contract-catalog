# Deploying the NFT framework

How to put the framework on a Chainweb network (devnet, testnet, or a KDA-CE
network). The executable source of truth for the sequence is
`scripts/devnet-validate/src/nft-framework.ts` — the deploy tail there (module
source + `create-table` list per module) is exactly what a real train submits.
This page explains the order, the namespace decision, and the one rule that
cannot be walked back.

## The one-shot rule

Module names are fixed by cross-references (`policy-manager` names `ledger`,
policies name `policy-manager`, auctions name both). **A namespace gets ONE
shot at a clean deploy**: if a train aborts half-way and leaves wrong state, a
redo needs either the module upgrade path or a NEW namespace — the names in the
old one are taken forever. Interfaces are stricter still: a deployed interface
is frozen (`CannotUpgradeInterface`); any change after deployment is a new
interface name, not an edit. Validate the full train on a devnet first, always.

## Namespace choice

- **Principal namespace (recommended).** Create it with
  `ns.create-principal-namespace` from an operator keyset; the name
  (`n_<hash>`) is derived from the keyset, so it cannot be squatted and cannot
  collide. Confirm the target network exposes `ns.create-principal-namespace`
  with a read-only `/local` call before planning around it (some devnet images
  ship without it).
- **`free` (validation only).** Open user guard, zero setup — but names are
  first-come and burned on failure (see the one-shot rule). Fine for a
  throwaway validation pass, not for anything that must stay deployed.

## Order, per chain

1. **Admin keyset** — `(namespace "<ns>") (define-keyset "<ns>.<admin>" ...)`.
   This keyset is the framework governance gate; on a real network it should be
   hardware-backed.
2. **Interfaces** — `interfaces/` in one transaction: `account-protocols`,
   `token-policy`, `poly-fungible`, `ledger-iface`, `sale`. Frozen at deploy.
3. **`core/util`**
4. **`core/policy-manager`** + its tables (`ledgers`, `quotes`, `sale-contracts`)
5. **`core/ledger`** + its tables (`ledger-table`, `tokens`)
6. **Policies** (each + its tables): `royalty-policy`, `non-fungible-policy`,
   and whichever of `collection-policy` / `guard-policy` / `guarded-uri-policy`
   / `non-updatable-uri-policy` the deployment needs. Policies are independent;
   deploy only what will be used — more can be added later.
7. **Sale contracts** (each + its table): `conventional-auction`,
   `dutch-auction`.
8. **Governance wiring** (admin-signed):
   `(<ns>.policy-manager.init <ns>.ledger)` then
   `(<ns>.policy-manager.register-sale-contract <ns>.conventional-auction)` and
   the same for `dutch-auction`. Nothing sells through an unregistered sale
   contract — this registration is the marketplace trust boundary.

## Verification

- Existence + integrity: `(describe-module "<ns>.<module>")` per chain — the
  hash, not an explorer page, is the proof. Record the per-chain hash table.
- Behavior: the `test/` suites (and `test/redteam/`) are the acceptance bar;
  run them against the sources you deployed, byte-identical.
- Cross-chain flows require a multi-chain network (two chains suffice; SPV is
  not testable in the bare REPL).
- Gas headroom: the heaviest measured operational leg is ~1.5k gas against the
  150k KDA-CE ceiling; full-module deploys are the largest transactions and
  still clear the ceiling comfortably.

## Upgrades

Every upgrade must `bless` the previous module hash — in-flight sales and
cross-chain steps carry provenance from the old hash and complete against the
blessed one. Never remove a bless while any transaction started under that
hash can still resume.
