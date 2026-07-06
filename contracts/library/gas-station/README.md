# Gas Station (allowlist-based)

PCO library template: an autonomous coin account that pays gas on behalf of users, enabling **gasless UX**. Implements `gas-payer-v1`. A gas station holds spendable KDA, so the whole design problem is **drain defense** — this template solves it with an **on-chain, sponsor-controlled allowlist** plus strict per-transaction bounds.

## Why not "allowlist the called module"?

A common gas-station pattern inspects the transaction's `exec-code` / `tx-type` via `read-msg` and funds only calls to a specific module. **That is not a sound defense**, for two reasons:

1. `read-msg` returns the transaction's mutable `data` payload, which is **not bound** to the code the transaction actually executes. A benign-looking `data` can accompany arbitrary code.
2. Even if it were bound, a single code string can carry **multiple top-level forms** — `"(good.call) (coin.transfer station attacker 9999.0)"` passes a "single element, prefix matches" check and drains the station.

So this template does **not** allowlist by inspecting tx code. It authorizes funding from state the sponsor controls on-chain.

## What it actually guarantees

The station funds a transaction's gas only if **all** hold:

1. **The user is enrolled** — the sponsor has called `enroll-user` (governance-gated) with the user's account name **and a guard**.
2. **The signer controls the user's guard** — `GAS_PAYER` calls `enforce-guard` on the stored guard, so merely *naming* an enrolled user is not enough (authentication).
3. **The user is enabled** — not disabled via `disable-user`.
4. **The ACTUAL gas is within bounds** — the station reads `(chain-data)` `gas-price`/`gas-limit` (the amounts coin actually debits) and enforces `≤ MAX_GAS_PRICE` / `≤ MAX_GAS_LIMIT`. **It does not trust the `GAS_PAYER` price/limit arguments for the money math** — those are signer-supplied and unbound to the real gas.
5. **Within the user's cumulative cap** — each funding adds `actual-limit × actual-price` to the user's `spent`; a funding that would push `spent` past the user's `cap` is rejected.

> **Why actual gas, not the cap arguments?** The `limit`/`price` passed to `GAS_PAYER` are chosen by the transaction signer and are not bound to the transaction's real gas. Bounding/accounting against them lets an attacker pass tiny decoy values while setting a huge real gas limit — draining the station past every bound. This template reads `chain-data` instead, mirroring the production `runonflux.flux-gas-station` (`enforce-below-or-at-gas-*`).

What an enrolled user *does* with the funded gas is up to them — the station does not (and cannot soundly) constrain which module they call. If you need module-level constraints, enforce them in your dApp. **Enrollment (a named account + its guard) is your trust boundary.**

## Security model

The station account is a **principal backed by a capability guard**. Its guard predicate is satisfied by **either**:
- the gas-payment path — `coin.GAS` (granted only by coin's gas machinery) **and** `ALLOW_GAS` (composed only inside `GAS_PAYER`, after all checks pass); or
- **governance** — the `gas-station-gov` keyset, used by `withdraw` to recover residual funds.

`ALLOW_GAS` is a weak-body internal cap that is not acquirable from outside the module, so gas can be released only through a policy-approved `GAS_PAYER`. There is no `read-msg` in the executable path.

## Deployment checklist

1. Wrap the module in your namespace; replace the `"gas-station-gov"` keyset with your deployed, namespace-qualified governance keyset (**multi-sig recommended**).
2. Tune `MAX_GAS_PRICE`, `MAX_GAS_LIMIT`, and `DEFAULT_USER_CAP` to your traffic. Keep the limit well under the 150,000 gas per-transaction ceiling.
3. Deploy, then call `(init)` **once** to create the station coin account (a second call aborts).
4. **Fund** `GAS_STATION` with KDA (`get-station-account` returns its name); top it up as it is spent down.
5. **Enroll users**: `(enroll-user "k:..." guard cap)` or `(enroll-user-default "k:..." guard)` — the guard authenticates the user at funding time. Disable with `(disable-user ...)`, reset a spend period with `(reset-user-spent ...)`. All emit events (`ENROLL`/`DISABLE`/`RESET`).
6. Validate the end-to-end gas flow on **devnet** before mainnet.

## Client usage

The user's transaction sets the station as gas payer and signs a capability scoped to `GAS_PAYER`:

- **Gas payer / sender**: the station account (`get-station-account`).
- **Signed capability**: `(<your-ns>.gas-station.GAS_PAYER user limit price)`, signed with the **key that satisfies the user's enrolled guard** (authentication).

If the user is not enrolled/enabled, the signer does not control the user's guard, or the **actual** gas exceeds the bounds/cap, the transaction is not funded.

## Withdrawing residual funds

`withdraw` recovers unspent KDA to a treasury account. The caller signs with the `gas-station-gov` key, scoping `(coin.TRANSFER GAS_STATION receiver amount)` — that signature both installs the managed transfer and satisfies the station guard's governance branch.

## Testing

`examples/gas-station-test.repl` is self-contained (loads `coin` + interfaces from `registry/`):

```bash
cd contracts/library/gas-station/examples && pact gas-station-test.repl
```

30 assertions. Every funding test sets the **real gas context** via `env-chain-data` and passes deliberately misleading `GAS_PAYER` arguments, proving the policy bounds/accounts against actual gas — including the **F1 drain regression** (tiny decoy cap args + huge actual gas → rejected) and the **F2 authentication regression** (naming an enrolled user without its guard → rejected). Also: governance-gated init/enrollment, approved funding, non-enrolled/disabled rejection, non-positive args, cumulative-cap exceeded, event emission, the guard predicate, and governance withdrawal (with non-governance withdrawal rejected). CI runs this suite as a blocking check.

## Known limits

- **Devnet-validate before mainnet.** The REPL exercises the `GAS_PAYER` policy and guard directly; coin's `buy-gas`/`redeem-gas` wrapping around a real transaction should be confirmed on devnet.
- The station does not constrain which module an enrolled user calls (see "Why not…" above). Enrollment is your trust boundary — enroll only accounts you intend to sponsor.
- `spent` is monotonic until `reset-user-spent`; design your cap/reset cadence (e.g. per-epoch) to match your budget.
- Governance holds absolute power (upgrade, enroll, withdraw). Use multi-sig.

## License

Apache-2.0
