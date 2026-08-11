# Human approvals

This is the human-owned decision summary for append-only scoped approval ledgers. Codex may prepare schemas and evidence but may not add an approval, approver identity, approval event, or approval date on a human's behalf.

| Decision ID | Gate | Required named approver | Recorded actors | Current state | First event date | Evidence | Scope/expiry |
|---|---|---|---|---|---|---|---|
| TL-D-001 | First pilot jurisdiction | Product/legal owner | - | PENDING | - | - | - |
| TL-D-002 | Adult-only/minor policy | Product and privacy/legal owners | - | PENDING | - | - | - |
| TL-D-003 | Nutrition content and calculations | Qualified nutrition reviewer | - | PENDING | - | - | - |
| TL-D-004 | Exercise and pose definitions | Qualified exercise reviewer | - | PENDING | - | - | - |
| TL-D-005 | Privacy/legal and retention | Named privacy/legal reviewer | - | PENDING | - | - | - |
| TL-D-006 | Sesotho language | Named Sesotho reviewer | - | PENDING | - | - | - |
| TL-D-007 | Brand system | Brand owner plus accessibility evidence | - | PENDING | - | - | - |
| TL-D-008 | Evidence sources | Domain/evidence owner | - | PENDING | - | - | - |
| TL-D-009 | Production retention and backup matrix | Privacy/legal and operations owners | - | PENDING | - | - | - |
| TL-D-010 | Hosting region budget and boundary | Business/platform owner | - | PENDING | - | - | - |
| TL-D-011 | Provider data handling | Privacy/security owner | - | PENDING | - | - | - |
| TL-D-012 | Model and dataset licences | Legal/data owner | - | PENDING | - | - | - |
| TL-D-013 | Physical-device matrix | Product/quality owner | - | PENDING | - | - | - |
| TL-D-014 | App-store accounts and signing | Store account owner | - | PENDING | - | - | - |
| TL-D-015 | Production credentials and secret management | Security/operations owner | - | PENDING | - | - | - |
| TL-D-016 | Pilot population monitoring and support | Accountable pilot owner | - | PENDING | - | - | - |
| TL-D-017 | Security risk acceptance | Authorised security owner | - | PENDING | - | - | - |

`PENDING` means no approval ledger has ever been activated. `APPROVED` means the decision ledger has at least one current, unrevoked scoped grant. `INACTIVE` preserves a human-owned ledger whose grants are all expired or revoked; it grants no feature authority. Both this table and `DECISIONS_REQUIRED.md` must use the same state.

Activation records the union of actual named humans from every event in `Recorded actors`, in first-event appearance order and separated by semicolons, plus the first event date, canonical path `docs/program/evidence/approvals/TL-D-NNN.json`, and exact summary `SCOPED GRANTS ONLY; SEE LEDGER`. The staged/tracked JSON is a schema-v2 `human_approval_ledger`: prior events are immutable and new events append sequentially with monotonic nondecreasing dates. Each `GRANT` records its own unique `approved_by` actor list and binds exactly one feature, release, full artifact-commit set, jurisdiction, scope, limitations, typed reviewed evidence, and expiry/re-review rule. Each `REVOKE` records its own unique `revoked_by` actor list and references one prior grant. Later events may therefore introduce later actors without rewriting history. Feature evidence cites the exact active event, for example `approval:TL-D-003/TL-D-003-G-0001`; a decision-level `APPROVED` state is never blanket authority. Codex cannot populate identities, dates, grants, revocations, or approval states on a human's behalf.
