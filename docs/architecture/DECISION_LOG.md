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

## ADR-003 - Reject unattested Windows PostgreSQL; require a counted WSL fallback

Status: WINDOWS CANDIDATE REJECTED; WSL FALLBACK REQUIRED BUT NOT ACTIVATED
Problem: R0 must prove real PostgreSQL, but Docker/PostgreSQL are absent, host RAM is constrained, and every attributable byte must remain below the strict 18 GB cap.
Decision: Do not download or execute the EDB Windows binary ZIP. The official PostgreSQL Windows page links it, but the publisher supplies neither an archive SHA-256 nor a detached signature; HTTPS metadata, a multipart ETag, a local hash, and signatures on selected extracted executables cannot attest the complete archive. The Windows portable and interactive paths are hard-disabled. Use a separate project-only supported Ubuntu WSL2 distro located beneath `%LOCALAPPDATA%\ThriveLens` as the required fallback, but activate it only after explicit human system authority, signed repository metadata, an exact PostgreSQL 17.10 package pin, projected storage, and rollback are recorded.
Accounting rationale: The existing shared Ubuntu VHD is about 2.70 GB and lives outside the counted root. Installing packages there would write PostgreSQL binaries, dpkg state, and APT cache outside ThriveLens accounting; a PGDATA-only mount would not fix that. The shared distro therefore remains untouched. A dedicated distro keeps its VHD, package cache, cluster, logs, and any rollback artifact attributable and measurable.
Compose boundary: `infra/compose.yaml` is an inert descriptor with `services: {}`. It cannot pull or start an image. A future runnable Compose path would require a same-process validation-and-use wrapper, exact pinned inputs, engine-layer/cache accounting, an empty protected data directory, and the data-inventory gate; Docker Desktop is not an R0 dependency.
Options rejected: SQLite/PGLite cannot prove PostgreSQL; a remote managed database needs credentials/provider approval; Docker Desktop adds unverified virtualization, storage, and memory cost; the system-wide Windows installer and unattested ZIP create unacceptable global or supply-chain state; the shared WSL distro breaks attributable accounting.
Security: Manual lifecycle only; loopback binding; SCRAM; data checksums; dedicated migration/runtime roles; no auto-start; no runtime DDL credentials; exact process/listener/absence proof; sanitized outputs. No WSL, package manager, service, credential, or cluster action is authorized by this ADR alone.
Cost/resource: Every distro image/VHD, package cache, PostgreSQL binary/cluster/log, synthetic backup, SDK, and build artifact must be counted before and after mutation. Installation remains blocked below 2 GiB free RAM and runtime below 1 GiB.
Rollback: Stop and prove absence first. Remove only recorded project packages/data or unregister only the dedicated project distro after separate destructive authorization. Never modify, terminate, export, or unregister the existing shared Ubuntu distro.

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
