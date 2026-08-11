# TL-R0-002 frozen heartbeat contract

Status: implementation candidate; independent review and integration evidence remain required.

## Boundary

The canonical OpenAPI document is `contracts/openapi/r0-heartbeat.openapi.json`. Its only server is the relative `/api/v1` base. Combining that base with the four path items produces exactly:

- `GET /api/v1/health/live`
- `GET /api/v1/health/ready`
- `GET /api/v1/system/status`
- `GET /api/v1/system/version`

No operation accepts a body, query, identity, token, device identifier, or wellness data. The only optional request input is `X-Correlation-ID`; a matching bounded value may be propagated, while invalid, control-bearing, or oversized input is replaced. Every operation is anonymous and read-only in R0 local/test/demo mode. There is no permissive default response. R0 production startup remains disabled.

## Truth table

| Current request evidence | Liveness | Readiness | Mobile status |
|---|---|---|---|
| API answers; database reachable and at exact expected head | `200 alive` without a database call | `200 ready`, database `ready` | `200 available`, app `available`, database `ready` |
| API answers; database unreachable or readable but non-current | `200 alive` without a database call | structured `503 not_ready`, database `not_ready` | `200 degraded`, app `available`, database `not_ready` |
| API answers; bounded probe is exhausted or cancelled | `200 alive` without a database call | structured `503 not_ready`, database `unknown` | `200 degraded`, app `available`, database `unknown` |
| A completed negative database check | unchanged | structured `503`, never an unstructured exception | `200 degraded` only with typed database `not_ready` or `unknown` |
| Unexpected framework/application failure | structured redacted `500` | structured redacted `500`, never a lying database-negative result | never converted into degraded `200` or ready |

An earlier success cannot be reused as current evidence. Version failure is non-blocking for a valid current status result. The version body contains only the API contract version and bounded service semantic version; it contains no dependency version, host, path, commit, or topology.

Every defined response carries JSON content type, `Cache-Control: no-store`, and an `X-Correlation-ID` matching `[A-Za-z0-9._-]{1,64}`. Invalid, control-bearing, or oversized caller values must be replaced rather than echoed. For an error response, the response header and error-body `correlation_id` are identical. Error bodies are validated against their exact canonical schema, not a selected field subset. They cannot carry exception, SQL, driver, DSN, hostname, absolute path, stack, request header, or request body detail. Status timestamps use the exact 20-byte UTC `YYYY-MM-DDTHH:MM:SSZ` form and must also parse as real calendar date-times; shape-matching impossible dates or times are invalid.

The single allowlisted operational completion event is exactly `{event: r0_heartbeat_request, outcome: success|degraded|error|rejected, correlation_id}`. Exactly one such event is required for successful, degraded, unexpected-error, rejected-Host, rejected-Origin, and other rejected-request completions. It contains no endpoint or exact route, Host, Origin, client address, request headers/body/query, database detail, exception, SQL, DSN, path, dependency version, or user/device value. Capturing that event is not a product audit record or probe-history store.

## Browser and Android transport

Local/test Flutter web uses relative `/api/v1`. FastAPI must serve both the configured built/static fixture and API from one `127.0.0.1:8000` origin. Only `127.0.0.1`, `127.0.0.1:8000`, `localhost`, and `localhost:8000` Host forms are accepted; any forwarded Host is rejected. When `Origin` exists it must pair by host family and port: `http://127.0.0.1:8000` with the numeric loopback Host family or `http://localhost:8000` with the localhost family. Two independently allowlisted but mismatched loopback values, scheme/port changes, `null`, and unrelated origins are rejected. R0 has no CORS middleware or `Access-Control-Allow-Origin`; same-origin or absent `Origin` is accepted, and `OPTIONS` returns a closed structured `405` rather than becoming a permissive preflight. Host (`400`), Origin (`403`), and method (`405`) rejections are no-store, correlated, structured, redacted, and contain no CORS allow header. A single-page-app fallback must never swallow an unknown `/api/v1/*` route.

Android debug selects one device and creates exactly `adb -s <serial> reverse tcp:8000 tcp:8000`. The wrapper accepts only a 1..128 character serial matching `[A-Za-z0-9._:][A-Za-z0-9._:-]{0,127}`; a leading option, whitespace, control character, or shell metacharacter is rejected before either ADB or the probe can run. Cleanup removes only that mapping with `adb -s <serial> reverse --remove tcp:8000`, including mapping, probe, failure, and interruption paths. The wrapper passes exactly `--base-url http://127.0.0.1:8000/api/v1 --mode debug` to the heartbeat probe; host FastAPI remains on loopback. Android Network Security Configuration is a closed tree with one empty `base-config cleartextTrafficPermitted=false` and one non-subdomain `127.0.0.1` debug exception; it contains no debug override, custom trust anchor, certificate, extra domain, or nested configuration. The provisional R0 engineering minimum is Android 10 / API 29, where Network Security Configuration controls cleartext; TL-D-013 and the human-approved device-support matrix remain pending. The debug manifest flag exists for Android integration tooling but must not be treated as a general-host exception. Release has no cleartext opt-in, rejects the debug base, and remains production-disabled. `0.0.0.0`, LAN addresses, `10.0.2.2`, trust-all certificates, `reverse --remove-all`, and browser-only substitution are forbidden.

## Expected-red handoff

`tests/contracts/expected-red.json` freezes eight named executable semantic acceptance tests owned by this contract task. Each test first checks one exact future implementation artifact and emits only its own bounded missing-implementation marker while that artifact is absent. Once present, the same unchanged assertion exercises actual response, ASGI, Android manifest, or wrapper behavior. Downstream tasks supply implementation but do not own or replace the assertions that decide green. The manifest uses argument arrays rather than shell command text.

| Owner | Frozen acceptance responsibility | Exact future closure command |
|---|---|---|
| `TL-R0-005` | Five tests over the actual `thrivelens_api.main.create_app` ASGI surface: DB-independent live, ready/status/error matrix, headers/correlation/redaction, same-origin/Host/Origin/OPTIONS/static boundary, and production rejection | `pwsh -NoProfile -File scripts/contracts/assert_expected_green.ps1 -Manifest tests/contracts/expected-red.json -Owner TL-R0-005` |
| `TL-R0-008` | Three tests over actual Android artifacts and wrapper: exact selected-device ADB reverse plus failure cleanup, loopback-scoped debug cleartext, and release/production negatives | `pwsh -NoProfile -File scripts/contracts/assert_expected_green.ps1 -Manifest tests/contracts/expected-red.json -Owner TL-R0-008` |

The TL-R0-005 injection seam is exact: `services/api/src/thrivelens_api/main.py` exports `create_app(*, mode, database_probe, static_root, correlation_id_factory, log_sink)`. The asynchronous zero-argument `database_probe` returns exactly `ready`, `not_ready`, or `unknown`; raising represents an unexpected failure. `log_sink` receives the exact allowlisted event above so sentinel redaction can be tested without scraping or persisting logs. Tests call the returned real ASGI application directly and validate full bodies through the canonical schemas. These seams inject dependency evidence and capture only; they do not provide a second transport model or bypass middleware/routes.

The TL-R0-008 wrapper seam is exact: `scripts/mobile/verify_android_surface.ps1` accepts explicit `-DeviceSerial`, `-AdbPath`, and `-HeartbeatProbePath` arguments and enforces the serial rule itself before invoking either executable. It invokes the chosen executables without shell-built command text, creates the exact mapping, runs the probe with the exact base/mode arguments above, propagates mapping/probe failure, and removes only that mapping in `finally`. Ordinary execution may default the executable/probe but may never make device selection optional. Release-negative tests scan Android main/release inputs plus shipped Flutter `lib`, assets, and `pubspec.yaml`; every regular file, including extensionless, dotfile, text/config, and binary content, is read as raw bounded chunks. Reparse points are rejected, the scan is capped at 8,192 entries, 16 MiB per file, and 128 MiB aggregate, and the debug base or release cleartext opt-in cannot be embedded in a shared source/config asset that enters the APK. `scripts/mobile/build_android.ps1 -Mode Release -PolicyCheckOnly` performs no build and emits only the closed JSON object `{mode: release, minimum_android_api: 29, production_enabled: false, cleartext_allowed: false, debug_base_url_allowed: false}` after checking the shared release inputs. The same policy-only command must fail nonzero when `THRIVELENS_API_BASE_URL` contains the debug loopback base or `THRIVELENS_PRODUCTION_ENABLED=true`; a hard-coded safe report that ignores unsafe build input is not green.

The red harness succeeds only for collected named tests that fail at their explicit missing-implementation assertion. Passing, skipping, expected-failure, zero collection, wrong failure, import/syntax/tool failure, crash, timeout, marker spoofing, output above the strict 65,536 combined-byte cap, unsafe termination, or partial owner execution fails. Output is streamed while the child runs. Timeout or output excess triggers process-tree termination and only bounded post-termination drain; a termination failure fails closed without awaiting an incomplete read indefinitely. The green harness uses the unchanged manifest and succeeds only when every entry for the requested owner is collected and exits zero without skip or red markers.

The three TL-R0-008 expected-red IDs close transport construction, cleanup, manifest policy, and release-policy inputs only. They do not claim a real device ready/degraded heartbeat. That remains a separate mandatory TL-R0-008 closure through its immutable `verify_android_surface.ps1` and `test_r0_heartbeat.ps1 -Surface Android` commands plus task-scoped device evidence; browser proof cannot substitute for it.

`SystemStatusResponse` intentionally uses a closed `oneOf` so impossible `available`/database-negative combinations cannot be generated or parsed as valid. TL-R0-006 must verify the pinned Dart generator handles this union, deserialize every canonical fixture, and prove regeneration has zero drift. A generator limitation requires an explicit reviewed contract decision; it must not be worked around by weakening the union.

## Idempotency, persistence, and rollback

All four calls are safe, read-only, and idempotent. They create no product row, probe-history row, audit record, analytics event, user/device identity, mobile queue, or persistent cache. Rollback is a normal revert of the contract commit; downstream generated clients must be regenerated and reviewed for any later breaking change.
