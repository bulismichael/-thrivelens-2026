from __future__ import annotations

import unittest

from scripts.contracts.r0_transport import (
    ACCEPTED_HOST_HEADERS,
    ACCEPTED_WEB_ORIGINS,
    load_policy,
    validate_policy,
)


class SameOriginNetworkPolicyTests(unittest.TestCase):
    def test_canonical_network_policy_is_exact(self) -> None:
        validate_policy(load_policy())

    def test_web_and_api_share_only_loopback_origin(self) -> None:
        policy = load_policy()
        self.assertEqual(policy["api"]["bind_host"], "127.0.0.1")
        self.assertEqual(policy["api"]["port"], 8000)
        self.assertFalse(policy["api"]["cors_enabled"])
        self.assertEqual(policy["api"]["web_origin_mode"], "same_origin")
        self.assertEqual(
            ACCEPTED_WEB_ORIGINS,
            {"http://127.0.0.1:8000", "http://localhost:8000"},
        )

    def test_host_allowlist_excludes_public_forwarded_and_test_defaults(self) -> None:
        self.assertEqual(
            ACCEPTED_HOST_HEADERS,
            {"127.0.0.1", "127.0.0.1:8000", "localhost", "localhost:8000"},
        )
        for forbidden in ("0.0.0.0", "example.com", "testserver", "127.0.0.1:9000"):
            self.assertNotIn(forbidden, ACCEPTED_HOST_HEADERS)

    def test_cross_origin_options_and_production_are_fail_closed(self) -> None:
        policy = load_policy()
        self.assertTrue(policy["api"]["reject_cross_origin_options"])
        self.assertFalse(policy["production_enabled"])
        self.assertFalse(policy["android_release"]["production_enabled"])


if __name__ == "__main__":
    unittest.main()
