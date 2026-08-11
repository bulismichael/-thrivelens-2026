# Architecture decision log

## ADR-001 - Lean modular monolith first

Status: ACCEPTED for R0
Decision: Use a feature/domain-oriented FastAPI modular monolith, PostgreSQL, versioned REST/OpenAPI, generated clients, and Flutter feature-first architecture. Add admin web and provider/model/geospatial infrastructure only with an active use case and evidence-backed ADR.
Why: The repository has no product code, R0 is one vertical slice, and this minimizes operational, supply-chain, memory, disk, and contract cost.
Rollback/removal: Modules can be extracted after measured contention or independent lifecycle evidence; no distributed-service compatibility is promised now.

## ADR-002 - Four distinct heartbeat use cases

Status: ACCEPTED for R0 contract work
Decision: Separate process liveness, orchestration readiness, mobile system status, and minimal version. Readiness returns structured `503` for unavailable/non-current PostgreSQL; a reachable API returns mobile status `200 available|degraded`.
Why: Liveness must not restart a healthy API due to dependency failure, orchestration needs truthful non-ready HTTP semantics, and mobile must receive a typed degraded state rather than treating every dependency failure as an unparseable transport error.
Security: Coarse enums only; no topology, revision, DSN, raw driver error, host, or dependency inventory. `no-store` on every response.
Rollback: A later authenticated operational endpoint may replace this anonymous operational surface without changing transport-independent domain results.

## ADR-002A - Same-origin automatic Flutter web heartbeat

Status: ACCEPTED for R0 contract work
Decision: In local/test R0, FastAPI serves the built Flutter web assets and `/api/v1` from one loopback/internal-CI origin. The client uses a relative API base. R0 enables no CORS, rejects unrelated Origin/OPTIONS access, and remains production-disabled. Chrome phone-viewport proof supplements but does not replace Android execution evidence.
Why: A separately hosted Flutter development origin would be blocked by the browser under the no-CORS policy. One origin is smaller, deterministic, and closer to a deployable artifact without widening anonymous access.
Rollback: The static mount is local/test-only and removable when an approved deployment boundary supplies a dedicated origin, HTTPS, authentication, and explicit origin policy.

## ADR-002B - Android debug reaches host loopback through ADB reverse

Status: ACCEPTED for R0 contract work
Decision: Keep FastAPI bound to host `127.0.0.1:8000`. For an explicitly selected emulator or attached Android device, the verification wrapper creates `adb reverse tcp:8000 tcp:8000`; the debug app uses `http://127.0.0.1:8000/api/v1`, allows cleartext only in its debug configuration, and removes the mapping in cleanup. Release/production contains no cleartext opt-in and rejects the debug base. The exact machine-validated contract is `config/r0-network-policy.json`; prose cannot weaken it.
Why: Device loopback is not host loopback. ADB reverse proves the real app without exposing FastAPI on a LAN interface or adding emulator-specific host aliases.
Rollback: Remove the bounded reverse mapping and stop the loopback process. A later approved HTTPS deployment replaces the debug base and policy.

## ADR-003 - Real PostgreSQL with portable local and Compose contracts

Status: PROVISIONAL; TL-R0-003 must verify the exact archive before acceptance
Problem: Docker/PostgreSQL are absent, host RAM is constrained, but R0 must prove real PostgreSQL.
Decision candidate: Prefer an official-page-linked portable Windows PostgreSQL binary archive installed under the aggregate-counted `%LOCALAPPDATA%\ThriveLens` root, manually started on loopback with a dedicated cluster. Also commit a minimal PostgreSQL-only Compose contract for compatible CI/developer hosts. Do not install Docker Desktop for R0. WSL2 PostgreSQL is the fallback if the portable archive cannot be verified or operated safely.
Wave 0 reversal rationale: Platform discovery initially preferred the already-installed WSL2 Ubuntu path because portable Windows availability had not been verified. The root later verified that the official PostgreSQL Windows page links an advanced-user binary zip. That makes a no-service, no-sudo, attributable portable candidate credible, but not accepted until TL-R0-003 records its exact EDB-hosted artifact, immutable version, checksum or signature availability, licence and maintenance provenance, measured compressed/extracted sizes, start/stop evidence, and fallback trigger.
Options rejected: SQLite/PGLite cannot prove PostgreSQL; remote managed DB needs credentials/provider approval; Docker Desktop adds unverified virtualization and memory cost; system-wide installer creates more global state.
Security: Dedicated migration/runtime roles, loopback only, no auto-start, no runtime DDL credentials, sanitized config.
Cost/resource: Project target allocation 1 GB including binary, R0 data, and one synthetic backup; exact compressed/extracted sizes are measured before install.
Rollback: Stop the dedicated cluster and remove only the verified ThriveLens root after authorization; never remove unrelated PostgreSQL/WSL resources.

## ADR-004 - External attributable tool root with aggregate accounting

Status: ACCEPTED
Decision: Keep source in the OneDrive workspace, but put SDKs, caches, task worktrees, and local data under `%LOCALAPPDATA%\ThriveLens`, avoiding spaces/sync/elevation. The resource gate aggregates both roots.
Why: Flutter advises a path without spaces/elevated permissions, Android/Gradle/database tooling can be sensitive to sync paths, and all attributable bytes still need enforcement.
Rollback: Paths remain project-specific and removable only after target verification and authorization.

## ADR-005 - R0 persists no user data

Status: ACCEPTED
Decision: R0 persists only tool-required migration metadata. Status results remain in Flutter process memory, and no probe-history table, identity, device identifier, wellness record, analytics payload, or audit record is created.
Why: The heartbeat needs no user data and production retention is not approved.
Rollback: Later persisted fields require a release use case, inventory entry, migration, authorization, export/deletion behavior, and human-approved production retention.

## ADR template for later dependencies

Record problem, measured limitation, options, decision, licence/maintenance, security/privacy, hardware/operating cost, migration/rollback, tests, and removal criteria before introducing a production dependency or service.
