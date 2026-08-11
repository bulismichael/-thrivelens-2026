# Data flow and trust boundaries

## R0 actors and assets

Actors: device user/tester; untrusted network caller; Flutter/generated client; developer/CI operator; FastAPI runtime; separately privileged migration runner; PostgreSQL; log/evidence reader; dependency and build registries.

Assets: runtime/migration credentials; integrity and availability of status; OpenAPI/generated-client integrity; source/locks/builds; mode separation; allowlisted logs; aggregate resource state. Future wellness data is outside R0.

## R0 flow

```text
Pinned source/tool inputs
        |
        v
Flutter web -- same-origin relative /api/v1, no body/identity/token ---------> FastAPI HTTP adapter
Android debug -- device 127.0.0.1:8000 -- adb reverse -- host 127.0.0.1:8000 -^
        ^                                                      |
        | typed generated response                              | application service
        |                                                      v
        +-- memory-only status <-- redacted domain result -- DatabaseReadinessPort
                                                               |
                                                               | read-only bounded query
                                                               v
                                                        PostgreSQL runtime role

FastAPI -- allowlisted operational event --> local/CI structured log evidence
Migration runner -- explicit DDL credential --> PostgreSQL migration metadata
```

## Trust boundaries

| ID | Boundary | Required control | R0 verification |
|---|---|---|---|
| TB1 | Device/network to FastAPI | Same-origin built Flutter plus API on loopback/internal CI; Android debug reaches host loopback only through bounded `adb reverse`; no CORS; cleartext only in debug; release rejects debug base; R0 production disabled | Origin/OPTIONS, bind, static-fixture/real-build, adb-reverse cleanup, debug/release network-policy, and production-startup tests |
| TB2 | API response to generated client/UI | Closed schemas, deterministic generation, malformed/unknown fail closed | OpenAPI/client drift and widget tests |
| TB3 | FastAPI to PostgreSQL | Loopback/internal only, least-privilege runtime role, pool/time bounds, read-only probe | Role, timeout, stopped/behind DB tests |
| TB4 | Secret/config source to runtime | Typed settings, no production defaults, never echo values | Demo-secret and sentinel tests |
| TB5 | Runtime to logs/CI artifacts | Field allowlist; no bodies, headers, DSN, IP/device/user data, stack or SQL | Captured structured-log schema tests |
| TB6 | Registries/tooling to artifacts | Pinned versions/digests/checksums/locks and critical scan gate | Supply-chain policy and CI checks |
| TB7 | Demo/test/development to production | Explicit trusted mode; production rejects unsafe configuration | Backend and Flutter release-policy tests |
| TB8 | Repository to external attributable roots | Project-specific paths, aggregate accounting, verified deletion target | Resource and path-policy tests |

## Endpoint behavior

- Liveness: process response only; never acquires a database connection.
- Readiness: real PostgreSQL connectivity plus exact expected migration head; returns ready or structured non-ready without details.
- Mobile status: the API component is available because it returned; database is `ready`, `not_ready`, or `unknown`. A reachable connectivity or readable non-current migration state is `not_ready`; an exhausted or cancelled bounded probe is `unknown`. Both negative states make the overall mobile status `degraded` and neither may reuse an earlier success.
- Version: bounded service/API version. No dependency versions, hostnames, build paths, or topology.

All status calls are read-only and idempotent. They create no product row, device identifier, user identifier, audit record, analytics event, queue entry, or persistent mobile cache.

## Later-release boundary additions

Before a new flow persists or transmits data, update this diagram and `DATA_INVENTORY.md` for identity/consent, evidence/assistant, meals/images, plans/progress, admin/audit, routes/places, pose, providers, export/deletion, retention jobs, backups, and model/dataset evaluation. Each adds its own abuse cases and tests; R0 does not prebuild those boundaries.
