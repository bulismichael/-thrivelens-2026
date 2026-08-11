from __future__ import annotations

import tempfile
import subprocess
import stat
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from scripts.contracts.r0_transport import (
    TransportPolicyError,
    adb_cleanup_argv,
    adb_reverse_argv,
    inspect_release_apk_bytes,
    load_policy,
    load_release_policy_from_apk,
    scan_packaged_inputs,
    validate_policy,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


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
            "serial&TL_CANARY",
            "serial<TL_CANARY",
            "serial>TL_CANARY",
            'serial"TL_CANARY',
            "serial'TL_CANARY",
            "serial%TL_CANARY",
            "serial`TL_CANARY",
            "serial\tTL_CANARY",
            "x" * 129,
            "serial\nTL_CANARY",
        ):
            with self.assertRaises(TransportPolicyError, msg=repr(serial)):
                adb_reverse_argv(serial)
            with self.assertRaises(TransportPolicyError, msg=repr(serial)):
                adb_cleanup_argv(serial)

    def test_task_owned_powershell_primitive_exhausts_ascii_and_uses_argument_list(self) -> None:
        result = subprocess.run(
            [
                "pwsh",
                "-NoProfile",
                "-File",
                str(REPOSITORY_ROOT / "scripts" / "contracts" / "test_r0_android_invocation.ps1"),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr)[-2000:])
        self.assertIn("Android invocation primitive PASS", result.stdout)

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

    def test_release_apk_scan_reads_expanded_entries_and_rejects_debug_transport(self) -> None:
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-apk-") as temporary:
            root = Path(temporary)
            safe_apk = root / "safe.apk"
            with zipfile.ZipFile(safe_apk, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("AndroidManifest.xml", b"compiled-manifest")
                archive.writestr("assets/flutter_assets/.env", b"MODE=release")
                archive.writestr("assets/flutter_assets/opaque", b"\x00\xffrelease\x00")
                archive.writestr(
                    "assets/flutter_assets/assets/r0_release_policy.json",
                    b'{"schema_version":1,"resolved_api_base_url":"","production_enabled":false}',
                )
            result = inspect_release_apk_bytes(safe_apk)
            self.assertEqual(result["files"], 4)
            self.assertGreater(result["expanded_bytes"], 0)
            self.assertEqual(
                load_release_policy_from_apk(safe_apk),
                {
                    "schema_version": 1,
                    "resolved_api_base_url": "",
                    "production_enabled": False,
                },
            )

            unsafe_apk = root / "unsafe.apk"
            with zipfile.ZipFile(unsafe_apk, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("AndroidManifest.xml", b"compiled-manifest")
                archive.writestr(
                    "assets/flutter_assets/opaque",
                    b"prefixHTTP://127.0.0.1:8000/API/V1suffix",
                )
            with patch("scripts.contracts.r0_transport.PACKAGED_SCAN_CHUNK_BYTES", 8):
                with self.assertRaises(TransportPolicyError):
                    inspect_release_apk_bytes(unsafe_apk)

    def test_release_apk_scan_rejects_network_config_links_and_expansion_caps(self) -> None:
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-apk-") as temporary:
            root = Path(temporary)
            network_apk = root / "network.apk"
            with zipfile.ZipFile(network_apk, "w") as archive:
                archive.writestr("AndroidManifest.xml", b"manifest")
                archive.writestr("res/xml/network_security_config.xml", b"compiled")
            with self.assertRaises(TransportPolicyError):
                inspect_release_apk_bytes(network_apk)

            link_apk = root / "link.apk"
            link = zipfile.ZipInfo("assets/flutter_assets/link")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            with zipfile.ZipFile(link_apk, "w") as archive:
                archive.writestr("AndroidManifest.xml", b"manifest")
                archive.writestr(link, b"target")
            with self.assertRaises(TransportPolicyError):
                inspect_release_apk_bytes(link_apk)

            capped_apk = root / "capped.apk"
            with zipfile.ZipFile(capped_apk, "w") as archive:
                archive.writestr("AndroidManifest.xml", b"manifest")
                archive.writestr("assets/value", b"abcd")
            with patch("scripts.contracts.r0_transport.MAX_APK_EXPANDED_BYTES", 4):
                with self.assertRaises(TransportPolicyError):
                    inspect_release_apk_bytes(capped_apk)

            unsafe_policy_apk = root / "unsafe-policy.apk"
            with zipfile.ZipFile(unsafe_policy_apk, "w") as archive:
                archive.writestr("AndroidManifest.xml", b"manifest")
                archive.writestr(
                    "assets/flutter_assets/assets/r0_release_policy.json",
                    b'{"schema_version":1,"resolved_api_base_url":"","production_enabled":true}',
                )
            with self.assertRaises(TransportPolicyError):
                load_release_policy_from_apk(unsafe_policy_apk)


if __name__ == "__main__":
    unittest.main()
