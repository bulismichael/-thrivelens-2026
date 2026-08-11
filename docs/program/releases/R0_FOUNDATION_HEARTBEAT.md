# R0 - Foundation heartbeat

Status: active
Primary actor: developer or evaluator using a visibly labelled local/test/demo build
Production-facing wellness functionality: absent

## Objective

Establish a clean, reversible, resource-bounded delivery system and one real mobile-to-API-to-database path without prematurely introducing later product capabilities.

## Primary use case

Use case: Verify the live ThriveLens development stack from Flutter.
Actor: Developer or evaluator.
Preconditions: Pinned supported tools; same-origin loopback/internal-CI Flutter web and API surface; debug-only Android `adb reverse tcp:8000 tcp:8000` transport to the still-loopback-only API; frozen OpenAPI; generated Dart client; FastAPI running; real PostgreSQL reachable and at the expected single migration head for the happy path.
Trigger: Open system status or select retry.
Input: Configured non-secret loopback/internal API base URL, trusted local build mode, retry action; no body, identity, token, device ID, or wellness data.
Happy path: UI enters checking; generated client requests mobile system status and version; FastAPI performs a read-only database/current-head check; typed response parses; UI shows service available and database ready with freshness.
Alternative paths: Reachable API plus unavailable/behind/ahead database yields typed degraded status; version failure remains non-blocking; confirmed device offline is distinct from service failure.
Failure paths: Timeout, refused connection, malformed response, unknown enum, unexpected server error, and stale out-of-order retry all fail closed without raw transport details.
Domain invariants: Liveness never checks PostgreSQL; readiness is ready only for reachable/current database; mobile status returns a typed degraded result when the API is reachable; prior/fake/cached success cannot make the current check ready; generated models are the only transport source of truth.
Authorisation: Anonymous minimal read on a loopback/internal CI listener in R0 local/test/demo; exposes only coarse state and bounded versions. R0 production startup is disabled until a later hosting/network/retention decision.
Audit event: No domain audit record. Allowlisted operational event only.
Retention: UI memory only; no probe-history rows; synthetic disposable logs.
Offline behaviour: No offline queue. A prior result, if shown, is explicitly stale; retry is manual.
Output: Current checking, ready, degraded, unreachable, timeout, malformed, or confirmed-offline view.
User-visible uncertainty: Say `Not ready`, `Unknown`, or `Cannot reach`; never infer `down` without evidence.
Acceptance evidence: Contract, migration, PostgreSQL integration, generated-client freshness, Flutter state/widget/golden/accessibility, redaction, performance, resource, build, and cross-boundary heartbeat reports.

## Frozen direction pending contract task

- `GET /api/v1/health/live`: process liveness only.
- `GET /api/v1/health/ready`: orchestration readiness; `200` only for reachable/current PostgreSQL, otherwise structured `503`.
- `GET /api/v1/system/status`: mobile-facing aggregate; reachable API returns typed `200 available|degraded` so the client can render dependency failure.
- `GET /api/v1/system/version`: bounded API/service version; failure cannot override valid operational status.
- Every response is non-cacheable; errors are structured and redacted; correlation identifiers are bounded and sanitised.
- The automatic Flutter web harness is same-origin: local/test FastAPI serves the built Flutter assets and `/api/v1` from one loopback origin; R0 enables no CORS.
- Android debug uses the non-secret base `http://127.0.0.1:8000/api/v1` only after the verification wrapper creates `adb reverse tcp:8000 tcp:8000`; the wrapper removes the reverse mapping during cleanup. Cleartext is allowed only by the debug Android configuration. Release/production rejects this base and contains no cleartext opt-in. FastAPI remains bound to host loopback.
- R0 listeners default to loopback/internal CI and production mode refuses to start.

The exact OpenAPI is integration-owned by `TL-R0-002` and is not frozen merely by this brief.

## UX direction

Use the provisional `Quiet Aperture` direction: warm neutral field, decisive high-contrast type, one restrained lens/focus motif, cardless divider-separated status rows, and stable layout across state changes. R0 omits inactive Today/Lens/Plan/Progress/Profile navigation. The screen separately names `App service` and `Database`, gives one retry action, shows freshness and trusted local mode, and progressively discloses bounded build details.

This is an engineering direction, not human brand approval.

## Exit gate

- Documented bootstrap runs on a supported clean environment.
- Real PostgreSQL empty-cluster migration and current-head checks pass.
- Liveness remains healthy when PostgreSQL is unavailable; readiness and mobile status report their distinct typed states.
- Dart client is reproducibly generated from canonical OpenAPI with zero drift.
- Flutter displays real current status and tested failure/retry states through the same-origin automatically verified Chrome phone viewport.
- The Android debug application builds and the real ready/degraded heartbeat executes on an emulator/capable runner or attached Android device; Chrome evidence alone cannot close R0.
- Tier 1/2 gates, sequential builds, scans, and aggregate resource checks pass.
- Independent quality, security/privacy, UX, and integration findings are resolved or truthfully blocking.
- The broader physical-device matrix, iOS, signing, brand, and human approvals are not inferred.

## Rollback

Stop the dedicated local PostgreSQL process and API, preserve only explicitly required synthetic evidence, remove only verified ThriveLens tool/cache/data roots when authorised, revert through normal Git commits, and never delete the WSL distribution or unrelated user tools/data.
