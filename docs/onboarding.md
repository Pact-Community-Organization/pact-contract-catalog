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
   - Add your contract file(s) to `contracts/<category>/<contract-name>/`
   - Create metadata in `contracts/<category>/<contract-name>/metadata/<contract-name>.json`
   - Add tests to `contracts/<category>/<contract-name>/` (co-located with the contract, using .repl extension)

3. **Validate Locally**:
   - Run Pact compiler to check syntax.
   - Execute tests to ensure functionality.

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

See [policies/contract-policies.md](policies/contract-policies.md) for details.