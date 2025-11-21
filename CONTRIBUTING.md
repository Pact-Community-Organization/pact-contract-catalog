Pact Contract Catalog — Contributing
==================================

Thank you for contributing. This document explains the standard contributor flow for the `pact-contract-catalog` repository.

1. Fork the repository and create a topic branch for your work.
2. Follow the repository layout described in `ARCHITECTURE.md`.
3. If you add a contract entry under `contracts/<slug>/`, include a `metadata.yaml` that follows the schema described in `ARCHITECTURE.md`.
4. Add tests and documentation where applicable. Use `tests/` and `examples/` for test harnesses and REPL examples.
5. Open a Pull Request against the `pact-contract-catalog` default branch. Use the PR template and include a clear description, test steps, and any audit notes.

Guidelines and policies
- Keep PRs small and focused.
- Do not commit build artifacts or large generated files.
- Legal/brand-sensitive changes require additional review per `legal/brand-review.md`.

Maintainer exceptions
- If you are the project maintainer and need to merge a change as an exception directly to production, include a justification in the PR body and tag the maintainer. Branch protection may require additional steps; maintainers with admin privileges may merge in exceptional circumstances.

If you have questions, open an issue and tag a maintainer.

---
This file is sourced from the Foundation repository. See the canonical contributing guide in the Foundation for full policy.

Source: [foundation/CONTRIBUTING.md](https://github.com/Pact-Community-Organization/foundation/blob/main/CONTRIBUTING.md)

Guidance summary:
- Fork the repo, create a branch, add contract folder under `contracts/<slug>/` with `README.md`, `metadata.yaml`, optional `examples/` and `AUDIT.md`.
- Validate with `scripts/generate_index.sh` and open a PR.
- Maintainers review and merge after checks and approvals.

