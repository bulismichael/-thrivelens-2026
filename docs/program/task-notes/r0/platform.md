# TL-R0-003 platform foundation

Status: **dedicated WSL and exact packages present; PostgreSQL lifecycle not yet verified; Windows runtime rejected**

Observed: 2026-08-12

Target host: Windows x86-64 with 7.87 GB physical memory; live mutation gates remeasure free memory instead of relying on a stale snapshot.

The user authorized one exact project-only distro and signed-package transaction. The dedicated distro, exact nine-package closure, and protected bootstrap credential exist; the shared Ubuntu distribution was not targeted. No cluster/service/migration/API/backup is claimed, and Docker remains unused.

A lightweight read-only Windows measurement snapshot on 2026-08-12 observed `%LOCALAPPDATA%\ThriveLens\wsl\ThriveLens-R0\ext4.vhdx` at 2,131,755,008 bytes and the deduplicated aggregate counted root at 2,134,150,647 bytes. These values are point-in-time file-length/accounting observations, not a byte attestation of the installed Ubuntu image.

## Decision

Reject the EDB portable Windows archive for ThriveLens runtime use. PostgreSQL 17.10 remains the exact supported R0 version target, but the [official PostgreSQL Windows page](https://www.postgresql.org/download/windows/) links to an EDB-hosted advanced-user ZIP for which the [EDB binaries page](https://www.enterprisedb.com/download-postgresql-binaries?lang=en) publishes neither an archive SHA-256 nor a detached signature. Its HTTP ETag has a multipart suffix and is metadata, not a digest. A local post-download hash would prove repeatability only; signatures on selected extracted executables cannot attest the complete archive.

The manifest therefore stores `null` for the archive digest, marks the portable candidate `REJECTED_FOR_RUNTIME`, and hard-disables its installer. The EDB interactive Windows installer is also `HARD_DISABLED`; it is not an alternate route around the archive decision. No Windows PostgreSQL artifact should be downloaded or accepted under TL-R0-003.

The ADR-003 fallback is activated for the exact `ThriveLens-R0` distro only. Signed PGDG metadata, the full pinned/held package closure, dedicated counted storage, and the privacy inventory are present. Cluster initialization and runtime proof remain gated and sequential.

## Pinned artifacts and projections

| Foundation | Exact artifact | Publisher evidence | Compressed bytes | Known target projection | Current state |
|---|---|---|---:|---:|---|
| CPython | `python-3.13.15-amd64.exe` | [PSF release page](https://www.python.org/downloads/release/python-31315/), SHA-256 `edec09c4853aeae9ac36efb8c9f95b6b8e2fee65eee56d9767a8b7c69c574403`, [Sigstore guidance](https://www.python.org/downloads/metadata/sigstore/), PSF Authenticode | 29,452,944 | 268,435,456-byte target only; TEMP/TMP and persistent cache unknown | **Installation disabled**; Sigstore recorded but not enforced; not downloaded |
| Portable PostgreSQL | `postgresql-17.10-2-windows-x64-binaries.zip` | Official-page-linked EDB HTTPS artifact; Content-Length 333,927,270; Last-Modified `Thu, 11 Jun 2026 12:28:18 GMT`; no published digest/signature | 333,927,270 | Binary 805,306,368 bytes; initial cluster 134,217,728; synthetic backup 67,108,864; total below 1,006,632,960 | **Rejected for runtime**; download/install disabled |
| WSL PGDG package transaction | Exact nine-package closure recorded in the manifest | Signed `noble-pgdg` metadata and pinned/held package versions | APT reported 48.4 MB, rounded | APT reported 201 MB additional installed space, rounded; 251,000,000-byte package-only ceiling | Packages present; no cluster/runtime claimed |
| Compose PostgreSQL | `postgres:17.10-bookworm@sha256:6e5a6518f9d2ff9e9f4cba2a5a87d8f41b0f067f6f92ac847c344351a6c8d923` | [Docker Official Images source of truth](https://github.com/docker-library/official-images/blob/master/library/postgres); linux/amd64 child manifest | 156,095,657 amd64 layer bytes | 536,870,912 runtime plus 134,217,728 data bytes | Inert descriptor; activation wrapper absent; engine accounting absent; image not pulled |

The ceilings are projections, not measurements. Ubuntu publishes the selected WSL artifact at exactly 391,541,571 bytes and binds it in its signed SHA256SUMS metadata; because `wsl --web-download` did not retain that payload, the current VHD is explicitly not claimed to be byte-attested by the recorded hash. Python's 297,888,400-byte artifact-plus-target subtotal is explicitly **not** a worst case because installer TEMP/TMP scratch and persistent installer-cache size and paths are unknown. Consequently both Python and combined-backend worst-case projections are `null`, and Python installation is disabled before artifact or process use. PostgreSQL's rejected Windows artifact-plus-total projection is 1,340,560,230 bytes, but no Windows archive is opened or extracted. The WSL 251,000,000-byte ceiling is limited to the PostgreSQL package transaction: it combines bounded archive and installed-package allowances and excludes the distro/VHD and APT metadata. APT's `48.4 MB` archive and `201 MB` installed figures are rounded transaction output, not exact-byte evidence. Compose projects 827,184,297 bytes while remaining disabled for missing engine accounting. Any future mutation route must reject projected 85%/18 GiB breaches, retain a 512 MiB free-disk reserve, and run post-mutation accounting.

Licences are [PSF License Version 2](https://docs.python.org/3/license.html) for CPython and the [PostgreSQL License](https://www.postgresql.org/about/licence/) for PostgreSQL. Installed PostgreSQL/Ubuntu package copyright metadata exists in the dedicated distro, but the dependency licence inventory has not been independently enumerated or approved. The EDB archive and Docker image may also contain separately licensed dependencies; their bundled inventories remain pending because neither artifact was fetched. No production or dependency licence approval is inferred from documenting or installing these packages.

## Resource and execution contract

Root integration made this exact integration-owned phase change before the authorized WSL package transaction:

```json
"phase": "bootstrap_active"
```

The phase is currently `bootstrap_active`. The single configured `%LOCALAPPDATA%\ThriveLens` root is therefore required, so the repository, worktrees, downloads, SDKs, caches, runtime data, and evidence remain aggregate-counted.

The preflight is intentionally stricter than the global warning:

- install: minimum 2,147,483,648 free bytes;
- PostgreSQL initialize/runtime: minimum 1,073,741,824 free bytes;
- any unavailable memory/disk measurement, inactive resource phase, failed aggregate gate, rejected Windows runtime, inactive WSL fallback, absent binary, or absent cluster is blocking;
- exact projected bytes must remain below both the 85% high-water mark and the 18 GiB cap before any filesystem mutation;
- the rejected EDB archive is never opened or extracted; no dormant ZIP parser or extraction implementation exists;
- Python installation blocks before artifact inspection or process execution until measured scratch/cache ceilings and counted paths exist;
- every existing component of the attributable binary/data/log/executable path is checked for reparse points;
- cleanup/stop remains available when memory is low;
- no checked-in script downloads from the network, modifies machine `PATH`, registers a Windows service, starts Docker, or creates a default password; WSL lifecycle scripts target only `ThriveLens-R0` through bounded argument-list execution.

The integration owner added the dedicated WSL and cluster infrastructure rows to `docs/privacy/DATA_INVENTORY.md`; initialization verifies them before mutation. It also requires the exact protected password file with inheritance disabled, no Allow ACE for any principal other than the current user, LocalSystem, or BUILTIN Administrators, and explicit effective read access for the current user.

The dormant initialization contract uses PostgreSQL's documented `--pwfile`, `--auth-host=scram-sha-256`, `--auth-local=scram-sha-256`, and `--data-checksums` controls. Start checks exact output from all four pinned tools, uses `pg_ctl` with a 30-second wait and binds only `127.0.0.1:55432`. Any post-start failure triggers bounded cleanup. Stop can report `STOPPED` or `ALREADY_STOPPED` only after exact binary-process and dedicated-port listener absence. The runtime test stops and verifies absence before PASS. See upstream [`initdb`](https://www.postgresql.org/docs/17/app-initdb.html) and [`pg_ctl`](https://www.postgresql.org/docs/17/app-pg-ctl.html).

## Compose boundary

`infra/compose.yaml` is a PostgreSQL-only inert descriptor. Its exact `services: {}` mapping means a direct Compose command has no image to pull and no service, port, volume, secret, command, or entrypoint to create. The ignored `x-thrivelens-postgres-contract` extension records the intended future contract without making it runnable. It:

- has status `BLOCKED_GATED_ACTIVATION_WRAPPER_NOT_IMPLEMENTED`, rejects direct activation, and records `postgres-explicit` only as a future generated-config profile;
- fixes `platform: linux/amd64` and pins its child manifest digest rather than only the multi-platform index;
- pins `127.0.0.1:55432`, administrator `tl_bootstrap`, and database `thrivelens_r0` exactly;
- requires a file-backed password with no repository default;
- requests SCRAM and data checksums at initialization;
- caps memory at 512 MiB and shared memory at 64 MiB;
- intends an attributable bind directory rather than an uncounted named volume and forbids automatic restart in any future generated configuration;
- accepts only `%LOCALAPPDATA%\ThriveLens\data\postgresql\compose-r0`, never the attributable root or an arbitrary subdirectory;
- requires an empty directory for initial activation, rejects pre-seeded `PGDATA`, and enforces a protected allowlisted directory ACL with current-user Modify rights;
- requires the same strict host password-file ACL and requires the password path to be outside the data directory;
- remains blocked until the integration owner accounts for engine image/layer/cache/writable-layer storage and satisfies the data inventory gate.

`validate_compose_inputs.ps1` accepts no parameters and therefore has no alternate “validated” path that a future Compose invocation could ignore. It reads the data directory, password file, administrator, database, and port exactly once from `TL_POSTGRES_COMPOSE_DATA_DIR`, `TL_POSTGRES_ADMIN_PASSWORD_FILE`, `TL_POSTGRES_ADMIN_USER`, `TL_POSTGRES_DATABASE`, and `TL_POSTGRES_PORT`. It rejects missing inputs and any case-sensitive user/database or exact-string port drift from `tl_bootstrap`, `thrivelens_r0`, and `55432`; it also preserves the exact path, ACL, disjoint-secret, resource, engine-accounting, and data-inventory gates. It unconditionally returns `COMPOSE_ACTIVATION_WRAPPER_REQUIRED`.

Any future activation wrapper requires a separate review. It must capture one immutable process-environment snapshot, validate all five values and every gate, generate a temporary runnable configuration from that same in-memory snapshot, and invoke the generated configuration within the same process flow. It must not re-read environment variables between validation and use, persist a runnable configuration in the repository, or introduce a second override surface. This same-process generation rule closes the validation/use gap; it is documented policy, not an implemented activation route.

Docker Desktop remains absent and must not be installed merely to satisfy R0. A compatible CI/developer host may validate this contract later, sequentially and under the same aggregate-resource/evidence rules.

## WSL fallback trigger

The trigger fired because the EDB archive has no publisher archive attestation. A dedicated `ThriveLens-R0` Ubuntu 24.04 WSL2 distribution is present beneath the counted root with a 6 GiB VHD ceiling. Exact PGDG PostgreSQL 17.10 packages are present from signed metadata; service units are masked and package-managed cluster creation is disabled. The upstream Ubuntu checksum is a provenance reference only: the `wsl --web-download` payload was not retained, so the current VHD is not claimed to be byte-attested by that hash. Read-only WSL controls and preflight do invoke the exact existing distro through `wsl.exe`; they do not download, install, initialize, or start PostgreSQL. The 251,000,000-byte ceiling covers only the completed PostgreSQL package transaction; distro/VHD/APT metadata are measured by the aggregate gate.

Initialization accepts only `%LOCALAPPDATA%\ThriveLens\secrets\postgres-r0-bootstrap.pw`, stages a checksum-enabled SCRAM cluster, and promotes only to `/var/lib/thrivelens/postgresql/r0`. A partial/invalid target blocks. Runtime binds `127.0.0.1:55432`, uses manual `pg_ctl`, persists no raw PostgreSQL logs, and must complete two authenticated start/stop cycles plus Windows-host reachability before verification. SQLite, PGLite, browser storage, and remote managed databases are not substitutes for R0 PostgreSQL proof.

The TL-R0-004 handoff becomes available only after TL-R0-003 is VERIFIED with the two-cycle runtime PASS. It supplies host `127.0.0.1`, port `55432`, maintenance database `postgres`, bootstrap role `tl_bootstrap`, and the protected host password-file path. TL-R0-004—not this task—creates `thrivelens_r0`, migration/runtime roles, the baseline migration, and the single migration head. Neither task may emit or retain the secret value or a DSN.

## Rollback

- Python: no mutation is permitted, so no rollback is currently required. Future enablement must define verified uninstall plus scratch/cache cleanup before review.
- Rejected Windows PostgreSQL: nothing is installed, so no rollback is currently required. If a future separately approved implementation writes bytes, stop and verify exact absence, then remove only explicitly authorized versioned binary/data/log paths beneath the attributable root and rerun the resource gate.
- Compose: nothing was pulled or started, and the checked-in descriptor has no service. A future authorized wrapper must stop/remove only the generated explicit-profile container; removal of the dedicated bind-data directory remains a separate destructive action requiring explicit authority.
- WSL: the dedicated distro, exact packages, and protected credential now exist. During first initialization only, the script may automatically delete its own unpromoted `.r0-staging-<nonce>` tree after a pre-activation failure, using the reviewed fd-relative same-mount boundary; this is bounded transaction cleanup, not cluster rollback. Once activation is attempted, staging/final state is preserved and the outcome is fatal for explicit recovery. Destructive unregister, promoted-cluster deletion, and credential deletion were not exercised or authorized. Those rollback actions require fresh human confirmation of the exact `ThriveLens-R0` target, verified process/listener absence, and pre/post resource gates; never target another distro.

## Current blockers and manual intervention

1. The PostgreSQL cluster is not initialized and the two-cycle runtime proof has not run; TL-R0-003 therefore remains unverified.
2. Python installation remains disabled because scratch/cache ceilings and counted paths are undefined.
3. Compose remains intentionally inert: no activation wrapper or runnable service exists and engine storage accounting is not configured.
4. Destructive WSL rollback is not authorized. Exact-target removal requires a separate human confirmation.
