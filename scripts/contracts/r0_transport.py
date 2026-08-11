from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
POLICY_PATH = REPOSITORY_ROOT / "config" / "r0-network-policy.json"
SAFE_DEVICE_SERIAL = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")
ACCEPTED_HOST_HEADERS = frozenset(
    {"127.0.0.1", "127.0.0.1:8000", "localhost", "localhost:8000"}
)
ACCEPTED_WEB_ORIGINS = frozenset(
    {"http://127.0.0.1:8000", "http://localhost:8000"}
)


class TransportPolicyError(ValueError):
    """Raised when R0 transport would widen beyond the frozen local boundary."""


def load_policy(path: Path = POLICY_PATH) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise TransportPolicyError("R0 network policy is unreadable") from exc
    if not isinstance(value, dict):
        raise TransportPolicyError("R0 network policy root must be an object")
    return value


def validate_policy(policy: dict[str, Any]) -> None:
    expected = {
        "schema_version": 1,
        "production_enabled": False,
        "api": {
            "bind_host": "127.0.0.1",
            "port": 8000,
            "cors_enabled": False,
            "web_origin_mode": "same_origin",
            "reject_cross_origin_options": True,
        },
        "android_debug": {
            "transport": "adb_reverse",
            "selected_device_required": True,
            "device_host": "127.0.0.1",
            "device_port": 8000,
            "host_host": "127.0.0.1",
            "host_port": 8000,
            "base_url": "http://127.0.0.1:8000/api/v1",
            "cleartext_allowed": True,
            "remove_mapping_on_exit": True,
        },
        "android_release": {
            "cleartext_allowed": False,
            "reject_debug_base_url": True,
            "production_enabled": False,
        },
    }
    if policy != expected:
        raise TransportPolicyError("R0 network policy differs from the exact frozen contract")


def _validated_serial(serial: str) -> str:
    if not isinstance(serial, str) or SAFE_DEVICE_SERIAL.fullmatch(serial) is None:
        raise TransportPolicyError("ADB device serial must be one bounded explicit argument")
    return serial


def adb_reverse_argv(serial: str) -> list[str]:
    selected = _validated_serial(serial)
    return ["adb", "-s", selected, "reverse", "tcp:8000", "tcp:8000"]


def adb_cleanup_argv(serial: str) -> list[str]:
    selected = _validated_serial(serial)
    return ["adb", "-s", selected, "reverse", "--remove", "tcp:8000"]
