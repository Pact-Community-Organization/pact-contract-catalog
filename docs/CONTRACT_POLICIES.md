# Contract Policies

This document outlines the comprehensive policies governing the submission, maintenance, and management of Pact smart contracts in the Pact Contract Catalog. These policies ensure alignment with the Pact Community Organization's (PCO) mission to make Pact contracts easy, safe, and reliable for businesses, fostering a trusted ecosystem.

## 1. Licensing
- All contracts must be licensed under Apache-2.0 or a compatible open-source license that allows free use, modification, and distribution.
- The license must be explicitly stated in the contract's metadata file.
- Contributors must ensure they have the rights to license the code as specified.

## 2. Quality Standards
- Contracts must adhere to Pact language best practices, including proper module structure, efficient code, and clear naming conventions.
- Comprehensive documentation must be provided, including function descriptions, parameter types, return values, and usage examples.
- Test coverage must be at least 80% for all public functions, with tests demonstrating correct behavior and edge cases.
- Contracts should be modular and reusable where possible.

## 3. Security
- Contracts must not contain known security vulnerabilities, such as reentrancy issues, integer overflows, or improper access controls.
- All contracts undergo automated security scans during CI.
- The Security Working Group (WG) conducts manual reviews for contracts deemed high-risk (e.g., those handling significant value or complex logic).
- External security audits are required for contracts in critical categories (e.g., financial, governance) or upon maintainer discretion.
- Security issues must be reported via the PCO's security disclosure process (see [SECURITY.md](../SECURITY.md)).

### 3.1 Audit-status ladder (canonical)

Every contract entry declares an `audit_status` in its `metadata.yaml`. The value
**must** be exactly one of the five levels below. These are the only accepted
values; the CI validator rejects any other string. The word "audited", unqualified,
is deliberately **not** a value — it overclaims. Each level states precisely who
looked at the code and how, so an enterprise evaluator can calibrate trust.

| Level | Meaning | Evidence required in `AUDIT.md` |
|-------|---------|----------------------------------|
| `reference` | Upstream code (Kadena LLC / third-party) catalogued verbatim for documentation. PCO makes **no** security claim of its own. | Provenance: source repo or on-chain module hash. |
| `unaudited` | Catalogued but not reviewed by PCO. Use at your own risk. | None; status is the honest default. |
| `self-reviewed` | The author performed a documented self-review against the PCO checklist. Not independent. | Self-review notes + checklist coverage. |
| `community-reviewed` | At least one PCO reviewer other than the author reviewed the code and signed off. | Reviewer name(s), date, findings + dispositions. |
| `independently-audited` | An independent third-party auditor (firm or PCO Security WG member with no authorship stake) produced a dated report, and the audited source hash matches the catalogued source. | Auditor identity, report link/attachment, audited module hash, remediation status. |

Promotion up the ladder requires the evidence in the right-hand column to be
present in the contract's `AUDIT.md`. Downgrades occur automatically when a
contract changes without re-review, or when a maintainer flags a regression.

## 4. Maintenance
- Contracts must be actively maintained by their authors or designated maintainers.
- Updates must be provided for breaking changes in dependencies or Pact language updates.
- Contracts not updated for 12 months may receive deprecation warnings.
- Deprecated contracts must include migration guides or alternatives.

## 5. Compliance and Ethics
- All submissions must adhere to the PCO Code of Conduct.
- Contracts must not contain discriminatory, harmful, or illegal content.
- Intellectual property rights must be respected; no copyrighted or proprietary code without permission.
- Contracts promoting scams, fraud, or unethical practices are strictly prohibited.

## 6. Submission Requirements
- Submissions must include the contract code, a co-located `metadata.yaml`, a `README.md`, an `AUDIT.md`, and a test suite.
- Metadata must accurately describe the contract's purpose, functions, dependencies, and audit status.
- Contracts must pass all CI checks (syntax validation, tests, security scans).
- Submissions from new contributors may require additional scrutiny.

## 7. Categories and Tags
- Contracts must be categorized appropriately (e.g., finance, governance, utilities, examples).
- Relevant tags must be applied for discoverability (e.g., audited, beginner-friendly, deprecated).
- Misclassification may result in re-categorization by maintainers.

## 8. Versioning
- Contracts must follow semantic versioning (MAJOR.MINOR.PATCH).
- Breaking changes require a new major version.
- Version history must be documented in metadata.

## 9. Dependencies
- Dependencies on other contracts or modules must be clearly listed.
- Contracts should minimize external dependencies to reduce risk.
- Dependency updates must be tested and documented.

## 10. Review Process
- All submissions undergo automated CI checks for syntax, tests, and basic security.
- Manual review by core maintainers assesses quality, compliance, and fit for the catalog.
- Security WG review for high-risk contracts.
- Council approval for contracts affecting governance or high-value operations.
- Review feedback must be addressed within 30 days, or the PR may be closed.

## 11. Appeals and Disputes
- Contributors may appeal review decisions to the PCO Council.
- Appeals must be submitted as GitHub issues with detailed rationale.
- The Council will mediate and provide a final decision within 14 days.

## 12. Deprecation and Removal
- Contracts may be deprecated for security issues, lack of maintenance, or policy violations.
- Deprecated contracts remain accessible but are marked as such.
- Removal occurs only for severe violations, with 30-day notice and migration guidance.
- Removed contracts are archived but not deleted.

## Enforcement
- Policy violations may result in warnings, contract deprecation, or removal from the catalog.
- Repeat violations may lead to contributor restrictions.
- All enforcement actions are documented and appealable.

These policies are living documents and may be updated via the PCO governance process. Contributors are encouraged to review them before submission.