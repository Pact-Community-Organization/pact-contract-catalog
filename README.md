# Pact Contract Catalog

Welcome to the Pact Contract Catalog, the central repository for reusable, trusted Pact smart contracts in the Kadena ecosystem. This repository is maintained by the Pact Community Organization (PCO) to ensure the safety, quality, and accessibility of Pact contracts.

## Mission Alignment

In alignment with the PCO mission to "Make it easy and safe for businesses to start building with Pact," the Contract Catalog provides a curated collection of audited, reliable open-source Pact contracts. Our vision is to foster a trusted Pact ecosystem where businesses can confidently use these contracts for their applications.

## Purpose

The Pact Contract Catalog serves as:

- **A Trusted Registry**: Verified reusable Pact contracts for businesses and developers.
- **A Knowledge Base**: Reference implementations, metadata, and usage guidelines.
- **A Quality Standard**: Contracts reviewed for security, maintainability, and compliance with community policies.
- **An Onboarding Platform**: A streamlined process for submitting and validating new contracts to ensure they meet PCO standards.

## Repository Structure

- `contracts/`: Verified Pact contracts organized by category (includes co-located metadata and test files).
- `tests/`: (Deprecated) Test suites for contract validation - tests are now co-located with contracts.
- `docs/`: Documentation, usage guides, and onboarding instructions.
- `policies/`: Community policies for contract submission and maintenance.

## Onboarding a New Contract

To onboard a new contract:

1. **Prepare Your Contract**: Ensure it follows Pact best practices and includes comprehensive tests.
2. **Submit a Pull Request**: Create a PR with your contract in `contracts/`, metadata in `metadata/`, and tests in `tests/`.
3. **Compliance Check**: The PR will trigger automated checks for syntax, security, and policy compliance.
4. **Review Process**: Core maintainers and the Security WG will review for quality and safety.
5. **Audit and Approval**: Contracts may require external audit before acceptance.
6. **Publication**: Approved contracts are merged and become part of the trusted catalog.

See [docs/onboarding.md](docs/onboarding.md) for detailed instructions.

## How to Use

1. Browse the `contracts/` directory to find reusable Pact contracts.
2. Refer to the `metadata/` directory for contract details.
3. Follow the usage instructions in the `docs/` directory.

## Contributing

We welcome contributions to the Pact Contract Catalog! Please see our [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to submit new contracts or improve existing ones.

## Governance

This repository follows the governance model defined in the [PCO Foundation](https://github.com/Pact-Community-Organization/foundation). For contract-specific policies, see [policies/](policies/).

## License

This repository is licensed under the Apache-2.0 License. See the [LICENSE](LICENSE) file for details.