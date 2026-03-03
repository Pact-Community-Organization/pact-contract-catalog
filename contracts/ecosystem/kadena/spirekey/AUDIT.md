# AUDIT — kadena.spirekey

## Summary

| Field | Value |
|---|---|
| **Module** | `kadena.spirekey` |
| **Deployed Hash** | `wZIoPnkgwaXYenTfUTYP…` |
| **Audit Status** | Community Reviewed |
| **Publisher** | Kadena Inc. |

## Security Observations

### WebAuthn credential security
- Account guard is a WebAuthn public key — biometric-bound, never leaves the device.
- Credential rotation is protected by the `ROTATE` capability, guarded by the current credential.
- No seed phrase: recovery depends on device backup / passkey sync (e.g., iCloud Keychain).

### Gas payer safety
- `GAS_PAYER` capability enforces a gas limit via the `@managed` amount guard in `gas-payer-v1`.
- dApps using SpireKey as gas payer should set a reasonable `gasLimit` to prevent drain.

### Trust model
- Module code is deployed by Kadena Inc. with a known governance keyset.
- Source is open on GitHub; community has reviewed the implementation.

## Compliance with PCO Standards

| Check | Status |
|---|---|
| `gas-payer-v1` fully implemented | ✅ |
| `@managed` on GAS_PAYER amount | ✅ |
| No `(enforce true ...)` | ✅ |
| Open source | ✅ |

## Risk Rating

**LOW** — Official Kadena module with open source and standard interface compliance.
