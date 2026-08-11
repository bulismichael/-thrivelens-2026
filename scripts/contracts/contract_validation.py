from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Iterable


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
OPENAPI_PATH = REPOSITORY_ROOT / "contracts" / "openapi" / "r0-heartbeat.openapi.json"
FIXTURE_ROOT = OPENAPI_PATH.parent / "fixtures"
MANIFEST_PATH = REPOSITORY_ROOT / "tests" / "contracts" / "expected-red.json"

EXPECTED_EFFECTIVE_ROUTES = {
    "/api/v1/health/live": ("getHealthLive", {"200", "400", "403", "500"}),
    "/api/v1/health/ready": ("getHealthReady", {"200", "400", "403", "500", "503"}),
    "/api/v1/system/status": ("getSystemStatus", {"200", "400", "403", "500"}),
    "/api/v1/system/version": ("getSystemVersion", {"200", "400", "403", "500"}),
}

EXPECTED_RESPONSE_SCHEMAS = {
    ("/health/live", "200"): "#/components/schemas/LivenessResponse",
    ("/health/live", "400"): "#/components/schemas/RequestRejectedResponse",
    ("/health/live", "403"): "#/components/schemas/RequestRejectedResponse",
    ("/health/live", "500"): "#/components/schemas/InternalErrorResponse",
    ("/health/ready", "200"): "#/components/schemas/ReadinessReadyResponse",
    ("/health/ready", "400"): "#/components/schemas/RequestRejectedResponse",
    ("/health/ready", "403"): "#/components/schemas/RequestRejectedResponse",
    ("/health/ready", "500"): "#/components/schemas/InternalErrorResponse",
    ("/health/ready", "503"): "#/components/schemas/ReadinessUnavailableResponse",
    ("/system/status", "200"): "#/components/schemas/SystemStatusResponse",
    ("/system/status", "400"): "#/components/schemas/RequestRejectedResponse",
    ("/system/status", "403"): "#/components/schemas/RequestRejectedResponse",
    ("/system/status", "500"): "#/components/schemas/InternalErrorResponse",
    ("/system/version", "200"): "#/components/schemas/SystemVersionResponse",
    ("/system/version", "400"): "#/components/schemas/RequestRejectedResponse",
    ("/system/version", "403"): "#/components/schemas/RequestRejectedResponse",
    ("/system/version", "500"): "#/components/schemas/InternalErrorResponse",
}

FIXTURE_CASES = {
    "health-live-200.json": "#/components/schemas/LivenessResponse",
    "health-ready-200.json": "#/components/schemas/ReadinessReadyResponse",
    "health-ready-503-not-ready.json": "#/components/schemas/ReadinessUnavailableResponse",
    "health-ready-503-unknown.json": "#/components/schemas/ReadinessUnavailableResponse",
    "system-status-200-available.json": "#/components/schemas/SystemStatusResponse",
    "system-status-200-degraded-not-ready.json": "#/components/schemas/SystemStatusResponse",
    "system-status-200-degraded-unknown.json": "#/components/schemas/SystemStatusResponse",
    "system-version-200.json": "#/components/schemas/SystemVersionResponse",
    "internal-error-500.json": "#/components/schemas/InternalErrorResponse",
    "request-rejected.json": "#/components/schemas/RequestRejectedResponse",
}

FORBIDDEN_RESPONSE_FRAGMENTS = (
    "postgresql://",
    "postgres://",
    "traceback",
    "stack trace",
    "sqlalchemy",
    "psycopg",
    "password",
    "secret",
    "select *",
    "c:\\users\\",
    "/home/",
    "/users/",
    "/workspace/",
)

EXPECTED_MANIFEST_ENTRIES = {
    "TL-R0-005-LIVENESS-DB-INDEPENDENCE": {
        "owner": "TL-R0-005",
        "script": "tests/contracts/expected_red/test_backend_heartbeat_acceptance.py",
        "test_id": (
            "__main__.BackendHeartbeatAcceptanceTests.test_liveness_never_invokes_database_probe"
        ),
    },
    "TL-R0-005-READINESS-STATUS-MATRIX": {
        "owner": "TL-R0-005",
        "script": "tests/contracts/expected_red/test_backend_heartbeat_acceptance.py",
        "test_id": (
            "__main__.BackendHeartbeatAcceptanceTests.test_readiness_and_mobile_status_truth_matrix"
        ),
    },
    "TL-R0-005-HEADERS-CORRELATION-REDACTION": {
        "owner": "TL-R0-005",
        "script": "tests/contracts/expected_red/test_backend_heartbeat_acceptance.py",
        "test_id": (
            "__main__.BackendHeartbeatAcceptanceTests.test_headers_correlation_and_error_redaction"
        ),
    },
    "TL-R0-005-SAME-ORIGIN-HOST-STATIC": {
        "owner": "TL-R0-005",
        "script": "tests/contracts/expected_red/test_backend_heartbeat_acceptance.py",
        "test_id": (
            "__main__.BackendHeartbeatAcceptanceTests.test_same_origin_host_method_and_static_boundary"
        ),
    },
    "TL-R0-005-PRODUCTION-REJECTION": {
        "owner": "TL-R0-005",
        "script": "tests/contracts/expected_red/test_backend_heartbeat_acceptance.py",
        "test_id": (
            "__main__.BackendHeartbeatAcceptanceTests.test_production_startup_is_unconditionally_rejected"
        ),
    },
    "TL-R0-008-ADB-REVERSE-LIFECYCLE": {
        "owner": "TL-R0-008",
        "script": "tests/contracts/expected_red/test_android_heartbeat_acceptance.py",
        "test_id": (
            "__main__.AndroidHeartbeatAcceptanceTests.test_selected_device_reverse_and_failure_cleanup"
        ),
    },
    "TL-R0-008-DEBUG-MANIFEST-BOUNDARY": {
        "owner": "TL-R0-008",
        "script": "tests/contracts/expected_red/test_android_heartbeat_acceptance.py",
        "test_id": (
            "__main__.AndroidHeartbeatAcceptanceTests.test_debug_cleartext_is_loopback_scoped"
        ),
    },
    "TL-R0-008-RELEASE-PRODUCTION-NEGATIVE": {
        "owner": "TL-R0-008",
        "script": "tests/contracts/expected_red/test_android_heartbeat_acceptance.py",
        "test_id": (
            "__main__.AndroidHeartbeatAcceptanceTests.test_release_rejects_debug_transport_and_production"
        ),
    },
}


class ContractValidationError(ValueError):
    """Raised when a frozen contract violates a deterministic invariant."""


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractValidationError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ContractValidationError(f"cannot read {path.name}: {exc.strerror}") from exc
    if len(text.encode("utf-8")) > 1_048_576:
        raise ContractValidationError(f"JSON file exceeds 1 MiB: {path.name}")
    try:
        return json.loads(text, object_pairs_hook=_reject_duplicate_pairs)
    except json.JSONDecodeError as exc:
        raise ContractValidationError(
            f"invalid JSON in {path.name} at line {exc.lineno}, column {exc.colno}"
        ) from exc


def _decode_pointer_part(value: str) -> str:
    return value.replace("~1", "/").replace("~0", "~")


def resolve_local_ref(document: dict[str, Any], ref: str) -> Any:
    if not isinstance(ref, str) or not ref.startswith("#/"):
        raise ContractValidationError(f"external or malformed reference is forbidden: {ref!r}")
    node: Any = document
    for raw_part in ref[2:].split("/"):
        part = _decode_pointer_part(raw_part)
        if not isinstance(node, dict) or part not in node:
            raise ContractValidationError(f"unresolved local reference: {ref}")
        node = node[part]
    return node


def _iter_nodes(node: Any, pointer: str = "$") -> Iterable[tuple[str, Any]]:
    yield pointer, node
    if isinstance(node, dict):
        for key, value in node.items():
            yield from _iter_nodes(value, f"{pointer}/{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from _iter_nodes(value, f"{pointer}/{index}")


def _schema_ref_from_response(document: dict[str, Any], response: dict[str, Any]) -> str:
    seen: set[str] = set()
    current: Any = response
    while isinstance(current, dict) and "$ref" in current:
        if set(current) != {"$ref"}:
            raise ContractValidationError("a response $ref cannot have sibling keys")
        ref = current["$ref"]
        if ref in seen:
            raise ContractValidationError(f"cyclic response reference: {ref}")
        seen.add(ref)
        current = resolve_local_ref(document, ref)
    try:
        return current["content"]["application/json"]["schema"]["$ref"]
    except (KeyError, TypeError) as exc:
        raise ContractValidationError("every response must use one canonical JSON schema $ref") from exc


def _resolved_response(document: dict[str, Any], response: dict[str, Any]) -> dict[str, Any]:
    if "$ref" not in response:
        return response
    if set(response) != {"$ref"}:
        raise ContractValidationError("a response $ref cannot have sibling keys")
    resolved = resolve_local_ref(document, response["$ref"])
    if not isinstance(resolved, dict):
        raise ContractValidationError("response reference must resolve to an object")
    return resolved


def _resolved_header(document: dict[str, Any], header: dict[str, Any]) -> dict[str, Any]:
    if "$ref" not in header:
        return header
    if set(header) != {"$ref"}:
        raise ContractValidationError("a header $ref cannot have sibling keys")
    resolved = resolve_local_ref(document, header["$ref"])
    if not isinstance(resolved, dict):
        raise ContractValidationError("header reference must resolve to an object")
    return resolved


def validate_openapi(document: dict[str, Any]) -> None:
    if not isinstance(document, dict):
        raise ContractValidationError("OpenAPI root must be an object")
    if document.get("openapi") != "3.0.3":
        raise ContractValidationError("OpenAPI version must be exactly 3.0.3")
    if document.get("security") != []:
        raise ContractValidationError("R0 top-level security must be explicitly anonymous")
    if document.get("servers") != [
        {"url": "/api/v1", "description": "Same-origin R0 API base"}
    ]:
        raise ContractValidationError("the only server must be the relative /api/v1 base")

    paths = document.get("paths")
    if not isinstance(paths, dict):
        raise ContractValidationError("paths must be an object")
    expected_path_items = {route.removeprefix("/api/v1") for route in EXPECTED_EFFECTIVE_ROUTES}
    if set(paths) != expected_path_items:
        raise ContractValidationError("OpenAPI must contain exactly the four frozen relative paths")

    operation_ids: set[str] = set()
    effective_routes: set[str] = set()
    for path, path_item in paths.items():
        if not isinstance(path_item, dict) or set(path_item) != {"get"}:
            raise ContractValidationError(f"{path} must expose GET only")
        operation = path_item["get"]
        if not isinstance(operation, dict):
            raise ContractValidationError(f"GET {path} must be an object")
        if operation.get("security") != []:
            raise ContractValidationError(f"GET {path} must be explicitly anonymous")
        forbidden = {"requestBody", "callbacks", "webhooks"} & set(operation)
        if forbidden:
            raise ContractValidationError(f"GET {path} has forbidden input or callback keys: {sorted(forbidden)}")
        if operation.get("parameters") != [
            {"$ref": "#/components/parameters/CorrelationIdRequest"}
        ]:
            raise ContractValidationError(f"GET {path} must expose only the optional correlation header")
        operation_id = operation.get("operationId")
        if not isinstance(operation_id, str) or operation_id in operation_ids:
            raise ContractValidationError("operationIds must be present and unique")
        operation_ids.add(operation_id)

        effective_route = f"/api/v1{path}"
        effective_routes.add(effective_route)
        expected_id, expected_statuses = EXPECTED_EFFECTIVE_ROUTES[effective_route]
        if operation_id != expected_id:
            raise ContractValidationError(f"unexpected operationId for {effective_route}")
        responses = operation.get("responses")
        if not isinstance(responses, dict) or set(responses) != expected_statuses:
            raise ContractValidationError(f"unexpected response statuses for {effective_route}")
        if "default" in responses:
            raise ContractValidationError("permissive default responses are forbidden")

        for status, raw_response in responses.items():
            if not isinstance(raw_response, dict):
                raise ContractValidationError(f"response {status} for {path} must be an object")
            response = _resolved_response(document, raw_response)
            headers = response.get("headers")
            if not isinstance(headers, dict) or set(headers) != {
                "Cache-Control",
                "X-Correlation-ID",
            }:
                raise ContractValidationError(f"response {status} for {path} must have exactly safe headers")
            cache_header = _resolved_header(document, headers["Cache-Control"])
            correlation_header = _resolved_header(document, headers["X-Correlation-ID"])
            if cache_header.get("schema") != {"type": "string", "enum": ["no-store"]}:
                raise ContractValidationError("Cache-Control must be frozen to no-store")
            if correlation_header.get("schema") != {
                "type": "string",
                "pattern": "^[A-Za-z0-9._-]{1,64}$",
                "minLength": 1,
                "maxLength": 64,
            }:
                raise ContractValidationError("X-Correlation-ID must use the exact bounded safe alphabet")
            if any(name.lower().startswith("access-control-") for name in headers):
                raise ContractValidationError("CORS response headers are forbidden in R0")
            actual_schema = _schema_ref_from_response(document, raw_response)
            expected_schema = EXPECTED_RESPONSE_SCHEMAS[(path, status)]
            if actual_schema != expected_schema:
                raise ContractValidationError(f"response {status} for {path} uses the wrong schema")
            resolve_local_ref(document, actual_schema)

    if effective_routes != set(EXPECTED_EFFECTIVE_ROUTES):
        raise ContractValidationError("effective route composition is not the frozen four-route surface")

    parameter = document.get("components", {}).get("parameters", {}).get("CorrelationIdRequest")
    if parameter != {
        "name": "X-Correlation-ID",
        "in": "header",
        "required": False,
        "description": (
            "A valid bounded value may be propagated. Invalid, control-bearing, or oversized "
            "values are ignored and replaced by the server."
        ),
        "schema": {"$ref": "#/components/schemas/CorrelationId"},
    }:
        raise ContractValidationError("the optional request correlation parameter must remain exact")

    for pointer, node in _iter_nodes(document):
        if not isinstance(node, dict):
            continue
        if "$ref" in node:
            if set(node) != {"$ref"}:
                raise ContractValidationError(f"$ref siblings are forbidden at {pointer}")
            resolve_local_ref(document, node["$ref"])
        if node.get("nullable") is True:
            raise ContractValidationError(f"nullable escape hatch is forbidden at {pointer}")
        if node.get("additionalProperties") is True:
            raise ContractValidationError(f"open additionalProperties is forbidden at {pointer}")

    schemas = document.get("components", {}).get("schemas")
    if not isinstance(schemas, dict) or not schemas:
        raise ContractValidationError("components.schemas must be a non-empty object")
    for name, schema in schemas.items():
        _validate_schema_definition(document, schema, f"#/components/schemas/{name}", set())


def _validate_schema_definition(
    document: dict[str, Any], schema: Any, pointer: str, resolving: set[str]
) -> None:
    if not isinstance(schema, dict):
        raise ContractValidationError(f"schema must be an object at {pointer}")
    if "$ref" in schema:
        if set(schema) != {"$ref"}:
            raise ContractValidationError(f"schema $ref siblings are forbidden at {pointer}")
        ref = schema["$ref"]
        if ref in resolving:
            raise ContractValidationError(f"cyclic schema reference is forbidden at {pointer}: {ref}")
        _validate_schema_definition(document, resolve_local_ref(document, ref), ref, resolving | {ref})
        return

    object_keywords = {"properties", "required", "additionalProperties"} & set(schema)
    if schema.get("type") == "object" or object_keywords:
        if schema.get("type") != "object":
            raise ContractValidationError(f"object schema must declare type object at {pointer}")
        if schema.get("additionalProperties") is not False:
            raise ContractValidationError(f"object schema must set additionalProperties false at {pointer}")
        properties = schema.get("properties")
        required = schema.get("required")
        if not isinstance(properties, dict) or not properties:
            raise ContractValidationError(f"object schema needs explicit properties at {pointer}")
        if not isinstance(required, list) or len(required) != len(set(required)):
            raise ContractValidationError(f"object schema needs a unique required list at {pointer}")
        if set(required) != set(properties):
            raise ContractValidationError(f"every object property must be required at {pointer}")
        for key, child in properties.items():
            _validate_schema_definition(document, child, f"{pointer}/properties/{key}", resolving)

    if "oneOf" in schema:
        branches = schema["oneOf"]
        if not isinstance(branches, list) or len(branches) < 2:
            raise ContractValidationError(f"oneOf must have at least two branches at {pointer}")
        for index, branch in enumerate(branches):
            _validate_schema_definition(document, branch, f"{pointer}/oneOf/{index}", resolving)
    if schema.get("type") == "array":
        if "items" not in schema:
            raise ContractValidationError(f"array schema must define items at {pointer}")
        _validate_schema_definition(document, schema["items"], f"{pointer}/items", resolving)


def validate_instance(
    document: dict[str, Any], schema: dict[str, Any], value: Any, pointer: str = "$"
) -> list[str]:
    if "$ref" in schema:
        return validate_instance(document, resolve_local_ref(document, schema["$ref"]), value, pointer)
    if "oneOf" in schema:
        branch_errors = [validate_instance(document, branch, value, pointer) for branch in schema["oneOf"]]
        matches = [errors for errors in branch_errors if not errors]
        if len(matches) == 1:
            return []
        return [f"{pointer}: expected exactly one oneOf branch, matched {len(matches)}"]

    errors: list[str] = []
    schema_type = schema.get("type")
    type_matches = {
        "object": lambda item: isinstance(item, dict),
        "array": lambda item: isinstance(item, list),
        "string": lambda item: isinstance(item, str),
        "integer": lambda item: isinstance(item, int) and not isinstance(item, bool),
        "number": lambda item: isinstance(item, (int, float)) and not isinstance(item, bool),
        "boolean": lambda item: isinstance(item, bool),
    }
    if schema_type in type_matches and not type_matches[schema_type](value):
        return [f"{pointer}: expected {schema_type}"]
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{pointer}: value is outside enum")

    if schema_type == "string" and isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(f"{pointer}: string is shorter than minLength")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(f"{pointer}: string is longer than maxLength")
        if "pattern" in schema and re.fullmatch(schema["pattern"], value) is None:
            errors.append(f"{pointer}: string does not match pattern")

    if schema_type == "object" and isinstance(value, dict):
        properties = schema.get("properties", {})
        missing = set(schema.get("required", [])) - set(value)
        extra = set(value) - set(properties)
        if missing:
            errors.append(f"{pointer}: missing properties {sorted(missing)}")
        if schema.get("additionalProperties") is False and extra:
            errors.append(f"{pointer}: unexpected properties {sorted(extra)}")
        for key in set(value) & set(properties):
            errors.extend(validate_instance(document, properties[key], value[key], f"{pointer}.{key}"))
    if schema_type == "array" and isinstance(value, list):
        for index, item in enumerate(value):
            errors.extend(validate_instance(document, schema["items"], item, f"{pointer}[{index}]"))
    return errors


def validate_fixtures(document: dict[str, Any], fixture_root: Path = FIXTURE_ROOT) -> None:
    actual_files = {path.name for path in fixture_root.glob("*.json") if path.is_file()}
    if actual_files != set(FIXTURE_CASES):
        raise ContractValidationError("fixture inventory must be exactly the frozen response cases")
    for filename, schema_ref in FIXTURE_CASES.items():
        fixture = load_json(fixture_root / filename)
        errors = validate_instance(document, {"$ref": schema_ref}, fixture)
        if errors:
            raise ContractValidationError(f"{filename} does not match {schema_ref}: {'; '.join(errors)}")
        serialized = json.dumps(fixture, sort_keys=True).lower()
        for fragment in FORBIDDEN_RESPONSE_FRAGMENTS:
            if fragment in serialized:
                raise ContractValidationError(f"{filename} contains forbidden response detail")


def validate_expected_red_manifest(manifest: dict[str, Any]) -> None:
    if not isinstance(manifest, dict) or set(manifest) != {"schema_version", "entries"}:
        raise ContractValidationError("expected-red manifest root keys are closed")
    if manifest.get("schema_version") != 1:
        raise ContractValidationError("expected-red schema_version must be 1")
    entries = manifest.get("entries")
    if not isinstance(entries, list) or not entries or len(entries) > 16:
        raise ContractValidationError("expected-red entries must contain 1..16 items")
    expected_keys = {
        "id",
        "owner",
        "working_directory",
        "argv",
        "timeout_seconds",
        "test_ids",
        "expected_missing_behavior_marker",
        "future_green_command",
    }
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != expected_keys:
            raise ContractValidationError("expected-red entry keys are closed")
        entry_id = entry.get("id")
        if entry_id in seen or entry_id not in EXPECTED_MANIFEST_ENTRIES:
            raise ContractValidationError("expected-red IDs must be unique and exactly frozen")
        seen.add(entry_id)
        expected = EXPECTED_MANIFEST_ENTRIES[entry_id]
        owner = entry.get("owner")
        test_id = expected["test_id"]
        if owner != expected["owner"]:
            raise ContractValidationError(f"wrong owner for {entry_id}")
        if entry.get("working_directory") != ".":
            raise ContractValidationError("expected-red working_directory must remain repository-relative dot")
        direct_test_name = test_id.removeprefix("__main__.")
        if entry.get("argv") != ["python", expected["script"], direct_test_name]:
            raise ContractValidationError(f"argv is not the frozen no-shell test command for {entry_id}")
        if entry.get("test_ids") != [test_id]:
            raise ContractValidationError(f"test_ids are not exact for {entry_id}")
        if entry.get("timeout_seconds") != 30:
            raise ContractValidationError("expected-red timeout must remain 30 seconds")
        marker = f"THRIVELENS_MISSING_IMPLEMENTATION::{entry_id}"
        if entry.get("expected_missing_behavior_marker") != marker:
            raise ContractValidationError(f"missing-behavior marker is not exact for {entry_id}")
        command = (
            "pwsh -NoProfile -File scripts/contracts/assert_expected_green.ps1 "
            f"-Manifest tests/contracts/expected-red.json -Owner {owner}"
        )
        if entry.get("future_green_command") != command:
            raise ContractValidationError(f"future green command is not exact for {entry_id}")
    if seen != set(EXPECTED_MANIFEST_ENTRIES):
        raise ContractValidationError("expected-red manifest is missing a frozen entry")


def validate_all() -> tuple[int, int]:
    document = load_json(OPENAPI_PATH)
    validate_openapi(document)
    validate_fixtures(document)
    manifest = load_json(MANIFEST_PATH)
    validate_expected_red_manifest(manifest)
    return len(EXPECTED_EFFECTIVE_ROUTES), len(FIXTURE_CASES)
