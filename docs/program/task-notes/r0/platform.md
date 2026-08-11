# TL-R0-003 platform foundation

Status: **Windows PostgreSQL rejected; WSL fallback required but not activated**

Observed: 2026-08-12

Target host: Windows x86-64, 7.87 GB physical memory, observed free memory about 0.47 GB

No artifact was downloaded, no installer or licence was accepted, no service or cluster was started, no credential was created, and WSL/Docker were not invoked while producing this note.

## Decision

Reject the EDB portable Windows archive for ThriveLens runtime use. PostgreSQL 17.10 remains the exact supported R0 version target, but the [official PostgreSQL Windows page](https://www.postgresql.org/download/windows/) links to an EDB-hosted advanced-user ZIP for which the [EDB binaries page](https://www.enterprisedb.com/download-postgresql-binaries?lang=en) publishes neither an archive SHA-256 nor a detached signature. Its HTTP ETag has a multipart suffix and is metadata, not a digest. A local post-download hash would prove repeatability only; signatures on selected extracted executables cannot attest the complete archive.

The manifest therefore stores `null` for the archive digest, marks the portable candidate `REJECTED_FOR_RUNTIME`, and hard-disables its installer. The EDB interactive Windows installer is also `HARD_DISABLED`; it is not an alternate route around the archive decision. No Windows PostgreSQL artifact should be downloaded or accepted under TL-R0-003.

The ADR-003 fallback is now **required but not activated**. WSL activation needs explicit human system authority, distribution-signed repository metadata plus an exact supported PostgreSQL package pin, and a dedicated ThriveLens WSL storage location added to aggregate accounting before any package or cluster byte is written. This task does not invoke WSL, `sudo`, package managers, Docker, or services.

## Pinned artifacts and projections

| Foundation | Exact artifact | Publisher evidence | Compressed bytes | Extracted/installed acceptance ceiling | Current state |
|---|---|---|---:|---:|---|
| CPython | `python-3.13.15-amd64.exe` | [PSF release page](https://www.python.org/downloads/release/python-31315/), SHA-256 `edec09c4853aeae9ac36efb8c9f95b6b8e2fee65eee56d9767a8b7c69c574403`, [Sigstore guidance](https://www.python.org/downloads/metadata/sigstore/), PSF Authenticode | 29,452,944 | 268,435,456 bytes | SHA-256 and Authenticode enforcement specified; Sigstore bundle recorded but not enforced; not downloaded/installed |
| Portable PostgreSQL | `postgresql-17.10-2-windows-x64-binaries.zip` | Official-page-linked EDB HTTPS artifact; Content-Length 333,927,270; Last-Modified `Thu, 11 Jun 2026 12:28:18 GMT`; no published digest/signature | 333,927,270 | Binary 805,306,368 bytes; initial cluster 134,217,728; synthetic backup 67,108,864; total below 1,006,632,960 | **Rejected for runtime**; download/install disabled |
| Compose PostgreSQL | `postgres:17.10-bookworm@sha256:6e5a6518f9d2ff9e9f4cba2a5a87d8f41b0f067f6f92ac847c344351a6c8d923` | [Docker Official Images source of truth](https://github.com/docker-library/official-images/blob/master/library/postgres); linux/amd64 child manifest | 156,095,657 amd64 layer bytes | 536,870,912 runtime plus 134,217,728 data bytes | Default-disabled contract; engine accounting absent; image not pulled |

The ceilings are rejection thresholds, not measured results. Python's retained-artifact-plus-install projection is 297,888,400 bytes. PostgreSQL's rejected Windows-artifact-plus-total projection is 1,340,560,230 bytes, including the 128 MiB initial-cluster ceiling. The combined worst-case backend projection is 1,638,448,630 bytes. Before mutation, scripts add the applicable projection to currently accounted bytes, reject a result at or above 85% or 18 GiB, and require the projection plus a 512 MiB free-disk reserve. Extracted/installed trees are rescanned without following reparse points, and all mutation outcomes run a post-resource gate.

Licences are [PSF License Version 2](https://docs.python.org/3/license.html) for CPython and the [PostgreSQL License](https://www.postgresql.org/about/licence/) for PostgreSQL. The EDB archive and Docker image may contain separately licensed dependencies; their bundled inventories remain pending because neither artifact was fetched. No licence approval is inferred from documenting them.

## Resource and execution contract

Root integration must make this exact integration-owned change before any backend/Flutter installation:

```json
"phase": "bootstrap_active"
```

Every other field in `config/resource-budget.json` remains unchanged. This makes the single configured `%LOCALAPPDATA%\ThriveLens` root required, so the repository, worktrees, downloads, SDKs, caches, runtime data, and evidence remain aggregate-counted.

The preflight is intentionally stricter than the global warning:

- install: minimum 2,147,483,648 free bytes;
- PostgreSQL initialize/runtime: minimum 1,073,741,824 free bytes;
- any unavailable memory/disk measurement, inactive resource phase, failed aggregate gate, rejected Windows runtime, inactive WSL fallback, absent binary, or absent cluster is blocking;
- exact projected bytes must remain below both the 85% high-water mark and the 18 GiB cap before any filesystem mutation;
- ZIP central-directory entry count, normalized containment, duplicate/case-collision paths, link/reparse flags, and summed uncompressed bytes are checked before any dormant extraction path; the extracted tree is then rescanned without following links;
- every existing component of the attributable binary/data/log/executable path is checked for reparse points;
- cleanup/stop remains available when memory is low;
- no script downloads from the network, modifies machine `PATH`, registers a Windows service, invokes WSL/sudo, starts Docker, or creates a default password.

Before any future PostgreSQL initialization, the integration owner must add the cluster's persisted fields to `docs/privacy/DATA_INVENTORY.md`. That update is mandatory and intentionally remains unsatisfied because the privacy inventory is outside TL-R0-003 ownership. Initialization also requires a password file beneath the attributable root with inheritance disabled and read access limited to the current user, LocalSystem, and BUILTIN Administrators.

The dormant initialization contract uses PostgreSQL's documented `--pwfile`, `--auth-host=scram-sha-256`, `--auth-local=scram-sha-256`, and `--data-checksums` controls. Start checks exact output from all four pinned tools, uses `pg_ctl` with a 30-second wait and binds only `127.0.0.1:55432`. Any post-start failure triggers bounded cleanup. Stop can report `STOPPED` or `ALREADY_STOPPED` only after exact binary-process and dedicated-port listener absence. The runtime test stops and verifies absence before PASS. See upstream [`initdb`](https://www.postgresql.org/docs/17/app-initdb.html) and [`pg_ctl`](https://www.postgresql.org/docs/17/app-pg-ctl.html).

## Compose boundary

`infra/compose.yaml` is PostgreSQL-only. It has no API, proxy, admin UI, observability stack, or application dependency. It:

- is disabled by default behind the explicit `postgres-explicit` profile;
- fixes `platform: linux/amd64` and pins its child manifest digest rather than only the multi-platform index;
- binds only `127.0.0.1:${TL_POSTGRES_PORT:-55432}:5432`;
- requires a file-backed password with no repository default;
- requests SCRAM and data checksums at initialization;
- caps memory at 512 MiB and shared memory at 64 MiB;
- uses an attributable bind directory rather than an uncounted named volume and keeps `restart: "no"`;
- requires the same strict host password-file ACL;
- remains blocked until the integration owner accounts for engine image/layer/cache/writable-layer storage and satisfies the data inventory gate.

Docker Desktop remains absent and must not be installed merely to satisfy R0. A compatible CI/developer host may validate this contract later, sequentially and under the same aggregate-resource/evidence rules.

## WSL fallback trigger

The trigger has fired because the EDB archive has no publisher archive attestation. WSL is **required but not activated**. Activation requires human authority for the system/package change, verification of distribution-signed repository metadata, an exact supported PostgreSQL package pin, and dedicated WSL package/cluster/backup storage added to aggregate accounting before `sudo`, package installation, or data creation. The same SCRAM, checksums, loopback, memory, size, real-runtime, and rollback gates apply. SQLite, PGLite, browser storage, and a remote managed database are not substitutes for R0 PostgreSQL proof.

## Rollback

- Python: use the same verified installer with `/uninstall /quiet`, verify the dedicated version root is gone, then rerun the resource gate. The scripted install does not change machine `PATH` or install a global launcher.
- Rejected Windows PostgreSQL: nothing is installed, so no rollback is currently required. If a future separately approved implementation writes bytes, stop and verify exact absence, then remove only explicitly authorized versioned binary/data/log paths beneath the attributable root and rerun the resource gate.
- Compose: nothing was pulled or started. On a future authorized host, stop/remove only the explicit-profile container; removal of the dedicated bind-data directory remains a separate destructive action requiring explicit authority.
- WSL: no rollback exists yet because no WSL change was made.

## Current blockers and manual intervention

1. Free memory is about 0.47 GB, below both fail-closed floors. The user must close memory-heavy applications before any install or runtime attempt.
2. `config/resource-budget.json` remains `prebootstrap`; root integration must make the exact phase-only change above.
3. The EDB archive is rejected and both Windows provisioning routes are hard-disabled. WSL is required, but only a human with system authority may activate it after signed exact-package pinning and dedicated counted-storage design.
4. `docs/privacy/DATA_INVENTORY.md` must be updated by its integration owner before initialization; TL-R0-003 does not own that path.
5. Compose engine storage accounting is not configured and its explicit-profile validator remains blocked.
6. PostgreSQL binaries and cluster do not exist, so `preflight.ps1` and `test_runtime.ps1` must remain red/blocked. This is truthful missing-runtime evidence, not a skipped or passed PostgreSQL test.
