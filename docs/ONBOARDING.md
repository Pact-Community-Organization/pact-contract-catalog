# Onboarding a New Contract

This guide outlines the process for onboarding a new Pact smart contract to the Pact Contract Catalog.

## Prerequisites

- Your contract must be written in Pact and follow best practices.
- Include comprehensive tests.
- Ensure the contract is secure and well-documented.
- Comply with the PCO Code of Conduct and governance policies.

## Steps

1. **Fork the Repository**: Fork the pact-contract-catalog repository.

2. **Create Contract Structure**:
   - Deployable templates go to `contracts/library/<contract-name>/`; observed on-chain modules go to `contracts/registry/ecosystem/` or `contracts/registry/community/` with deployment evidence (see [ARCHITECTURE.md](../ARCHITECTURE.md) and [ADR-001](adr/ADR-001-registry-library-split.md))
   - Create metadata at `<contract-dir>/metadata.yaml` (co-located YAML, not JSON)
   - Add a `README.md` and `AUDIT.md` in the same directory
   - Library entries: add tests to `<contract-dir>/examples/` using the `.repl` extension (mandatory)

3. **Validate Locally**:
   - Run Pact compiler to check syntax.
   - Execute tests using a Pact REPL environment (see README.md for setup).

4. **Submit Pull Request**:
   - Create a PR with a clear description.
   - Reference any related issues or RFCs.

5. **Automated Checks**:
   - CI will run syntax checks and basic validations.

6. **Review Process**:
   - Core maintainers will review for code quality.
   - Security WG may perform security audit.
   - Council approval for high-impact contracts.

7. **Audit (if required)**:
   - External audit may be requested for complex contracts.

8. **Merge and Publish**:
   - Once approved, the contract is merged and added to the catalog.

## Policies

- All contracts must be licensed under Apache-2.0 or compatible.
- Contracts must include proper documentation.
- No malicious or vulnerable code.
- Regular maintenance required.

See [CONTRACT_POLICIES.md](CONTRACT_POLICIES.md) for details.