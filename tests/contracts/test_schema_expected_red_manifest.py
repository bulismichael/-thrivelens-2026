from __future__ import annotations

import copy
import unittest

from scripts.contracts.contract_validation import (
    ContractValidationError,
    MANIFEST_PATH,
    load_json,
    validate_expected_red_manifest,
)


class ExpectedRedManifestSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = load_json(MANIFEST_PATH)

    def test_canonical_manifest_passes(self) -> None:
        validate_expected_red_manifest(self.manifest)

    def test_unknown_root_or_entry_keys_are_rejected(self) -> None:
        root = copy.deepcopy(self.manifest)
        root["shell"] = True
        with self.assertRaises(ContractValidationError):
            validate_expected_red_manifest(root)
        entry = copy.deepcopy(self.manifest)
        entry["entries"][0]["allow_failure"] = True
        with self.assertRaises(ContractValidationError):
            validate_expected_red_manifest(entry)

    def test_duplicate_or_unknown_ids_are_rejected(self) -> None:
        duplicate = copy.deepcopy(self.manifest)
        duplicate["entries"][1]["id"] = duplicate["entries"][0]["id"]
        with self.assertRaises(ContractValidationError):
            validate_expected_red_manifest(duplicate)
        unknown = copy.deepcopy(self.manifest)
        unknown["entries"][0]["id"] = "TL-R0-999-UNKNOWN"
        with self.assertRaises(ContractValidationError):
            validate_expected_red_manifest(unknown)

    def test_shell_text_substitution_is_rejected(self) -> None:
        candidate = copy.deepcopy(self.manifest)
        candidate["entries"][0]["argv"] = ["pwsh", "-Command", "exit 1"]
        with self.assertRaises(ContractValidationError):
            validate_expected_red_manifest(candidate)

    def test_owner_test_id_timeout_marker_and_green_command_are_exact(self) -> None:
        for field, value in (
            ("owner", "TL-R0-008"),
            ("test_ids", ["different.test"]),
            ("timeout_seconds", 300),
            ("expected_missing_behavior_marker", "spoof"),
            ("future_green_command", "exit 0"),
        ):
            candidate = copy.deepcopy(self.manifest)
            candidate["entries"][0][field] = value
            with self.assertRaises(ContractValidationError, msg=field):
                validate_expected_red_manifest(candidate)


if __name__ == "__main__":
    unittest.main()
