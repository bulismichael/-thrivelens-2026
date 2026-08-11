# ThriveLens threat model

Status: initial R0 design review; not `SECURITY_REVIEWED`

## Security objectives

1. Status integrity fails closed; a fake, stale, malformed, or partial result cannot appear ready.
2. Production cannot start with demo/default credentials, debug behavior, insecure public transport, or missing required secrets.
3. Secrets, topology, stack traces, SQL, sensitive content, and identifiers do not enter client errors or ordinary logs.
4. PostgreSQL runtime authority is minimal, bounded, read-only for health, and separate from migrations.
5. Build inputs and generated clients are pinned, reproducible, scanned, and traceable.
6. R0 collects and persists no user/wellness/device data.

## R0 threat-control-test matrix

| ID | Severity | Threat | Required control | Blocking test/evidence |
|---|---|---|---|---|
| R0-T01 | CRITICAL | Production starts with demo/placeholder/empty secrets or debug | R0 production startup disabled; later one typed fail-closed configuration boundary with no shipped production defaults | R0 production-start rejection and non-disclosing config-error tests |
| R0-T02 | CRITICAL | Secret/topology/sensitive leakage in log or HTTP error | Allowlisted JSON fields; sanitized exception mapping; no body/header/DSN capture | Sentinel values injected through config, headers, query, and DB errors are absent |
| R0-T03 | HIGH | Health/version fingerprints infrastructure | Coarse closed schemas and bounded version only | Response allowlist and recursive `additionalProperties: false` test |
| R0-T04 | HIGH | Probe collects or persists data | No body/auth/device input; constant read-only queries; no probe table/cache | Before/after rows/schema unchanged across repeated probes |
| R0-T05 | HIGH | False-green while DB stopped/behind/ahead | Current-request connectivity plus exact migration head; UI fail closed | Real PostgreSQL state matrix and stale-response fencing |
| R0-T06 | HIGH | Cleartext/trust-all transport enables tampering or a widened host listener | Web HTTP only on loopback; Android debug uses `adb reverse` to host loopback and debug-only cleartext config; release rejects the debug base and has no cleartext opt-in; never use trust-all | ADB mapping/cleanup, loopback bind, debug-manifest, release-manifest/base, and certificate-policy tests |
| R0-T07 | HIGH | Compromised API can mutate schema or public DB is exposed | Separate migration/runtime roles; loopback/internal DB; runtime no DDL | Runtime probe succeeds and create/alter/drop fails |
| R0-T08 | HIGH | Status polling exhausts pool/workers | Pool and overflow bound; deadlines; no unbounded retry; optional coalescing/rate control | Unavailable/hung DB concurrency/recovery test |
| R0-T09 | HIGH | OpenAPI/client drift misinterprets state | Canonical OpenAPI, pinned generator, generated DTOs only, unknown fail closed | Regeneration produces clean diff; all fixtures compile/deserialize |
| R0-T10 | HIGH | Dependency/action/container/tool compromise | Immutable pins, locks, provenance, minimal CI permissions, secret/dependency scans | Policy tests and no critical scan finding |
| R0-T11 | MEDIUM | Caller correlation ID forges/expands logs | Server-generated or `[A-Za-z0-9._-]{1,64}`; JSON encoder | Newline/control/oversize headers replaced; bounded valid JSON |
| R0-T12 | MEDIUM | Cached/stale status or excessive version detail | `Cache-Control: no-store`; memory-only UI; explicit freshness | Header, storage-spy, and version snapshot tests |
| R0-T13 | MEDIUM | Wildcard CORS/host policy widens exposure | Local/test serves built Flutter and API from one loopback origin; no R0 CORS; reject unrelated Origin/OPTIONS; production disabled | Same-origin static-mount, Host/Origin/OPTIONS, and settings policy tests |
| R0-T14 | HIGH | Resource exhaustion breaches host/cap | Aggregate logical accounting, low-memory preflight, sequential phases, size projections | Boundary/resource/preflight tests |

Critical findings block integration. All high items require executable evidence before R0 verification.

## Mandatory future abuse cases

- Cross-user access, reviewer overreach, feature-flag privilege escalation, insecure mobile token storage.
- Malicious evidence documents, prompt injection, evidence poisoning/supersession, unsafe unsupported claims.
- Crafted image resource exhaustion, unsafe file types, metadata leakage, training without opt-in, provider retention mismatch.
- Exact route endpoint disclosure, coordinate logging, home/school/work inference, deleted queued data resurrection.
- Raw pose upload, injury diagnosis, checkpoint substitution, dependency/model compromise, unsafe promotion.
- Provider outage, production demo credentials, backup/restore leakage, deletion gaps, and secret rotation.

These scenarios remain in the risk and traceability controls but receive concrete flows/tests only when their release becomes active.

## Human gates

Privacy/legal review, retention, hosting/region, production secret management, pilot jurisdiction, security risk acceptance, and pilot authorization remain pending. This document is engineering input, not legal advice or risk acceptance.
