from __future__ import annotations

import copy
import unittest

from scripts.contracts.contract_validation import (
    FIXTURE_CASES,
    FIXTURE_ROOT,
    OPENAPI_PATH,
    load_json,
    validate_fixtures,
    validate_instance,
)


class ResponseFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.document = load_json(OPENAPI_PATH)

    def fixture(self, name: str):  # type: ignore[no-untyped-def]
        return load_json(FIXTURE_ROOT / name)

    def test_exact_fixture_inventory_validates(self) -> None:
        validate_fixtures(self.document)
        self.assertEqual(
            {path.name for path in FIXTURE_ROOT.glob("*.json")},
            set(FIXTURE_CASES),
        )

    def test_readiness_503_distinguishes_not_ready_and_unknown(self) -> None:
        not_ready = self.fixture("health-ready-503-not-ready.json")
        unknown = self.fixture("health-ready-503-unknown.json")
        self.assertEqual((not_ready["status"], not_ready["database"]), ("not_ready", "not_ready"))
        self.assertEqual((unknown["status"], unknown["database"]), ("not_ready", "unknown"))
        self.assertNotEqual(not_ready["error"]["code"], unknown["error"]["code"])

    def test_mobile_status_truth_table_is_closed(self) -> None:
        available = self.fixture("system-status-200-available.json")
        not_ready = self.fixture("system-status-200-degraded-not-ready.json")
        unknown = self.fixture("system-status-200-degraded-unknown.json")
        self.assertEqual((available["status"], available["components"]["database"]), ("available", "ready"))
        self.assertEqual((not_ready["status"], not_ready["components"]["database"]), ("degraded", "not_ready"))
        self.assertEqual((unknown["status"], unknown["components"]["database"]), ("degraded", "unknown"))

    def test_impossible_available_with_negative_database_is_rejected(self) -> None:
        fixture = self.fixture("system-status-200-available.json")
        fixture["components"]["database"] = "unknown"
        errors = validate_instance(
            self.document,
            {"$ref": "#/components/schemas/SystemStatusResponse"},
            fixture,
        )
        self.assertTrue(errors)

    def test_extra_nested_property_is_rejected(self) -> None:
        fixture = self.fixture("health-ready-503-not-ready.json")
        fixture["error"]["exception"] = "synthetic sentinel"
        errors = validate_instance(
            self.document,
            {"$ref": "#/components/schemas/ReadinessUnavailableResponse"},
            fixture,
        )
        self.assertTrue(errors)

    def test_correlation_value_is_bounded_to_safe_alphabet(self) -> None:
        fixture = self.fixture("internal-error-500.json")
        for invalid in ("", "line\nbreak", "x" * 65, "spaces are unsafe"):
            candidate = copy.deepcopy(fixture)
            candidate["error"]["correlation_id"] = invalid
            errors = validate_instance(
                self.document,
                {"$ref": "#/components/schemas/InternalErrorResponse"},
                candidate,
            )
            self.assertTrue(errors, invalid)

    def test_error_messages_and_codes_are_exact_allowlists(self) -> None:
        fixture = self.fixture("internal-error-500.json")
        fixture["error"]["message"] = "C:\\Users\\person\\secret.py: SELECT *"
        errors = validate_instance(
            self.document,
            {"$ref": "#/components/schemas/InternalErrorResponse"},
            fixture,
        )
        self.assertTrue(errors)


if __name__ == "__main__":
    unittest.main()
