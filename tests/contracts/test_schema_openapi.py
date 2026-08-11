from __future__ import annotations

import copy
import unittest

from scripts.contracts.contract_validation import (
    ContractValidationError,
    EXPECTED_EFFECTIVE_ROUTES,
    OPENAPI_PATH,
    load_json,
    validate_openapi,
)


class OpenApiContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.document = load_json(OPENAPI_PATH)

    def assert_rejected(self, mutation) -> None:  # type: ignore[no-untyped-def]
        candidate = copy.deepcopy(self.document)
        mutation(candidate)
        with self.assertRaises(ContractValidationError):
            validate_openapi(candidate)

    def test_canonical_document_passes(self) -> None:
        validate_openapi(self.document)

    def test_relative_server_composes_exactly_four_effective_routes(self) -> None:
        effective = {self.document["servers"][0]["url"] + path for path in self.document["paths"]}
        self.assertEqual(effective, set(EXPECTED_EFFECTIVE_ROUTES))

    def test_only_get_and_stable_unique_operation_ids_exist(self) -> None:
        ids = []
        for path_item in self.document["paths"].values():
            self.assertEqual(set(path_item), {"get"})
            ids.append(path_item["get"]["operationId"])
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(
            set(ids),
            {"getHealthLive", "getHealthReady", "getSystemStatus", "getSystemVersion"},
        )

    def test_only_optional_bounded_correlation_header_is_accepted(self) -> None:
        for path_item in self.document["paths"].values():
            operation = path_item["get"]
            self.assertNotIn("requestBody", operation)
            self.assertEqual(
                operation["parameters"],
                [{"$ref": "#/components/parameters/CorrelationIdRequest"}],
            )
            self.assertEqual(operation["security"], [])

    def test_default_response_is_rejected(self) -> None:
        self.assert_rejected(
            lambda doc: doc["paths"]["/health/live"]["get"]["responses"].update(
                {"default": doc["paths"]["/health/live"]["get"]["responses"]["500"]}
            )
        )

    def test_absolute_or_duplicate_api_base_is_rejected(self) -> None:
        self.assert_rejected(lambda doc: doc["servers"][0].update({"url": "http://127.0.0.1:8000/api/v1"}))
        self.assert_rejected(lambda doc: doc["servers"][0].update({"url": "/api/v1/api/v1"}))

    def test_extra_path_or_method_is_rejected(self) -> None:
        self.assert_rejected(lambda doc: doc["paths"].update({"/future": doc["paths"]["/health/live"]}))
        self.assert_rejected(
            lambda doc: doc["paths"]["/health/live"].update(
                {"post": doc["paths"]["/health/live"]["get"]}
            )
        )

    def test_inline_live_headers_are_validated(self) -> None:
        self.assert_rejected(
            lambda doc: doc["paths"]["/health/live"]["get"]["responses"]["200"]["headers"][
                "Cache-Control"
            ]["schema"].update({"enum": ["public"]})
        )

    def test_response_schema_substitution_is_rejected(self) -> None:
        self.assert_rejected(
            lambda doc: doc["paths"]["/system/status"]["get"]["responses"]["200"]["content"]
            ["application/json"]["schema"].update(
                {"$ref": "#/components/schemas/LivenessResponse"}
            )
        )

    def test_external_and_cyclic_schema_references_are_rejected(self) -> None:
        self.assert_rejected(
            lambda doc: doc["components"]["schemas"]["CorrelationId"].clear()
            or doc["components"]["schemas"]["CorrelationId"].update(
                {"$ref": "https://example.invalid/schema.json"}
            )
        )
        self.assert_rejected(
            lambda doc: doc["components"]["schemas"]["CorrelationId"].clear()
            or doc["components"]["schemas"]["CorrelationId"].update(
                {"$ref": "#/components/schemas/CorrelationId"}
            )
        )

    def test_every_object_is_recursively_closed_and_required(self) -> None:
        self.assert_rejected(
            lambda doc: doc["components"]["schemas"]["ReadyComponents"].update(
                {"additionalProperties": True}
            )
        )
        self.assert_rejected(
            lambda doc: doc["components"]["schemas"]["ReadyComponents"].update(
                {"required": ["app_service"]}
            )
        )

    def test_nullable_escape_hatch_is_rejected(self) -> None:
        self.assert_rejected(
            lambda doc: doc["components"]["schemas"]["CorrelationId"].update({"nullable": True})
        )

    def test_semantic_shadow_keys_at_root_components_and_operation_are_rejected(self) -> None:
        self.assert_rejected(lambda doc: doc.update({"x-production-enabled": True}))
        self.assert_rejected(
            lambda doc: doc["components"].update(
                {"securitySchemes": {"shadow": {"type": "http", "scheme": "bearer"}}}
            )
        )
        self.assert_rejected(
            lambda doc: doc["paths"]["/health/live"]["get"].update({"x-cors-enabled": True})
        )

    def test_unknown_info_server_response_and_schema_keys_are_rejected(self) -> None:
        self.assert_rejected(lambda doc: doc["info"].update({"license": {"name": "shadow"}}))
        self.assert_rejected(lambda doc: doc["servers"][0].update({"variables": {}}))
        self.assert_rejected(
            lambda doc: doc["paths"]["/health/live"]["get"]["responses"]["200"].update(
                {"links": {}}
            )
        )
        self.assert_rejected(
            lambda doc: doc["components"]["schemas"]["CorrelationId"].update(
                {"example": "shadow-id"}
            )
        )

    def test_unknown_header_parameter_content_and_media_type_keys_are_rejected(self) -> None:
        self.assert_rejected(
            lambda doc: doc["paths"]["/health/live"]["get"]["responses"]["200"]["headers"][
                "Cache-Control"
            ].update({"example": "no-store"})
        )
        self.assert_rejected(
            lambda doc: doc["components"]["parameters"]["CorrelationIdRequest"].update(
                {"allowEmptyValue": True}
            )
        )
        self.assert_rejected(
            lambda doc: doc["paths"]["/health/live"]["get"]["responses"]["200"]["content"].update(
                {"text/plain": {"schema": {"type": "string"}}}
            )
        )
        self.assert_rejected(
            lambda doc: doc["paths"]["/health/live"]["get"]["responses"]["200"]["content"][
                "application/json"
            ].update({"example": {"status": "alive"}})
        )

    def test_allowed_key_with_noncanonical_value_is_rejected_by_fingerprint(self) -> None:
        self.assert_rejected(
            lambda doc: doc["paths"]["/health/live"]["get"].update(
                {"summary": "A bounded but noncanonical shadow summary"}
            )
        )


if __name__ == "__main__":
    unittest.main()
