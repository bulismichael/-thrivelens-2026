from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.contracts.r0_transport import (
    TransportPolicyError,
    adb_cleanup_argv,
    adb_reverse_argv,
    load_policy,
    scan_packaged_inputs,
    validate_policy,
)


class AndroidTransportPolicyTests(unittest.TestCase):
    def test_selected_device_reverse_and_targeted_cleanup_are_exact(self) -> None:
        self.assertEqual(
            adb_reverse_argv("device-01"),
            ["adb", "-s", "device-01", "reverse", "tcp:8000", "tcp:8000"],
        )
        self.assertEqual(
            adb_cleanup_argv("device-01"),
            ["adb", "-s", "device-01", "reverse", "--remove", "tcp:8000"],
        )
        self.assertNotIn("--remove-all", adb_cleanup_argv("device-01"))

    def test_unsafe_or_ambiguous_device_serial_is_rejected(self) -> None:
        for serial in (
            "",
            "-e",
            "--help",
            "-serial",
            "two devices",
            "serial;TL_CANARY",
            "x" * 129,
            "serial\nTL_CANARY",
        ):
            with self.assertRaises(TransportPolicyError, msg=repr(serial)):
                adb_reverse_argv(serial)
            with self.assertRaises(TransportPolicyError, msg=repr(serial)):
                adb_cleanup_argv(serial)

    def test_debug_transport_matches_loopback_api_base_once(self) -> None:
        policy = load_policy()
        validate_policy(policy)
        debug = policy["android_debug"]
        self.assertTrue(debug["selected_device_required"])
        self.assertEqual(debug["transport"], "adb_reverse")
        self.assertEqual(debug["device_host"], "127.0.0.1")
        self.assertEqual(debug["host_host"], "127.0.0.1")
        self.assertEqual(debug["device_port"], 8000)
        self.assertEqual(debug["host_port"], 8000)
        self.assertEqual(debug["base_url"], "http://127.0.0.1:8000/api/v1")
        self.assertNotIn("/api/v1/api/v1", debug["base_url"])
        self.assertTrue(debug["remove_mapping_on_exit"])

    def test_cleartext_is_debug_only_and_release_rejects_debug_base(self) -> None:
        policy = load_policy()
        self.assertTrue(policy["android_debug"]["cleartext_allowed"])
        self.assertFalse(policy["android_release"]["cleartext_allowed"])
        self.assertTrue(policy["android_release"]["reject_debug_base_url"])
        self.assertFalse(policy["android_release"]["production_enabled"])

    def test_forbidden_widening_substitutions_are_absent(self) -> None:
        serialized = str(load_policy()).lower()
        for forbidden in ("0.0.0.0", "10.0.2.2", "trust-all", "remove-all"):
            self.assertNotIn(forbidden, serialized)

    def test_packaged_input_scan_reads_every_regular_file_as_bounded_raw_bytes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-packaged-") as temporary:
            root = Path(temporary)
            (root / "extensionless").write_bytes(b"plain")
            (root / ".env").write_bytes(b"MODE=release")
            (root / "settings.txt").write_bytes(b"release")
            (root / "transport.yaml").write_bytes(b"mode: release")
            (root / "asset.bin").write_bytes(b"\x00\xff\x10release\x00")
            result = scan_packaged_inputs([root])
            self.assertEqual(result["entries"], 6)
            self.assertEqual(result["files"], 5)
            self.assertEqual(
                result["bytes"],
                sum(path.stat().st_size for path in root.iterdir()),
            )

    def test_packaged_input_scan_rejects_debug_url_across_raw_chunk_boundary(self) -> None:
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-packaged-") as temporary:
            root = Path(temporary)
            (root / "opaque.bin").write_bytes(
                b"abcdeHTTP://127.0.0.1:8000/API/V1\x00trailing"
            )
            with patch("scripts.contracts.r0_transport.PACKAGED_SCAN_CHUNK_BYTES", 8):
                with self.assertRaises(TransportPolicyError):
                    scan_packaged_inputs([root])

    def test_packaged_input_scan_rejects_reparse_and_size_limit_bypasses(self) -> None:
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-packaged-") as temporary:
            root = Path(temporary)
            (root / "one").write_bytes(b"ab")
            (root / "two").write_bytes(b"cd")
            with patch("scripts.contracts.r0_transport._is_reparse_stat", return_value=True):
                with self.assertRaises(TransportPolicyError):
                    scan_packaged_inputs([root])
            with patch("scripts.contracts.r0_transport.MAX_PACKAGED_ENTRIES", 2):
                with self.assertRaises(TransportPolicyError):
                    scan_packaged_inputs([root])
            with patch("scripts.contracts.r0_transport.MAX_PACKAGED_FILE_BYTES", 1):
                with self.assertRaises(TransportPolicyError):
                    scan_packaged_inputs([root])
            with patch("scripts.contracts.r0_transport.MAX_PACKAGED_AGGREGATE_BYTES", 3):
                with self.assertRaises(TransportPolicyError):
                    scan_packaged_inputs([root])


if __name__ == "__main__":
    unittest.main()
