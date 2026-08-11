# Risk register

| ID | Severity | Risk | Trigger/evidence | Control and next action | Owner | State |
|---|---|---|---|---|---|---|
| TL-RISK-001 | HIGH | Host memory exhaustion causes failed/corrupt installs or builds | 7.87 GB total; repeated free memory below 1 GB | Sequential phases; preflight free-memory floor; user closes heavy applications before installs/builds | platform_observability_engineer | OPEN |
| TL-RISK-002 | HIGH | Delivery footprint exceeds 18 GB or omits attributable roots | Initial script had cap/root override, exact-cap, overlap, path, and junction defects | Non-overridable configured policy; strict cap; safe traversal; external phase root; sanitized evidence; independent re-review | integration_release_lead | IN MITIGATION |
| TL-RISK-003 | HIGH | R0 cannot yet build or run mobile/database | Flutter, Android/JDK, PostgreSQL absent | Pin official versions/sizes; reversible install; real portable PostgreSQL; truthful blocked evidence | platform_observability_engineer | OPEN |
| TL-RISK-004 | HIGH | False-green readiness hides unavailable or incompatible database | Connectivity-only or stale/fake status | Separate liveness/readiness/mobile status; exact migration head; real stopped/behind/ahead tests | backend_domain_engineer | SPECIFIED |
| TL-RISK-005 | CRITICAL | Demo/default secrets or unsafe debug reach production | Missing runtime validation | Fail-closed production configuration tests; no production defaults; sanitized errors | security_privacy_reviewer | OPEN |
| TL-RISK-006 | CRITICAL | Secrets or sensitive data leak in errors/logs/artifacts | Raw exceptions/access logs/config dumps | Allowlisted JSON logging and sentinel tests; no bodies/headers/DSNs | security_privacy_reviewer | OPEN |
| TL-RISK-007 | HIGH | Supply-chain input is mutable or compromised | No manifests/locks/scans yet | Pin tools/dependencies/actions/images; record provenance; fail critical scan findings | quality_engineer | OPEN |
| TL-RISK-008 | MEDIUM | OneDrive spaces/sync interfere with SDK, Gradle, database, or worktrees | Workspace path contains spaces and sync | Keep source in repo; place attributable tooling/caches/worktrees/data under measured `%LOCALAPPDATA%\ThriveLens` | platform_observability_engineer | OPEN |
| TL-RISK-009 | HIGH | Contract drift corrupts client state interpretation | Handwritten DTO or non-deterministic generation | Canonical OpenAPI, versioned generator, zero-drift check, fail-closed unknowns | integration_release_lead | SPECIFIED |
| TL-RISK-010 | HIGH | Health polling exhausts database/API | Unbounded pool, retry, timeout, or public probing | Pool 5/no overflow proposal; bounded deadlines; no automatic retry; concurrency test | backend_domain_engineer | OPEN |
| TL-RISK-011 | HIGH | Premature ML scaffolding/downloads consume resources and inflate claims | Later capability pulled into R0 | R0 ML non-goal, permanent manual flow dependency, evaluation gates, no checkpoints | vision_ml_engineer | CONTROLLED |
| TL-RISK-012 | HIGH | Human approval is inferred from code or agent review | Status collapsed to done/pilot-ready | Feature registry states, approval ledger, named evidence, independent review | integration_release_lead | CONTROLLED |
| TL-RISK-013 | MEDIUM | Physical-device/emulator evidence unavailable | Virtualization reports false; no ADB/device | Build/widget/browser evidence only; request device or virtualization intervention at the genuine gate | mobile_engineer | OPEN |
| TL-RISK-014 | MEDIUM | No remote backup for Git checkpoints | `git remote` is empty | Keep local checkpoints; ask before creating/pushing a remote; do not claim off-device backup | integration_release_lead | OPEN |

Critical risks block integration when their affected implementation exists. Human acceptance cannot be inferred or silently applied.
