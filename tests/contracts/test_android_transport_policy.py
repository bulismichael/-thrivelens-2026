from __future__ import annotations

import unittest

from scripts.contracts.r0_transport import (
    TransportPolicyError,
    adb_cleanup_argv,
    adb_reverse_argv,
    load_policy,
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
        for serial in ("", "two devices", "serial;exit", "x" * 129, "serial\nother"):
            with self.assertRaises(TransportPolicyError, msg=repr(serial)):
                adb_reverse_argv(serial)

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


if __name__ == "__main__":
    unittest.main()
