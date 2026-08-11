# Quality gates

## Gate principles

- Requirement -> failing test -> minimal implementation -> refactor -> integration test -> independent review.
- Fixture and fake evidence is labelled and never substituted for real PostgreSQL, device, provider, or dataset verification.
- Tier 1 is offline and deterministic. A retry never hides a flaky test.
- Reports record commit, tool versions, environment, duration, exact counts, resource status, and sanitized failures.
- Critical safety, correctness, security, contract, or resource failures block integration.

## R0 red-green order

1. Validate the control plane and exact-cap resource boundary.
2. Freeze OpenAPI, errors, headers, correlation, and migration-head semantics; prove implementation tests are red.
3. Prove readiness truth table and liveness database independence at the domain layer.
4. Prove empty/current/stopped/behind/ahead PostgreSQL cases and role separation.
5. Implement FastAPI until contract, security, and PostgreSQL tests pass.
6. Generate Dart client; prove deterministic zero drift and fixture compatibility.
7. Implement Flutter state reducer, widgets, semantics, and goldens from red tests.
8. Cross the real generated-client/API/PostgreSQL boundary and capture ready/degraded visual evidence.
9. Run scans, coverage/mutation, sequential builds, performance, and independent reviews.

## Test tiers

### Tier 1 - every commit, target under 10 minutes

- Formatting and static typing.
- Control/OpenAPI/generated-client policy checks.
- Backend unit/ASGI contract/security tests with dependency fakes.
- Flutter state and lightweight widget tests.
- Resource boundary and secret/config policy tests.
- No network, Docker, emulator, real provider, or model.

### Tier 2 - worktree/integration, target under 30 minutes

- Clean real PostgreSQL migration/current-head/role/readiness tests.
- Generated Dart client regeneration and compilation.
- Flutter component/golden/accessibility matrix.
- Real process-boundary heartbeat and forced degraded path in same-origin Chrome.
- Android debug build and the same ready/degraded heartbeat on an emulator/capable runner or attached device.
- Sequential debug builds, scans, aggregate footprint, and worktree cleanliness.

### Tier 3 - nightly

- Fresh checkout/bootstrap, fresh-process flake repetition, targeted mutation, migration/rollback rehearsal, security scans, and controlled API performance.
- Later releases add prompt-injection, retrieval, model, backup/restore, and end-to-end suites only when implemented.

### Tier 4 - release candidate

- Real-provider sandboxes where configured, full active model evaluations, physical-device matrix, accessibility audit, release builds, load/resilience, and deployment/rollback rehearsal.

## R0 coverage and mutation

- Implemented privacy/configuration/error-redaction logic: at least 95% branch coverage.
- Other deterministic backend modules: at least 85% branch coverage.
- Flutter domain/state logic: at least 80% branch coverage.
- Generated clients, migration boilerplate, fixtures, and schemas are excluded from percentage inflation but require contract/integration tests.
- Mutate the readiness decision and error-redaction modules; surviving non-equivalent mutants block R0 closure.

## R0 visual/accessibility matrix

- 360x800 light/dark: checking, ready, database-not-ready, service-unreachable, offline.
- 320x568 light at 200% text: database-not-ready with no clipping.
- 800x1280 dark: ready tablet layout.
- Fixed local test font, time, mode, fixtures, and disabled animation for goldens.
- WCAG 2.2 AA contrast; coherent semantic nodes; minimum 48x48 targets; logical focus order; one polite state announcement; no color-only meaning.

## Integration evidence required

- Empty database migration and exact single head.
- Liveness `200` while database stopped; readiness typed `503`; mobile status typed degraded `200`.
- Repeated probes do not persist status data.
- Generated client handles all success/error fixtures and fails closed on malformed/unknown values.
- Flutter retry is single-fire, stale-response fenced, and raw transport data never rendered.
- Production/demo configuration and sensitive-log sentinels pass.
- Aggregate footprint remains below the enforced high-water mark and strict cap.
- No unresolved critical finding and all reviewers are independent of implementation.

## Evidence integrity

- A task or feature state never advances from prose, an arbitrary existing file, or Git-internal content.
- Test reports, independent reviews, device results, dataset results, screenshots, and human approvals live only in their type-specific `docs/program/evidence/` or `reports/` subdirectory and must already be staged/tracked.
- JSON evidence records identify their type, exact task/feature/decision scope, existing reviewed commit, outcome, and type-specific fields. Independent reviews name a non-implementer role, test evidence, findings disposition, and recommendation.
- A verified task names one canonical commit. Its typed reports must cover every required command at that commit and record environment, tool versions, duration, counts, resource state, and sanitized failures; every required review and its cited reports target that same commit.
- `SECURITY_REVIEWED` requires the security/privacy reviewer and current linked-task tests. Emulator and physical-device states require matching surfaces; dataset state requires current metrics/thresholds and the model/dataset licence decision.
- Human approval additionally records the actual named person separately from the required role. Codex may validate that record but may not author the identity or approval.
