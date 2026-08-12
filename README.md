# ThriveLens

ThriveLens is being delivered release-by-release. R0 is the foundation heartbeat: a Flutter surface will eventually call a generated client, a loopback FastAPI service, and real PostgreSQL. The repository currently contains the verified delivery control plane and installation-free R0 platform contracts; it does **not** yet contain a verified database runtime or working product heartbeat.

## Current platform status

The counted, project-only `ThriveLens-R0` WSL2 distribution now exists under `%LOCALAPPDATA%\ThriveLens\wsl\ThriveLens-R0` with a 6 GiB virtual-disk ceiling. Ubuntu 24.04 and the exact PostgreSQL 17.10 PGDG package closure are verified by bounded read-only checks. Ubuntu publishes the selected WSL artifact at exactly 391,541,571 bytes with signed SHA256SUMS metadata; the original `wsl --web-download` payload was not retained, so the current VHD is not byte-attested by that hash. Packages are present; no database cluster or runtime is claimed until initialization and the real two-cycle runtime test pass.

A lightweight read-only Windows snapshot on 2026-08-12 observed the VHD file at 2,131,755,008 bytes and the aggregate counted ThriveLens root at 2,134,150,647 bytes. These are point-in-time file-size/accounting observations, not an Ubuntu image attestation.

- CPython 3.13.15 provenance is pinned to the Python Software Foundation's x86-64 installer. Installation is hard-disabled because the known artifact/target subtotal excludes TEMP/TMP scratch and persistent installer-cache bytes and their counted paths. The verifier specifies official SHA-256 and PSF Authenticode checks; the upstream Sigstore bundle is recorded but **not enforced**.
- The EDB PostgreSQL 17.10-2 Windows binaries ZIP is **rejected for runtime**, not merely awaiting a local checksum: EDB publishes no archive checksum or detached signature. The portable ZIP path and the interactive Windows installer path are both hard-disabled.
- Windows PostgreSQL remains rejected. The WSL fallback is activated only for the exact dedicated distribution; PostgreSQL system units are masked, package-managed cluster creation is disabled, and runtime uses manual `pg_ctl` only.
- APT reported `48.4 MB` of archives and `201 MB` of additional installed space. Those are APT's rounded display figures, not exact byte attestations. The 251,000,000-byte ceiling is package-only and excludes the Ubuntu distro/VHD and APT metadata, which remain covered by aggregate accounting.
- PostgreSQL and Ubuntu installed-package copyright metadata exists inside the distro. The dependency licence inventory has not been independently enumerated or approved, and no production licence approval is inferred.
- The PostgreSQL-only Compose descriptor is inert: `services` is empty and no repository configuration can pull or start its pinned image. Docker Desktop is not required or installed for R0, engine storage accounting is not configured, and the mandatory gated activation wrapper does not exist.
- The dedicated distro, packages, and protected bootstrap credential now exist from the explicitly authorized external provisioning step. No PostgreSQL cluster, service, migration, API, backup, or production licence/approval is claimed yet.

The authoritative details and primary-source links are in [the R0 platform note](docs/program/task-notes/r0/platform.md) and the machine-readable manifest at `config/toolchains/backend.json`.

## Resource gate

Every install or large build must run:

```powershell
pwsh -NoProfile -File scripts/check_resource_budget.ps1
```

The aggregate ThriveLens footprint must remain strictly below 18 GB, with installations stopped at the 85% high-water mark. The integration-owned `config/resource-budget.json` phase is already `bootstrap_active`, so `%LOCALAPPDATA%\ThriveLens` is mandatory and accounted. The backend preflight additionally requires at least 2 GiB free memory for installation and 1 GiB for runtime work.

## Safe installation-free checks

These checks do not download artifacts, create credentials, initialize a cluster, or start PostgreSQL/Docker. The WSL controls and preflight invoke `wsl.exe` only for the exact existing `ThriveLens-R0` distro and can cause Windows to launch that distro to run bounded read-only verification commands:

```powershell
pwsh -NoProfile -File scripts/bootstrap/backend/test_manifest.ps1
pwsh -NoProfile -File scripts/dev/postgres/test_static.ps1
pwsh -NoProfile -File scripts/dev/postgres/test_security_controls.ps1
pwsh -NoProfile -File scripts/dev/postgres/test_wsl_controls.ps1
pwsh -NoProfile -File scripts/dev/postgres/preflight.ps1
```

The manifest, static, security, and WSL-control tests should pass. Until initialization, runtime preflight truthfully returns `POSTGRES_CLUSTER_UNAVAILABLE`.

## Provisioning boundary

There is no approved Windows PostgreSQL provisioning sequence. Do not download the EDB ZIP or use the interactive EDB installer. The current WSL packages were externally provisioned through the authorized signed-PGDG transaction; `install_postgres.ps1` remains the hard Windows-path blocker and is not a general installer.

There is likewise no approved Python provisioning sequence. `install_python.ps1` blocks before inspecting an artifact or starting a process. A future separately reviewed implementation must first measure and bound installer scratch/cache behavior, place every persistent path under aggregate accounting, and then restore pre/post resource gates. The integration owner has now added the dedicated WSL/cluster persisted fields to `docs/privacy/DATA_INVENTORY.md`; initialization still verifies that exact content before mutation.

`test_runtime.ps1` must prove two manual start/authenticated-query/stop cycles without reinitialization, WSL and Windows loopback reachability, exact versions, and exact process/listener absence **before** reporting PASS. PostgreSQL server output goes to `/dev/null`; R0 persists no raw PostgreSQL log.

Stop is cleanup-safe even under low memory:

```powershell
pwsh -NoProfile -File scripts/dev/postgres/stop.ps1
```

## Compose contract

`infra/compose.yaml` contains `services: {}` plus a non-runnable `x-thrivelens-postgres-contract` descriptor. The descriptor records the pinned linux/amd64 child digest, loopback endpoint, exact `tl_bootstrap` administrator, `thrivelens_r0` database, port `55432`, paths, and limits, but exposes no runnable image, port, volume, or secret interpolation.

`validate_compose_inputs.ps1` has no override parameters. It reads the intended data directory, password file, user, database, and port once from the five process-environment names recorded in the manifest, rejects any drift from the exact pins, validates the existing ACL/resource/privacy/accounting gates, and always returns `COMPOSE_ACTIVATION_WRAPPER_REQUIRED`. Set `TL_POSTGRES_COMPOSE_DATA_DIR` to the exact expanded `%LOCALAPPDATA%\ThriveLens\data\postgresql\compose-r0` path; copying `.env.example` creates neither the directory nor a credential.

A future separately reviewed wrapper must read one immutable process-environment snapshot, validate it, generate a temporary runnable Compose configuration from that same snapshot, and invoke it in the same process flow. It must never validate one value and let Compose re-read another environment value. Until that wrapper exists, direct Compose activation is intentionally impossible.
