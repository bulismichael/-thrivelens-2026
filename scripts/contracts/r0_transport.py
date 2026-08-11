from __future__ import annotations

import json
import os
import re
import stat
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
POLICY_PATH = REPOSITORY_ROOT / "config" / "r0-network-policy.json"
SAFE_DEVICE_SERIAL = re.compile(r"^[A-Za-z0-9._:][A-Za-z0-9._:-]{0,127}$")
FORBIDDEN_PACKAGED_BYTES = (
    b"http://127.0.0.1:8000/api/v1",
    b'usescleartexttraffic="true"',
)
MAX_PACKAGED_ENTRIES = 8192
MAX_PACKAGED_FILE_BYTES = 16 * 1024 * 1024
MAX_PACKAGED_AGGREGATE_BYTES = 128 * 1024 * 1024
PACKAGED_SCAN_CHUNK_BYTES = 8192
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


def _is_reparse_stat(value: os.stat_result) -> bool:
    attributes = int(getattr(value, "st_file_attributes", 0))
    reparse_attribute = int(getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
    return stat.S_ISLNK(value.st_mode) or bool(attributes & reparse_attribute)


def _bounded_regular_file_scan(path: Path, aggregate_bytes: int) -> int:
    try:
        before = path.lstat()
    except OSError as exc:
        raise TransportPolicyError("Packaged input metadata is unreadable") from exc
    if _is_reparse_stat(before):
        raise TransportPolicyError("Packaged inputs must not contain reparse points")
    if not stat.S_ISREG(before.st_mode):
        raise TransportPolicyError("Packaged inputs must contain regular files only")
    if before.st_size < 0 or before.st_size > MAX_PACKAGED_FILE_BYTES:
        raise TransportPolicyError("Packaged input file exceeds the bounded byte limit")
    if aggregate_bytes + before.st_size > MAX_PACKAGED_AGGREGATE_BYTES:
        raise TransportPolicyError("Packaged inputs exceed the aggregate byte limit")

    flags = os.O_RDONLY | int(getattr(os, "O_BINARY", 0)) | int(getattr(os, "O_NOFOLLOW", 0))
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        raise TransportPolicyError("Packaged input file is unreadable") from exc
    size = 0
    tail = b""
    longest_needle = max(len(value) for value in FORBIDDEN_PACKAGED_BYTES)
    try:
        opened = os.fstat(descriptor)
        if _is_reparse_stat(opened) or not stat.S_ISREG(opened.st_mode):
            raise TransportPolicyError("Packaged inputs must contain regular non-reparse files")
        with os.fdopen(descriptor, "rb", closefd=True) as handle:
            descriptor = -1
            while True:
                chunk = handle.read(PACKAGED_SCAN_CHUNK_BYTES)
                if not chunk:
                    break
                size += len(chunk)
                if size > MAX_PACKAGED_FILE_BYTES:
                    raise TransportPolicyError("Packaged input file exceeds the bounded byte limit")
                if aggregate_bytes + size > MAX_PACKAGED_AGGREGATE_BYTES:
                    raise TransportPolicyError("Packaged inputs exceed the aggregate byte limit")
                window = (tail + chunk).lower()
                if any(needle in window for needle in FORBIDDEN_PACKAGED_BYTES):
                    raise TransportPolicyError("Packaged inputs contain forbidden release transport bytes")
                tail = window[-(longest_needle - 1) :] if longest_needle > 1 else b""
    except OSError as exc:
        raise TransportPolicyError("Packaged input file could not be scanned") from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    return size


def scan_packaged_inputs(sources: list[Path]) -> dict[str, int]:
    """Scan every packaged file as bounded raw bytes without following reparse points."""

    if not sources or len(sources) > 16:
        raise TransportPolicyError("Packaged input roots must be a bounded non-empty list")
    stack: list[Path] = []
    root_keys: set[str] = set()
    for source in sources:
        path = Path(source)
        key = os.path.normcase(os.path.abspath(os.fspath(path)))
        if key in root_keys:
            raise TransportPolicyError("Packaged input roots must be unique")
        root_keys.add(key)
        stack.append(path)

    entry_count = len(stack)
    if entry_count > MAX_PACKAGED_ENTRIES:
        raise TransportPolicyError("Packaged inputs exceed the entry limit")
    file_count = 0
    aggregate_bytes = 0
    while stack:
        path = stack.pop()
        try:
            metadata = path.lstat()
        except OSError as exc:
            raise TransportPolicyError("Packaged input is missing or unreadable") from exc
        if _is_reparse_stat(metadata):
            raise TransportPolicyError("Packaged inputs must not contain reparse points")
        if stat.S_ISDIR(metadata.st_mode):
            try:
                with os.scandir(path) as children:
                    for child in children:
                        entry_count += 1
                        if entry_count > MAX_PACKAGED_ENTRIES:
                            raise TransportPolicyError("Packaged inputs exceed the entry limit")
                        stack.append(Path(child.path))
            except TransportPolicyError:
                raise
            except OSError as exc:
                raise TransportPolicyError("Packaged input directory is unreadable") from exc
            continue
        if not stat.S_ISREG(metadata.st_mode):
            raise TransportPolicyError("Packaged inputs must contain regular files and directories only")
        aggregate_bytes += _bounded_regular_file_scan(path, aggregate_bytes)
        file_count += 1

    return {
        "entries": entry_count,
        "files": file_count,
        "bytes": aggregate_bytes,
    }
