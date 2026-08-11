from __future__ import annotations

import asyncio
import importlib
import json
import re
import sys
import unittest
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from scripts.contracts.contract_validation import OPENAPI_PATH, load_json, validate_instance


SOURCE_ROOT = REPOSITORY_ROOT / "services" / "api" / "src"
IMPLEMENTATION_FILE = SOURCE_ROOT / "thrivelens_api" / "main.py"
STATIC_ROOT = REPOSITORY_ROOT / "tests" / "contracts" / "fixtures" / "static"
SERVER_CORRELATION_ID = "server-generated-id"
SENSITIVE_CANARY = "TL_SENSITIVE_CANARY_7F3A"
OPENAPI_DOCUMENT = load_json(OPENAPI_PATH)


@dataclass
class _Probe:
    result: str = "ready"
    failure: Exception | None = None
    calls: int = 0

    async def __call__(self) -> str:
        self.calls += 1
        if self.failure is not None:
            raise self.failure
        return self.result


def _load_factory(test_case: unittest.TestCase, marker: str) -> Callable[..., Any]:
    if not IMPLEMENTATION_FILE.is_file():
        test_case.fail(marker)
    if str(SOURCE_ROOT) not in sys.path:
        sys.path.insert(0, str(SOURCE_ROOT))
    importlib.invalidate_caches()
    module = importlib.import_module("thrivelens_api.main")
    factory = getattr(module, "create_app", None)
    test_case.assertTrue(callable(factory), "thrivelens_api.main.create_app must be callable")
    return factory


def _app(
    factory: Callable[..., Any],
    probe: _Probe,
    mode: str = "test",
    log_sink: Callable[[dict[str, str]], None] | None = None,
) -> Any:
    return factory(
        mode=mode,
        database_probe=probe,
        static_root=STATIC_ROOT,
        correlation_id_factory=lambda: SERVER_CORRELATION_ID,
        log_sink=log_sink,
    )


async def _asgi_request_async(
    app: Any,
    method: str,
    path: str,
    headers: dict[str, str] | None = None,
    query_string: bytes = b"",
    body: bytes = b"",
) -> tuple[int, dict[str, str], bytes]:
    request_headers = {"host": "127.0.0.1:8000"}
    request_headers.update(headers or {})
    events: list[dict[str, Any]] = []
    request_sent = False

    async def receive() -> dict[str, Any]:
        nonlocal request_sent
        if not request_sent:
            request_sent = True
            return {"type": "http.request", "body": body, "more_body": False}
        return {"type": "http.disconnect"}

    async def send(message: dict[str, Any]) -> None:
        events.append(message)

    scope = {
        "type": "http",
        "asgi": {"version": "3.0", "spec_version": "2.3"},
        "http_version": "1.1",
        "method": method,
        "scheme": "http",
        "path": path,
        "raw_path": path.encode("ascii"),
        "query_string": query_string,
        "root_path": "",
        "headers": [(key.lower().encode("ascii"), value.encode("utf-8")) for key, value in request_headers.items()],
        "client": ("127.0.0.1", 41000),
        "server": ("127.0.0.1", 8000),
        "state": {},
    }
    await app(scope, receive, send)
    start = next(event for event in events if event["type"] == "http.response.start")
    body = b"".join(event.get("body", b"") for event in events if event["type"] == "http.response.body")
    response_headers = {
        key.decode("latin-1").lower(): value.decode("latin-1") for key, value in start["headers"]
    }
    return start["status"], response_headers, body


def _request(
    app: Any,
    method: str,
    path: str,
    headers: dict[str, str] | None = None,
    query_string: bytes = b"",
    body: bytes = b"",
) -> tuple[int, dict[str, str], bytes]:
    return asyncio.run(_asgi_request_async(app, method, path, headers, query_string, body))


def _json(body: bytes) -> dict[str, Any]:
    value = json.loads(body.decode("utf-8"))
    if not isinstance(value, dict):
        raise AssertionError("response body must be a JSON object")
    return value


class BackendHeartbeatAcceptanceTests(unittest.TestCase):
    def assert_one_safe_log_event(
        self,
        captured_events: list[dict[str, str]],
        expected_outcome: str,
    ) -> None:
        self.assertEqual(
            captured_events,
            [
                {
                    "event": "r0_heartbeat_request",
                    "outcome": expected_outcome,
                    "correlation_id": SERVER_CORRELATION_ID,
                }
            ],
        )
        serialized = json.dumps(captured_events, sort_keys=True).lower()
        self.assertNotIn(SENSITIVE_CANARY.lower(), serialized)
        for forbidden_field in (
            "authorization",
            "x-private-value",
            "bearer",
            "headers",
            "query",
            "body",
            "route",
            "path",
            "exception",
            "host",
            "origin",
        ):
            self.assertNotIn(forbidden_field, serialized)

    def assert_contract_json(
        self,
        status: int,
        headers: dict[str, str],
        body: bytes,
        expected_status: int,
        schema_ref: str,
    ) -> dict[str, Any]:
        self.assertEqual(status, expected_status)
        self.assertRegex(headers.get("content-type", ""), r"^application/json(?:;\s*charset=utf-8)?$")
        self.assertEqual(headers.get("cache-control"), "no-store")
        correlation = headers.get("x-correlation-id", "")
        self.assertRegex(correlation, r"^[A-Za-z0-9._-]{1,64}$")
        payload = _json(body)
        self.assertEqual(
            validate_instance(OPENAPI_DOCUMENT, {"$ref": schema_ref}, payload),
            [],
        )
        if "error" in payload:
            self.assertEqual(payload["error"]["correlation_id"], correlation)
        return payload

    def test_liveness_never_invokes_database_probe(self) -> None:
        marker = "THRIVELENS_MISSING_IMPLEMENTATION::TL-R0-005-LIVENESS-DB-INDEPENDENCE"
        factory = _load_factory(self, marker)
        probe = _Probe(failure=RuntimeError("SENTINEL_DB_MUST_NOT_RUN"))
        status, headers, body = _request(_app(factory, probe), "GET", "/api/v1/health/live")
        payload = self.assert_contract_json(
            status,
            headers,
            body,
            200,
            "#/components/schemas/LivenessResponse",
        )
        self.assertEqual(payload, {"status": "alive"})
        self.assertEqual(probe.calls, 0)

    def test_readiness_and_mobile_status_truth_matrix(self) -> None:
        marker = "THRIVELENS_MISSING_IMPLEMENTATION::TL-R0-005-READINESS-STATUS-MATRIX"
        factory = _load_factory(self, marker)
        cases = {
            "ready": (200, {"status": "ready", "database": "ready"}, "available", None),
            "not_ready": (
                503,
                {"status": "not_ready", "database": "not_ready"},
                "degraded",
                "DATABASE_NOT_READY",
            ),
            "unknown": (
                503,
                {"status": "not_ready", "database": "unknown"},
                "degraded",
                "DATABASE_STATUS_UNKNOWN",
            ),
        }
        for state, (ready_code, ready_subset, overall, error_code) in cases.items():
            with self.subTest(state=state):
                ready_probe = _Probe(result=state)
                ready_status, ready_headers, ready_body = _request(
                    _app(factory, ready_probe), "GET", "/api/v1/health/ready"
                )
                ready_schema = (
                    "#/components/schemas/ReadinessReadyResponse"
                    if state == "ready"
                    else "#/components/schemas/ReadinessUnavailableResponse"
                )
                ready_json = self.assert_contract_json(
                    ready_status,
                    ready_headers,
                    ready_body,
                    ready_code,
                    ready_schema,
                )
                self.assertEqual(
                    {key: ready_json[key] for key in ("status", "database")},
                    ready_subset,
                )
                if error_code is None:
                    self.assertEqual(set(ready_json), {"status", "database"})
                else:
                    self.assertEqual(set(ready_json), {"status", "database", "error"})
                    self.assertEqual(ready_json["error"]["code"], error_code)
                    self.assertEqual(
                        set(ready_json["error"]),
                        {"code", "message", "correlation_id"},
                    )
                status_probe = _Probe(result=state)
                mobile_status, mobile_headers, mobile_body = _request(
                    _app(factory, status_probe), "GET", "/api/v1/system/status"
                )
                mobile_json = self.assert_contract_json(
                    mobile_status,
                    mobile_headers,
                    mobile_body,
                    200,
                    "#/components/schemas/SystemStatusResponse",
                )
                self.assertEqual(mobile_json["status"], overall)
                self.assertEqual(set(mobile_json), {"status", "components", "checked_at"})
                self.assertEqual(set(mobile_json["components"]), {"app_service", "database"})
                self.assertEqual(mobile_json["components"]["app_service"], "available")
                self.assertEqual(mobile_json["components"]["database"], state)
                self.assertRegex(mobile_json["checked_at"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        for path in ("/api/v1/health/ready", "/api/v1/system/status"):
            failure_probe = _Probe(failure=RuntimeError("SENTINEL_UNEXPECTED_DATABASE_FAILURE"))
            failure_status, failure_headers, failure_body = _request(
                _app(factory, failure_probe), "GET", path
            )
            failure_json = self.assert_contract_json(
                failure_status,
                failure_headers,
                failure_body,
                500,
                "#/components/schemas/InternalErrorResponse",
            )
            self.assertEqual(failure_json["error"]["code"], "INTERNAL_ERROR")
        current_probe = _Probe(result="ready")
        current_app = _app(factory, current_probe)
        first_status, first_headers, first_body = _request(
            current_app, "GET", "/api/v1/system/status"
        )
        first_json = self.assert_contract_json(
            first_status,
            first_headers,
            first_body,
            200,
            "#/components/schemas/SystemStatusResponse",
        )
        self.assertEqual(first_json["status"], "available")
        current_probe.result = "not_ready"
        second_status, second_headers, second_body = _request(
            current_app, "GET", "/api/v1/system/status"
        )
        second_json = self.assert_contract_json(
            second_status,
            second_headers,
            second_body,
            200,
            "#/components/schemas/SystemStatusResponse",
        )
        self.assertEqual(second_json["status"], "degraded")
        self.assertEqual(second_json["components"]["database"], "not_ready")
        self.assertEqual(current_probe.calls, 2)
        version_status, version_headers, version_body = _request(
            _app(factory, _Probe()), "GET", "/api/v1/system/version"
        )
        version = self.assert_contract_json(
            version_status,
            version_headers,
            version_body,
            200,
            "#/components/schemas/SystemVersionResponse",
        )
        self.assertEqual(set(version), {"api_version", "service_version"})
        self.assertEqual(version["api_version"], "v1")
        self.assertRegex(version["service_version"], r"^[0-9]+\.[0-9]+\.[0-9]+$")

    def test_headers_correlation_and_error_redaction(self) -> None:
        marker = "THRIVELENS_MISSING_IMPLEMENTATION::TL-R0-005-HEADERS-CORRELATION-REDACTION"
        factory = _load_factory(self, marker)
        valid = "caller.valid-1"
        valid_status, valid_headers, valid_body = _request(
            _app(factory, _Probe()),
            "GET",
            "/api/v1/health/live",
            {"x-correlation-id": valid},
        )
        self.assert_contract_json(
            valid_status,
            valid_headers,
            valid_body,
            200,
            "#/components/schemas/LivenessResponse",
        )
        self.assertEqual(valid_headers.get("x-correlation-id"), valid)
        invalid_values = ("line\nbreak", "x" * 65, "unsafe space")
        for invalid in invalid_values:
            with self.subTest(invalid=repr(invalid)):
                status, headers, body = _request(
                    _app(factory, _Probe(result="not_ready")),
                    "GET",
                    "/api/v1/health/ready",
                    {"x-correlation-id": invalid},
                )
                payload = self.assert_contract_json(
                    status,
                    headers,
                    body,
                    503,
                    "#/components/schemas/ReadinessUnavailableResponse",
                )
                self.assertEqual(headers.get("x-correlation-id"), SERVER_CORRELATION_ID)
                self.assertEqual(payload["error"]["correlation_id"], SERVER_CORRELATION_ID)
        sentinel = SENSITIVE_CANARY
        status, headers, body = _request(
            _app(factory, _Probe(failure=RuntimeError(sentinel))),
            "GET",
            "/api/v1/system/status",
        )
        self.assert_contract_json(
            status,
            headers,
            body,
            500,
            "#/components/schemas/InternalErrorResponse",
        )
        self.assertNotIn(SENSITIVE_CANARY.encode("ascii"), body)

        cases = (
            (
                "success",
                _Probe(),
                "GET",
                "/api/v1/health/live",
                {},
                200,
                "#/components/schemas/LivenessResponse",
                "success",
            ),
            (
                "degraded",
                _Probe(result="not_ready"),
                "GET",
                "/api/v1/system/status",
                {},
                200,
                "#/components/schemas/SystemStatusResponse",
                "degraded",
            ),
            (
                "unexpected error",
                _Probe(failure=RuntimeError(SENSITIVE_CANARY)),
                "GET",
                "/api/v1/system/status",
                {},
                500,
                "#/components/schemas/InternalErrorResponse",
                "error",
            ),
            (
                "rejected host",
                _Probe(),
                "GET",
                "/api/v1/health/live",
                {"host": f"{SENSITIVE_CANARY}.invalid"},
                400,
                "#/components/schemas/RequestRejectedResponse",
                "rejected",
            ),
            (
                "rejected origin",
                _Probe(),
                "GET",
                "/api/v1/health/live",
                {"origin": f"https://{SENSITIVE_CANARY}.invalid"},
                403,
                "#/components/schemas/RequestRejectedResponse",
                "rejected",
            ),
            (
                "rejected request route",
                _Probe(),
                "GET",
                f"/api/v1/{SENSITIVE_CANARY}",
                {},
                404,
                "#/components/schemas/RequestRejectedResponse",
                "rejected",
            ),
        )
        sensitive_query = f"private={SENSITIVE_CANARY}".encode("ascii")
        sensitive_body = f'{{"private":"{SENSITIVE_CANARY}"}}'.encode("ascii")
        for (
            label,
            probe,
            method,
            path,
            case_headers,
            expected_status,
            schema_ref,
            outcome,
        ) in cases:
            with self.subTest(log_case=label):
                captured_events: list[dict[str, str]] = []
                sensitive_headers = {
                    "authorization": f"Bearer {SENSITIVE_CANARY}",
                    "x-private-value": SENSITIVE_CANARY,
                }
                sensitive_headers.update(case_headers)
                logged_status, logged_headers, logged_body = _request(
                    _app(factory, probe, log_sink=captured_events.append),
                    method,
                    path,
                    sensitive_headers,
                    sensitive_query,
                    sensitive_body,
                )
                self.assert_contract_json(
                    logged_status,
                    logged_headers,
                    logged_body,
                    expected_status,
                    schema_ref,
                )
                self.assertNotIn(SENSITIVE_CANARY.encode("ascii"), logged_body)
                self.assert_one_safe_log_event(captured_events, outcome)

    def test_same_origin_host_method_and_static_boundary(self) -> None:
        marker = "THRIVELENS_MISSING_IMPLEMENTATION::TL-R0-005-SAME-ORIGIN-HOST-STATIC"
        factory = _load_factory(self, marker)
        app = _app(factory, _Probe())
        for headers in (
            {},
            {"host": "127.0.0.1"},
            {"origin": "http://127.0.0.1:8000"},
            {"host": "localhost"},
            {"host": "localhost:8000", "origin": "http://localhost:8000"},
        ):
            status, response_headers, body = _request(app, "GET", "/api/v1/health/live", headers)
            self.assert_contract_json(
                status,
                response_headers,
                body,
                200,
                "#/components/schemas/LivenessResponse",
            )
            self.assertNotIn("access-control-allow-origin", response_headers)
        static_status, static_headers, static_body = _request(app, "GET", "/")
        self.assertEqual(static_status, 200)
        self.assertIn(b"THRIVELENS_STATIC_FIXTURE", static_body)
        self.assertEqual(static_headers.get("cache-control"), "no-store")
        api_missing_status, api_missing_headers, api_missing_body = _request(
            app, "GET", "/api/v1/not-a-route"
        )
        self.assert_contract_json(
            api_missing_status,
            api_missing_headers,
            api_missing_body,
            404,
            "#/components/schemas/RequestRejectedResponse",
        )
        self.assertNotIn(b"THRIVELENS_STATIC_FIXTURE", api_missing_body)
        self.assertEqual(api_missing_headers.get("cache-control"), "no-store")
        self.assertRegex(api_missing_headers.get("x-correlation-id", ""), r"^[A-Za-z0-9._-]{1,64}$")
        rejections = (
            ("GET", {"host": "example.com"}, 400),
            ("GET", {"host": "127.0.0.1:8000", "x-forwarded-host": "example.com"}, 400),
            ("GET", {"host": "127.0.0.1:8000", "x-forwarded-host": "127.0.0.1:8000"}, 400),
            ("GET", {"host": "127.0.0.1:8000", "origin": "http://localhost:8000"}, 403),
            ("GET", {"host": "localhost:8000", "origin": "http://127.0.0.1:8000"}, 403),
            ("GET", {"host": "127.0.0.1:8000", "origin": "http://127.0.0.1"}, 403),
            ("GET", {"host": "127.0.0.1:8000", "origin": "http://127.0.0.1:9000"}, 403),
            ("GET", {"origin": "https://example.com"}, 403),
            ("GET", {"origin": "null"}, 403),
            ("GET", {"origin": "https://127.0.0.1:8000"}, 403),
            ("OPTIONS", {"origin": "https://example.com"}, 405),
            ("OPTIONS", {"origin": "http://127.0.0.1:8000"}, 405),
            ("OPTIONS", {}, 405),
        )
        for method, request_headers, expected_status in rejections:
            with self.subTest(method=method, headers=request_headers):
                status, response_headers, body = _request(
                    app, method, "/api/v1/health/live", request_headers
                )
                payload = self.assert_contract_json(
                    status,
                    response_headers,
                    body,
                    expected_status,
                    "#/components/schemas/RequestRejectedResponse",
                )
                self.assertEqual(payload["error"]["code"], "REQUEST_REJECTED")
                self.assertEqual(response_headers.get("cache-control"), "no-store")
                self.assertEqual(
                    response_headers.get("x-correlation-id"),
                    payload["error"]["correlation_id"],
                )
                self.assertNotIn("access-control-allow-origin", response_headers)

    def test_production_startup_is_unconditionally_rejected(self) -> None:
        marker = "THRIVELENS_MISSING_IMPLEMENTATION::TL-R0-005-PRODUCTION-REJECTION"
        factory = _load_factory(self, marker)
        with self.assertRaisesRegex(RuntimeError, r"^R0_PRODUCTION_DISABLED$"):
            _app(factory, _Probe(), mode="production")


if __name__ == "__main__":
    unittest.main(verbosity=2)
