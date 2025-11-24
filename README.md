# Pact Contract Catalog

Welcome to the Pact Contract Catalog, the central repository for reusable, trusted Pact smart contracts. This repository is maintained by the Pact Community Organization (PCO) to ensure the safety, quality, and accessibility of Pact contracts.

## Mission Alignment

In alignment with the PCO mission to "Make it easy and safe for businesses to start building with smart contracts," the Contract Catalog provides example contracts, testing frameworks, and development tools to help build a trusted Pact ecosystem. We're starting small but growing through community contributions.

## Purpose

The Pact Contract Catalog serves as:

- **A Starting Point**: Example contracts and testing infrastructure for the growing Pact ecosystem
- **A Development Framework**: Tools and processes for contract validation and testing
- **A Quality Standard**: Guidelines for secure, maintainable Pact contract development
- **A Community Hub**: Platform for developers to learn, contribute, and collaborate on Pact contracts

## Repository Structure

- `contracts/`: Example Pact contracts with testing (currently 1 example: hello-world)
- `docs/`: Documentation, usage guides, and onboarding instructions
- `policies/`: Community policies for contract submission and maintenance

## Testing Contracts

To test Pact contracts locally, use a Pact REPL environment:

1. Go to the repository: https://github.com/CryptoPascal31/kadena_repl_sandbox
2. Follow the instructions in its README to set up the local REPL environment.
3. Clone the sandbox repository and use it to run `.repl` test files from this catalog.

For example, to test the hello-world contract:
- Navigate to `contracts/hello-world/`
- Run the test using the sandbox environment as per the kadena_repl_sandbox instructions.

This ensures contracts are tested in a proper Pact environment before submission.

## Onboarding a New Contract

To contribute a new contract to the catalog:

1. **Prepare Your Contract**: Ensure it follows Pact best practices and includes comprehensive tests.
2. **Submit a Pull Request**: Create a PR with your contract in `contracts/`, following the hello-world example structure.
3. **Community Review**: Get feedback from other contributors and maintainers.
4. **Testing**: Ensure contracts work with the provided testing framework.
5. **Publication**: Approved contracts are merged and become part of the growing catalog.

See [docs/onboarding.md](docs/onboarding.md) for detailed instructions.

## How to Use

1. Browse the `contracts/` directory to see example Pact contracts (currently hello-world).
2. Use the testing framework to validate your own contracts.
3. Follow the contribution guidelines to add new contracts.
4. Refer to the `docs/` directory for development guides.

## Contributing

We welcome contributions to the Pact Contract Catalog! Please see our [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to submit new contracts or improve existing ones.

## Governance

This repository follows the governance model defined in the [PCO Foundation](https://github.com/Pact-Community-Organization/foundation). For contract-specific policies, see [policies/](policies/).

## License

This repository is licensed under the Apache-2.0 License. See the [LICENSE](LICENSE) file for details.