# ThriveLens

ThriveLens is being delivered release-by-release. R0 is the foundation heartbeat: a Flutter surface will eventually call a generated client, a loopback FastAPI service, and real PostgreSQL. The repository currently contains the verified delivery control plane and installation-free R0 platform contracts; it does **not** yet contain a verified database runtime or working product heartbeat.

## Current platform status

- CPython 3.13.15 is pinned to the Python Software Foundation's x86-64 installer with official SHA-256, Sigstore, and Authenticode verification requirements.
- PostgreSQL 17.10-2 is pinned to the Windows x86-64 binaries ZIP linked from the official PostgreSQL Windows page. EDB does not publish a ZIP checksum or detached signature beside this artifact, so the portable candidate remains blocked and uninstalled.
- The PostgreSQL-only Compose contract is a secondary option for compatible CI/developer hosts. Docker Desktop is not required or installed for R0.
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
pwsh -NoProfile -File scripts/dev/postgres/preflight.ps1
```

The first two should pass. The last command is expected to return `BLOCKED` until the resource phase, free memory, archive integrity, binaries, and cluster are all genuinely ready.

## Future PostgreSQL runtime sequence

Do not run this sequence until the integration and independent security reviewers disposition the EDB archive integrity limitation and the host passes preflight.

1. Place reviewed artifacts under `%LOCALAPPDATA%\ThriveLens\downloads`; scripts reject artifacts outside the accounted root.
2. Run `scripts/bootstrap/backend/verify_artifact.ps1` for the artifact kind.
3. Run the applicable `install_python.ps1` or `install_postgres.ps1`; each executes pre/post aggregate resource gates and never modifies the machine `PATH` or registers PostgreSQL as a service.
4. Supply a non-empty password file under the attributable root, then initialize through `scripts/dev/postgres/initialize.ps1`. No default credential is provided or generated.
5. Run `scripts/dev/postgres/test_runtime.ps1`. It must prove a clean start, real `pg_isready`, a `127.0.0.1`-only listener, exact binary execution, and bounded fast shutdown.

Stop is cleanup-safe even under low memory:

```powershell
pwsh -NoProfile -File scripts/dev/postgres/stop.ps1
```

## Compose contract

`infra/compose.yaml` has exactly one service, binds the host side only to `127.0.0.1`, pins the Docker Official Image by immutable index digest, requires a password file, and caps runtime memory. It is not executed on this host. Copying `.env.example` does not create a usable credential; the blank password-file path is intentionally fail-closed.
