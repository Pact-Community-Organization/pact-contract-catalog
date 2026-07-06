# Contributing to the Pact Contract Catalog

Thank you for your interest in contributing to the Pact Contract Catalog! This repository is a critical resource for the smart contract ecosystem, and we appreciate your help in maintaining its quality and accessibility.

## How to Contribute

1. **Submit New Contracts**: Add reusable Pact contracts to the `contracts/` directory. See [docs/ONBOARDING.md](docs/ONBOARDING.md) for detailed instructions.
2. **Improve Metadata**: Update or add the `metadata.yaml` file co-located with each contract in `contracts/<layer>/<slug>/`.
3. **Enhance Documentation**: Improve usage guides and examples in the `docs/` directory.
4. **Report Issues**: Found a bug or have a suggestion? Open an issue in this repository. For security issues, follow [SECURITY.md](SECURITY.md).

## Contribution Guidelines

- Follow the [Code of Conduct](CODE_OF_CONDUCT.md).
- Ensure your contracts pass all linting and testing checks.
- Include metadata files for new contracts.
- Write clear commit messages and PR descriptions.
- Comply with [docs/CONTRACT_POLICIES.md](docs/CONTRACT_POLICIES.md).

## Development Workflow

1. Fork the repository and clone it locally.
2. Create a new branch for your changes.
3. Add or modify contracts, metadata, or documentation.
4. Test your changes locally.
5. Commit your changes with a descriptive message.
6. Push your branch to your fork and open a pull request.

## Review Process

- Pull requests are reviewed by maintainers.
- Feedback will be provided, and changes may be requested.
- Once approved, your PR will be merged.

## Reviewing a Library Template

Reviewing an existing template is the highest-leverage contribution this
catalog accepts: a qualifying independent review promotes an entry from
`self-reviewed` to `community-reviewed` on the
[audit-status ladder](docs/CONTRACT_POLICIES.md) (§3.1), which is exactly the
signal enterprise evaluators look for.

**Who qualifies.** Anyone who did not author the template and has working Pact
security knowledge. Disclose any affiliation in the review record.

**What a qualifying review is.** Not a rubber stamp — a documented adversarial
pass:

1. Read the template cold: `<slug>.pact`, its `README.md`, and its `AUDIT.md`
   (which lists the attacks already tried, so you don't repeat them — try new
   ones).
2. Run the co-located suite and write at least a few probes of your own
   against the entry's stated security claims (each `AUDIT.md` has a threat
   model table — attack it).
3. Check the KDA-CE trap classes the suite cannot prove, at minimum: table
   reads inside `enforce` conditions, capability acquisition paths for every
   weak-body cap, and managed-cap argument exactness on any externally
   invoked capability.
4. Write up findings with severity and reproduction. "No findings" is a valid
   result if the work behind it is shown.

**How to submit.** Open a PR that (a) appends your review record to the
entry's `AUDIT.md` — reviewer name/handle, date, scope, findings and their
dispositions — and (b) flips `audit_status` to `community-reviewed` in its
`metadata.yaml` once all findings at MEDIUM or above are resolved. Maintainers
verify the review meets the evidence bar in
[CONTRACT_POLICIES.md](docs/CONTRACT_POLICIES.md) §3.1 before merging.

If you find a vulnerability with live-deployment impact, follow
[SECURITY.md](SECURITY.md) instead of opening a public PR.

## Thank You

Your contributions help make the Pact ecosystem stronger and more accessible for everyone!