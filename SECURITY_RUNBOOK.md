## Security Runbook (copied from foundation)

Purpose: provide a minimal, practical response playbook for common security events.

1. Triage
   - Assign a Security WG member.
   - Create a private issue (if sensitive) and label `security`.

2. Containment
   - If code is vulnerable, open a draft PR with the fix in a private branch.
   - Revoke any compromised tokens/secrets and rotate keys.

3. Communication
   - Notify maintainers and org owners.
   - For public incidents, prepare coordinated disclosure timeline.

4. Post-Incident
   - Run a security post-mortem.
   - Update docs and checklist in `SECURITY.md`.
