# ThriveLens

ThriveLens is being delivered release-by-release. R0 is the foundation heartbeat: a Flutter surface will eventually call a generated client, a loopback FastAPI service, and real PostgreSQL. The repository currently contains the verified delivery control plane and installation-free R0 platform contracts; it does **not** yet contain a verified database runtime or working product heartbeat.

## Current platform status

- CPython 3.13.15 is pinned to the Python Software Foundation's x86-64 installer. The local verifier enforces the official SHA-256 and PSF Authenticode signature. The upstream Sigstore bundle is recorded for provenance but is **not enforced** by these scripts.
- The EDB PostgreSQL 17.10-2 Windows binaries ZIP is **rejected for runtime**, not merely awaiting a local checksum: EDB publishes no archive checksum or detached signature. The portable ZIP path and the interactive Windows installer path are both hard-disabled.
- WSL PostgreSQL is therefore required but **not activated**. A human must authorize the system change, pin a distribution-signed exact package, and establish dedicated aggregate-counted WSL storage first.
- The PostgreSQL-only Compose contract is a secondary, default-disabled option for compatible CI/developer hosts. Docker Desktop is not required or installed for R0, and engine storage accounting is not configured.
- No artifact, service, cluster, credential, or licence acceptance is created by the repository scripts without an explicit later provisioning action.

The authoritative details and primary-source links are in [the R0 platform note](docs/program/task-notes/r0/platform.md) and the machine-readable manifest at `config/toolchains/backend.json`.

## Resource gate

Every install or large build must run:

```powershell
pwsh -NoProfile -File scripts/check_resource_budget.ps1
```

The aggregate ThriveLens footprint must remain strictly below 18 GB, with installations stopped at the 85% high-water mark. Before any backend installation, the integration owner must change only `config/resource-budget.json`'s `phase` from `prebootstrap` to `bootstrap_active`; this makes `%LOCALAPPDATA%\ThriveLens` mandatory and accounted. The backend preflight then additionally requires at least 2 GiB free memory for installation and 1 GiB for runtime work.

## Safe installation-free checks

These checks do not download artifacts, create credentials, start services, or invoke WSL/Docker:

```powershell
pwsh -NoProfile -File scripts/bootstrap/backend/test_manifest.ps1
pwsh -NoProfile -File scripts/dev/postgres/test_static.ps1
pwsh -NoProfile -File scripts/dev/postgres/test_security_controls.ps1
pwsh -NoProfile -File scripts/dev/postgres/preflight.ps1
```

The first three should pass. The last command is expected to return `BLOCKED` with the rejected-Windows-runtime and not-activated-WSL codes, plus any current resource/binary/cluster blockers. A missing runtime is never reported as PostgreSQL evidence.

## Provisioning boundary

There is no approved Windows PostgreSQL provisioning sequence. Do not download the EDB ZIP or use the interactive EDB installer for this task. The dormant ZIP installer code remains fail-closed and can only be reconsidered through a separate publisher-attestation and security review.

Future Python provisioning must use an artifact beneath `%LOCALAPPDATA%\ThriveLens`, then pass the pre-mutation projection/free-disk gate, official hash and Authenticode checks, a no-follow installed-tree ceiling, and the post-mutation aggregate gate. PostgreSQL initialization cannot be enabled until the integration owner first updates `docs/privacy/DATA_INVENTORY.md`; that required document is outside TL-R0-003 ownership.

If an authorized WSL foundation is later delivered, `test_runtime.ps1` must prove real readiness, loopback-only ownership, exact versions from `postgres`, `pg_ctl`, `initdb`, and `pg_isready`, bounded start/stop, and exact process/listener absence **before** reporting PASS.

Stop is cleanup-safe even under low memory:

```powershell
pwsh -NoProfile -File scripts/dev/postgres/stop.ps1
```

## Compose contract

`infra/compose.yaml` has exactly one service, is disabled unless the explicit `postgres-explicit` profile is selected, fixes `platform: linux/amd64`, and pins that platform's child manifest digest. It binds only to `127.0.0.1`, uses an attributable bind directory instead of a named volume, requires a protected password file, and caps runtime memory. `validate_compose_inputs.ps1` remains blocked until container-engine storage accounting and the data inventory gate are configured. Copying `.env.example` creates neither storage nor a credential; both paths are intentionally blank.
