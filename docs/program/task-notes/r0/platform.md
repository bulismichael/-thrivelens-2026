# TL-R0-003 platform foundation

Status: **installation-free foundation complete; runtime verification blocked**

Observed: 2026-08-12

Target host: Windows x86-64, 7.87 GB physical memory, observed free memory about 0.47 GB

No artifact was downloaded, no installer or licence was accepted, no service or cluster was started, no credential was created, and WSL/Docker were not invoked while producing this note.

## Decision

Keep ADR-003's preferred path as a portable, no-service PostgreSQL candidate under the aggregate-counted `%LOCALAPPDATA%\ThriveLens` root, but do not accept or install it yet. PostgreSQL 17.10 is the current supported minor of major 17, whose upstream support runs through November 2029. Major 17 is preferred over major 18 for R0 because it retains a long support window while reducing early-major compatibility risk; this does not waive the requirement to take current 17.x security minors.

The portable archive's provenance is credible but not yet cryptographically complete. The [official PostgreSQL Windows page](https://www.postgresql.org/download/windows/) explicitly links an advanced-user binaries ZIP hosted by EDB, and the [EDB binaries page](https://www.enterprisedb.com/download-postgresql-binaries?lang=en) currently resolves Windows x86-64 version 17.10 to the artifact below. However, EDB exposes no SHA-256 or detached signature beside the ZIP. Its HTTP ETag has a multipart suffix and is not treated as a digest. A locally calculated hash after download would establish repeatability, not publisher authenticity.

Consequently, the manifest deliberately stores `null` for the PostgreSQL expected SHA-256 and the verifier fails closed. Independent security review must either approve an exact additional publisher-verification method or activate the WSL fallback. Executable Authenticode checks alone do not attest every file in the surrounding ZIP.

## Pinned artifacts and projections

| Foundation | Exact artifact | Publisher evidence | Compressed bytes | Extracted/installed acceptance ceiling | Current state |
|---|---|---|---:|---:|---|
| CPython | `python-3.13.15-amd64.exe` | [PSF release page](https://www.python.org/downloads/release/python-31315/), SHA-256 `edec09c4853aeae9ac36efb8c9f95b6b8e2fee65eee56d9767a8b7c69c574403`, [Sigstore guidance](https://www.python.org/downloads/metadata/sigstore/), PSF Authenticode | 29,452,944 | 268,435,456 bytes | Provenance pinned; not downloaded/verified/installed |
| Portable PostgreSQL | `postgresql-17.10-2-windows-x64-binaries.zip` | Official-page-linked EDB HTTPS artifact; Content-Length 333,927,270; Last-Modified `Thu, 11 Jun 2026 12:28:18 GMT`; no published digest/signature | 333,927,270 | Binary 805,306,368 bytes; initial cluster 134,217,728; synthetic backup 67,108,864; total below 1,006,632,960 | Integrity blocked; not downloaded/installed |
| Compose PostgreSQL | `postgres:17.10-bookworm@sha256:9b18b78397054fce88a9552e9d5a3ad5bb7fd258c5b3cc1c5028e46373d6ea8f` | [Docker Official Images source of truth](https://github.com/docker-library/official-images/blob/master/library/postgres); registry index and amd64 manifest metadata | 156,095,657 amd64 layer bytes | 536,870,912 runtime bytes | Contract pinned; image not pulled |

The PostgreSQL ceilings are rejection thresholds, not measured results. They reserve at most 768 MiB for binaries, 128 MiB for the initial R0 cluster, and 64 MiB for one synthetic backup, keeping the PostgreSQL allocation below the ADR's 1 GB target. The Python 256 MiB installed ceiling is likewise a pre-install budget, not a claimed measurement. Actual extracted/installed bytes must be recorded immediately after provisioning. Retained installers also count toward the aggregate footprint.

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
- any unavailable memory measurement, inactive resource phase, failed aggregate gate, unverified archive, absent binary, or absent cluster is blocking;
- cleanup/stop remains available when memory is low;
- no script downloads from the network, modifies machine `PATH`, registers a Windows service, invokes WSL/sudo, starts Docker, or creates a default password.

Portable initialization uses PostgreSQL's documented `--pwfile`, `--auth-host=scram-sha-256`, `--auth-local=scram-sha-256`, and `--data-checksums` controls. PostgreSQL warns that `trust` is the easy-install default, so the script never uses it. Start uses `pg_ctl` with a 30-second wait, low-memory settings, and command-line server overrides binding only `127.0.0.1:55432`. Stop uses bounded `fast` shutdown. See the upstream [`initdb`](https://www.postgresql.org/docs/17/app-initdb.html) and [`pg_ctl`](https://www.postgresql.org/docs/17/app-pg-ctl.html) references.

## Compose boundary

`infra/compose.yaml` is PostgreSQL-only. It has no API, proxy, admin UI, observability stack, or application dependency. It:

- pins the Docker Official Image index digest and records the linux/amd64 manifest digest in the backend manifest;
- binds only `127.0.0.1:${TL_POSTGRES_PORT:-55432}:5432`;
- requires a file-backed password with no repository default;
- requests SCRAM and data checksums at initialization;
- caps memory at 512 MiB and shared memory at 64 MiB;
- uses a named volume and `restart: "no"` so teardown is explicit.

Docker Desktop remains absent and must not be installed merely to satisfy R0. A compatible CI/developer host may validate this contract later, sequentially and under the same aggregate-resource/evidence rules.

## WSL fallback trigger

The fallback trigger fires if any of these remains true at the provisioning gate:

1. independent security review does not accept a complete publisher-verification method for the EDB ZIP;
2. expected signed executables fail Authenticode or the archive layout/version differs;
3. the extracted binary exceeds 805,306,368 bytes or total PostgreSQL allocation cannot remain below 1,006,632,960 bytes;
4. portable PostgreSQL cannot initialize, bind only to loopback, start, answer `pg_isready`, and stop cleanly.

WSL is **not activated**. Activation requires human authority for the system/package change and a reviewed resource-policy update that accounts for attributable WSL package, cluster, and backup bytes before `sudo`, package installation, or data creation. The same SCRAM, checksums, loopback, memory, size, real-runtime, and rollback gates apply. SQLite, PGLite, browser storage, and a remote managed database are not substitutes for R0 PostgreSQL proof.

## Rollback

- Python: use the same verified installer with `/uninstall /quiet`, verify the dedicated version root is gone, then rerun the resource gate. The scripted install does not change machine `PATH` or install a global launcher.
- Portable PostgreSQL: invoke `stop.ps1`; confirm the dedicated cluster is stopped; after explicit deletion authority, remove only the versioned binary/data/log directories beneath the attributable root; rerun the resource gate. Never target another PostgreSQL installation or the entire local application-data root.
- Compose: `docker compose down` stops/removes the container while retaining the named data volume. Volume deletion is a separate destructive action requiring explicit authority.
- WSL: no rollback exists yet because no WSL change was made.

## Current blockers and manual intervention

1. Free memory is about 0.47 GB, below both fail-closed floors. The user must close memory-heavy applications before any install or runtime attempt.
2. `config/resource-budget.json` remains `prebootstrap`; root integration must make the exact phase-only change above.
3. The EDB archive lacks a publisher SHA-256/detached signature. Security/integration review must disposition this or choose the WSL fallback before download.
4. PostgreSQL binaries and cluster do not exist, so `preflight.ps1` and `test_runtime.ps1` must remain red/blocked. This is truthful missing-runtime evidence, not a skipped or passed PostgreSQL test.
