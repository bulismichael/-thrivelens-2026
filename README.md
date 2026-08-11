# ThriveLens

ThriveLens is being delivered release-by-release. R0 is the foundation heartbeat: a Flutter surface will eventually call a generated client, a loopback FastAPI service, and real PostgreSQL. The repository currently contains the verified delivery control plane and installation-free R0 platform contracts; it does **not** yet contain a verified database runtime or working product heartbeat.

## Current platform status

- CPython 3.13.15 provenance is pinned to the Python Software Foundation's x86-64 installer. Installation is hard-disabled because the known artifact/target subtotal excludes TEMP/TMP scratch and persistent installer-cache bytes and their counted paths. The verifier specifies official SHA-256 and PSF Authenticode checks; the upstream Sigstore bundle is recorded but **not enforced**.
- The EDB PostgreSQL 17.10-2 Windows binaries ZIP is **rejected for runtime**, not merely awaiting a local checksum: EDB publishes no archive checksum or detached signature. The portable ZIP path and the interactive Windows installer path are both hard-disabled.
- WSL PostgreSQL is therefore required but **not activated**. A human must authorize the system change, pin a distribution-signed exact package, and establish dedicated aggregate-counted WSL storage first.
- The PostgreSQL-only Compose descriptor is inert: `services` is empty and no repository configuration can pull or start its pinned image. Docker Desktop is not required or installed for R0, engine storage accounting is not configured, and the mandatory gated activation wrapper does not exist.
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

There is no approved Windows PostgreSQL provisioning sequence. Do not download the EDB ZIP or use the interactive EDB installer for this task. `install_postgres.ps1` is a small unconditional structured blocker: it never opens or extracts an archive and contains no dormant extraction route.

There is likewise no approved Python provisioning sequence. `install_python.ps1` blocks before inspecting an artifact or starting a process. A future separately reviewed implementation must first measure and bound installer scratch/cache behavior, place every persistent path under aggregate accounting, and then restore pre/post resource gates. PostgreSQL initialization cannot be enabled until the integration owner updates `docs/privacy/DATA_INVENTORY.md`; that document is outside TL-R0-003 ownership.

If an authorized WSL foundation is later delivered, `test_runtime.ps1` must prove real readiness, loopback-only ownership, exact versions from `postgres`, `pg_ctl`, `initdb`, and `pg_isready`, bounded start/stop, and exact process/listener absence **before** reporting PASS.

Stop is cleanup-safe even under low memory:

```powershell
pwsh -NoProfile -File scripts/dev/postgres/stop.ps1
```

## Compose contract

`infra/compose.yaml` contains `services: {}` plus a non-runnable `x-thrivelens-postgres-contract` descriptor. The descriptor records the pinned linux/amd64 child digest, loopback endpoint, exact `tl_bootstrap` administrator, `thrivelens_r0` database, port `55432`, paths, and limits, but exposes no runnable image, port, volume, or secret interpolation.

`validate_compose_inputs.ps1` has no override parameters. It reads the intended data directory, password file, user, database, and port once from the five process-environment names recorded in the manifest, rejects any drift from the exact pins, validates the existing ACL/resource/privacy/accounting gates, and always returns `COMPOSE_ACTIVATION_WRAPPER_REQUIRED`. Set `TL_POSTGRES_COMPOSE_DATA_DIR` to the exact expanded `%LOCALAPPDATA%\ThriveLens\data\postgresql\compose-r0` path; copying `.env.example` creates neither the directory nor a credential.

A future separately reviewed wrapper must read one immutable process-environment snapshot, validate it, generate a temporary runnable Compose configuration from that same snapshot, and invoke it in the same process flow. It must never validate one value and let Compose re-read another environment value. Until that wrapper exists, direct Compose activation is intentionally impossible.
