# Traceability matrix

| Requirement | Source | R0 implementation task | Automatic evidence | Current truth |
|---|---|---|---|---|
| Preserve existing work and reversible history | Prompt sections 6, 24 | TL-R0-001 | Git checkpoint and clean-status evidence | `fc57594` and `44515a0` exist |
| Strict aggregate footprint below 18 GB | User request; AGENTS resource ceiling | TL-R0-001, TL-R0-003, TL-R0-009 | Non-overridable boundary, nested-root, junction, sanitization, and aggregate tests | Control plane verified; integrated blocked scaffold passes at 0.003 GB |
| Real Flutter -> generated client -> API -> PostgreSQL path | Prompt R0 and step 6 | TL-R0-003 through TL-R0-010 | Same-origin Chrome plus Android real-PostgreSQL/client/e2e reports and screenshots | Platform scaffold integrated; no runtime exists and downstream tasks remain blocked |
| Liveness independent from database readiness | Prompt R0; Wave 0 backend/security | TL-R0-002, TL-R0-005 | Unit and stopped-database integration tests | Specified |
| Mobile can render reachable/degraded API | Wave 0 product/backend/UX | TL-R0-002, TL-R0-005, TL-R0-008 | Status contract and real degraded e2e test | Specified |
| Generated clients are transport truth | Prompt section 12 | TL-R0-002, TL-R0-006, TL-R0-008 | Deterministic regeneration/no-drift test | Not started |
| Structured errors and safe correlation | Prompt R0; threat R0-T02/R0-T11 | TL-R0-002, TL-R0-005 | Contract, sentinel redaction, malformed-header tests | Specified |
| Production rejects demo/unsafe defaults | Prompt mandatory tests; threat R0-T01 | TL-R0-003, TL-R0-005, TL-R0-009 | Runtime-config and release-transport tests | Platform installers fail closed and Compose has no runnable service surface; API not implemented |
| R0 persists no user data or probe history | Product boundary; data inventory | TL-R0-004, TL-R0-005 | Read-only/repeated-probe integration tests | Specified |
| Initial premium accessible Flutter system | Prompt section 9; frontend skill; Wave 0 UX | TL-R0-007, TL-R0-008 | Widget, golden, semantics, text-scale, reduced-motion evidence | Specified, not brand-approved |
| Tier 1 under 10 minutes; Tier 2 under 30 | Prompt sections 13 and 19 | TL-R0-009, TL-R0-010 | Timed reports | Not measured |
| Non-AI API p95 at most 500 ms provisional | Prompt section 19 | TL-R0-010 | Recorded load test and confidence interval | Not measured |
| No large models or speculative services | Prompt sections 8, 15, 30 | All R0 tasks | Dependency/tree/resource policy tests | Specified |
| Adult-only default and minor protections | Prompt section 3.1 | R1 task graph later | Policy fixtures | Not started; no R0 onboarding |
| Unconfirmed foods never affect nutrients | Prompt mandatory safety tests | R1/R2 tasks later | Calculation and confirmation tests | Not started |
| Raw pose frames stay on device by default | Prompt R3 and mandatory tests | R3 tasks later | Upload/log negative tests and device evidence | Not started |
| Human approvals remain separate | Prompt sections 4, 20, 26 | TL-R0-001 and every release closure | Approval ledger and registry validation | All pending |

The matrix expands when a release becomes active; a future row cannot be marked passing from a placeholder, fixture, or plan.
