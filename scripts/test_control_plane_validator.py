from __future__ import annotations

import copy
import json
import struct
import unittest
import zlib
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch

from scripts import validate_control_plane as validator


class ControlPlaneValidatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.texts = validator.validate_required_files()
        cls.graph = validator.load_json_yaml("docs/program/TASK_GRAPH.yaml")
        cls.registry = validator.load_json_yaml("docs/program/FEATURE_REGISTRY.yaml")
        cls.budget = validator.load_json_yaml("config/resource-budget.json")
        cls.approval_states = validator.validate_decisions(cls.texts)

    def task_map(self, graph: dict | None = None) -> dict[str, dict]:
        source = graph if graph is not None else self.graph
        return {task["id"]: task for task in source["tasks"]}

    def valid_test_report(self, task: dict, commit: str = "44515a0") -> dict:
        return {
            "schema_version": 1,
            "evidence_type": "test_report",
            "task_id": task["id"],
            "commit": commit,
            "generated_at": "2026-08-11T12:00:00Z",
            "environment": {"os": "windows", "architecture": "x86_64", "execution_context": "test_fixture"},
            "tool_versions": {"python": "3.11.9"},
            "duration_seconds": 1.0,
            "resource_status": {"cap_gb": 18, "accounted_bytes": 1, "status": "OK", "host_free_memory_gb": 1.0},
            "commands": [
                {"command": command, "exit_code": 0, "duration_seconds": 0.1, "result_count": 1, "sanitized_failure": None}
                for command in task["required_tests"]
            ],
            "summary": "Synthetic validator lineage fixture; not release evidence.",
        }

    def valid_approval(self, decision_id: str, feature: dict, commits: list[str]) -> dict:
        event_id = f"{decision_id}-G-0001"
        resolved_commits = [validator.git_resolve_commit(commit) for commit in commits]
        self.assertTrue(all(resolved_commits))
        grant = {
            "event_id": event_id,
            "event": "GRANT",
            "approved_by": ["Jane Doe"],
            "approval_date": "2026-08-11",
            "feature_id": feature["id"],
            "release": feature["release"],
            "artifact_commits": resolved_commits,
            "jurisdiction": "Development governance scope",
            "scope": "Synthetic validator fixture scope",
            "limitations": "Synthetic validator fixture only",
            "evidence_reviewed": ["docs/program/evidence/test-reports/TL-R0-001/synthetic.json"],
            "expires_or_review_on": "REVIEW_ON_ARTIFACT_OR_SCOPE_CHANGE",
        }
        ledger = {
            "schema_version": 2,
            "evidence_type": "human_approval_ledger",
            "decision_id": decision_id,
            "events": [grant],
        }
        return {
            "state": "APPROVED",
            "ledger_path": f"docs/program/evidence/approvals/{decision_id}.json",
            "ledger": ledger,
            "active_grants": {event_id: grant},
        }

    def valid_dataset_report(self, feature_id: str, commit: str = "44515a0") -> dict:
        return {
            "schema_version": 1,
            "evidence_type": "dataset_report",
            "feature_id": feature_id,
            "commit": commit,
            "dataset_id": "fixture",
            "dataset_version": "v1",
            "license_decision_id": "TL-D-012",
            "metrics": {"accuracy": 0.9},
            "thresholds": {"accuracy": {"operator": "gte", "value": 0.8}},
            "result": "PASS",
            "recorded_at": "2026-08-11T12:00:00Z",
        }

    def valid_device_report(
        self,
        feature_id: str,
        commit: str = "44515a0",
        surface: str = "android_physical",
    ) -> dict:
        return {
            "schema_version": 1,
            "evidence_type": "device_report",
            "feature_id": feature_id,
            "commit": commit,
            "surface": surface,
            "device_class": "emulator" if surface == "android_emulator" else "phone",
            "os_version": "14.0",
            "app_artifact_hash": f"sha256:{'0' * 64}",
            "tests": ["heartbeat_ready", "heartbeat_degraded"],
            "result": "PASS",
            "recorded_at": "2026-08-11T12:00:00Z",
        }

    def valid_review(self, task: dict, role: str, test_reference: str = "report", commit: str = "44515a0") -> dict:
        return {
            "schema_version": 1,
            "evidence_type": "independent_review",
            "scope_id": task["id"],
            "reviewed_commit": commit,
            "reviewer_role": role,
            "reviewed_at": "2026-08-11T12:00:00Z",
            "findings": [],
            "findings_dispositioned": True,
            "test_evidence": [test_reference],
            "recommendation": "PASS",
            "summary": "Synthetic validator lineage fixture; not release evidence.",
        }

    def png_chunk(self, chunk_type: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + chunk_type
            + payload
            + struct.pack(">I", zlib.crc32(chunk_type + payload) & 0xFFFFFFFF)
        )

    def valid_png(
        self,
        extra_chunks: list[bytes] | None = None,
        *,
        width: int = 1,
        height: int = 1,
        bit_depth: int = 8,
        color_type: int = 6,
        interlace: int = 0,
        raw_scanlines: bytes | None = None,
        idat_payloads: list[bytes] | None = None,
    ) -> bytes:
        ihdr = struct.pack(">IIBBBBB", width, height, bit_depth, color_type, 0, 0, interlace)
        if raw_scanlines is None:
            raw_scanlines = b"\x00\x00\x00\x00\x00"
        payloads = idat_payloads or [zlib.compress(raw_scanlines)]
        return (
            b"\x89PNG\r\n\x1a\n"
            + self.png_chunk(b"IHDR", ihdr)
            + b"".join(extra_chunks or [])
            + b"".join(self.png_chunk(b"IDAT", payload) for payload in payloads)
            + self.png_chunk(b"IEND", b"")
        )

    def lifecycle_task(self, canonical: str) -> dict:
        task = copy.deepcopy(self.graph["tasks"][0])
        task["status"] = "VERIFIED"
        task["blockers"] = []
        task["evidence"]["commits"] = [canonical]
        task["evidence"]["test_reports"] = [
            "docs/program/evidence/test-reports/TL-R0-001/report.json"
        ]
        task["evidence"]["reviews"] = [
            "docs/program/evidence/reviews/TL-R0-001/review.json"
        ]
        return task

    def test_current_control_plane_passes(self) -> None:
        tasks, _ = validator.validate_tasks(copy.deepcopy(self.graph), self.texts)
        features = validator.validate_features(
            copy.deepcopy(self.registry), {task["id"]: task for task in tasks}, self.approval_states
        )
        self.assertGreater(len(features), 0)

    def test_owner_cannot_review_own_task(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][0]["required_reviewers"].append(graph["tasks"][0]["owner_agent"])
        with self.assertRaisesRegex(validator.ControlPlaneError, "owner cannot review"):
            validator.validate_tasks(graph, self.texts)

    def test_parallel_path_collision_is_rejected(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][1]["owned_paths"].append("parallel-collision/**")
        graph["tasks"][2]["owned_paths"].append("parallel-collision/output.json")
        with self.assertRaisesRegex(validator.ControlPlaneError, "Parallel path collision"):
            validator.validate_tasks(graph, self.texts)

    def test_active_task_with_unverified_dependency_is_rejected(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][0]["status"] = "READY"
        graph["tasks"][0]["blockers"] = []
        graph["tasks"][1]["status"] = "READY"
        with self.assertRaisesRegex(validator.ControlPlaneError, "unverified dependencies"):
            validator.validate_tasks(graph, self.texts)

    def test_unavailable_test_script_is_rejected(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][1]["required_tests"].append("python scripts/does_not_exist_xyz.py")
        with self.assertRaisesRegex(validator.ControlPlaneError, "unavailable script"):
            validator.validate_tasks(graph, self.texts)

    def test_shared_lock_outside_integration_is_rejected(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][1]["owned_paths"].append("services/api/unsafe.lock")
        with self.assertRaisesRegex(validator.ControlPlaneError, "shared paths outside integration"):
            validator.validate_tasks(graph, self.texts)

    def test_verified_task_needs_test_evidence(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][0]["status"] = "VERIFIED"
        graph["tasks"][0]["blockers"] = []
        graph["tasks"][0]["evidence"]["test_reports"] = []
        with patch.object(validator, "validate_verification_candidate"), patch.object(validator, "git_commit_paths", return_value=["scripts/validate_control_plane.py"]), self.assertRaisesRegex(validator.ControlPlaneError, "needs test evidence"):
            validator.validate_tasks(graph, self.texts)

    def test_verified_task_rejects_missing_commit(self) -> None:
        graph = copy.deepcopy(self.graph)
        task = graph["tasks"][0]
        task["status"] = "VERIFIED"
        task["blockers"] = []
        task["evidence"]["commits"] = ["ffffffffffffffffffffffffffffffffffffffff"]
        task["evidence"]["test_reports"] = ["scripts/validate_control_plane.py"]
        with self.assertRaisesRegex(validator.ControlPlaneError, "missing commit"):
            validator.validate_tasks(graph, self.texts)

    def test_verified_task_rejects_missing_report(self) -> None:
        graph = copy.deepcopy(self.graph)
        task = graph["tasks"][0]
        task["status"] = "VERIFIED"
        task["blockers"] = []
        task["evidence"]["commits"] = ["44515a0"]
        task["evidence"]["test_reports"] = ["docs/program/evidence/test-reports/TL-R0-001/missing.json"]
        task["evidence"]["reviews"] = ["docs/program/evidence/reviews/TL-R0-001/missing.json"]
        with patch.object(validator, "validate_verification_candidate"), patch.object(validator, "git_commit_paths", return_value=["scripts/validate_control_plane.py"]), self.assertRaisesRegex(validator.ControlPlaneError, "staged or tracked"):
            validator.validate_tasks(graph, self.texts)

    def test_verified_task_requires_every_required_command(self) -> None:
        graph = copy.deepcopy(self.graph)
        task = graph["tasks"][0]
        task["status"] = "VERIFIED"
        task["blockers"] = []
        task["evidence"]["commits"] = ["44515a0"]
        report_path = "docs/program/evidence/test-reports/TL-R0-001/report.json"
        task["evidence"]["test_reports"] = [report_path]
        task["evidence"]["reviews"] = [
            "docs/program/evidence/reviews/TL-R0-001/product.json",
            "docs/program/evidence/reviews/TL-R0-001/quality.json",
            "docs/program/evidence/reviews/TL-R0-001/security.json",
        ]
        report = self.valid_test_report(task)
        report["commands"].pop()
        documents = {
            report_path: report,
            task["evidence"]["reviews"][0]: self.valid_review(task, "product_systems_architect", report_path),
            task["evidence"]["reviews"][1]: self.valid_review(task, "quality_engineer", report_path),
            task["evidence"]["reviews"][2]: self.valid_review(task, "security_privacy_reviewer", report_path),
        }
        with patch.object(validator, "validate_verification_candidate"), patch.object(validator, "git_commit_paths", return_value=["scripts/validate_control_plane.py"]), patch.object(validator, "load_typed_evidence", side_effect=lambda reference, _: documents[reference]), self.assertRaisesRegex(validator.ControlPlaneError, "exact required command order and multiplicity"):
            validator.validate_tasks(graph, self.texts)

    def test_verified_task_allows_only_one_canonical_commit(self) -> None:
        graph = copy.deepcopy(self.graph)
        task = graph["tasks"][0]
        task["status"] = "VERIFIED"
        task["blockers"] = []
        task["evidence"]["commits"] = ["fc57594", "44515a0"]
        task["evidence"]["test_reports"] = ["docs/program/evidence/test-reports/TL-R0-001/report.json"]
        task["evidence"]["reviews"] = ["docs/program/evidence/reviews/TL-R0-001/product.json", "docs/program/evidence/reviews/TL-R0-001/quality.json", "docs/program/evidence/reviews/TL-R0-001/security.json"]
        with self.assertRaisesRegex(validator.ControlPlaneError, "one canonical verification commit"):
            validator.validate_tasks(graph, self.texts)

    def test_verification_candidate_requires_head_clean_bytes_and_no_conflicts(self) -> None:
        commit = "a" * 40
        with patch.object(validator, "git_resolve_commit", return_value=commit), patch.object(
            validator, "git_head_commit", return_value="b" * 40
        ), self.assertRaisesRegex(validator.ControlPlaneError, "exact checked-out integration candidate"):
            validator.validate_verification_candidate(commit)
        with patch.object(validator, "git_resolve_commit", return_value=commit), patch.object(
            validator, "git_head_commit", return_value=commit
        ), patch.object(validator, "git_unmerged_paths", return_value={"conflicted.json"}), self.assertRaisesRegex(
            validator.ControlPlaneError, "conflicted Git index"
        ):
            validator.validate_verification_candidate(commit)
        with patch.object(validator, "git_resolve_commit", return_value=commit), patch.object(
            validator, "git_head_commit", return_value=commit
        ), patch.object(validator, "git_unmerged_paths", return_value=set()), patch.object(
            validator, "git_worktree_changes", return_value={"docs/program/TASK_GRAPH.yaml"}
        ), self.assertRaisesRegex(validator.ControlPlaneError, "working-tree bytes"):
            validator.validate_verification_candidate(commit)
        with patch.object(validator, "git_resolve_commit", return_value=commit), patch.object(
            validator, "git_head_commit", return_value=commit
        ), patch.object(validator, "git_unmerged_paths", return_value=set()), patch.object(
            validator, "git_worktree_changes", return_value=set()
        ), patch.object(
            validator, "git_staged_changes", return_value={"scripts/validate_control_plane.py"}
        ), self.assertRaisesRegex(validator.ControlPlaneError, "candidate bytes differ"):
            validator.validate_verification_candidate(commit)
        with patch.object(validator.subprocess, "run", side_effect=OSError), self.assertRaisesRegex(
            validator.ControlPlaneError, "Cannot inspect exact Git candidate state"
        ):
            validator.git_path_output(["diff", "--name-only", "-z"])

    def test_verified_commit_cannot_change_unowned_or_forbidden_paths(self) -> None:
        graph = copy.deepcopy(self.graph)
        task = graph["tasks"][0]
        task["status"] = "VERIFIED"
        task["blockers"] = []
        task["evidence"]["commits"] = ["44515a0"]
        report_path = "docs/program/evidence/test-reports/TL-R0-001/report.json"
        task["evidence"]["test_reports"] = [report_path]
        task["evidence"]["reviews"] = [
            "docs/program/evidence/reviews/TL-R0-001/product.json",
            "docs/program/evidence/reviews/TL-R0-001/quality.json",
            "docs/program/evidence/reviews/TL-R0-001/security.json",
        ]
        documents = {report_path: self.valid_test_report(task)}
        for path, role in zip(task["evidence"]["reviews"], task["required_reviewers"], strict=True):
            documents[path] = self.valid_review(task, role, report_path)
        for changed, pattern in (("outside/file.txt", "outside its ownership"), ("services/api/src/forbidden.py", "outside its ownership|forbidden")):
            with self.subTest(changed=changed), patch.object(validator, "validate_verification_candidate"), patch.object(
                validator, "git_commit_paths", return_value=["scripts/validate_control_plane.py", changed]
            ), patch.object(validator, "load_typed_evidence", side_effect=lambda reference, _: documents[reference]), self.assertRaisesRegex(
                validator.ControlPlaneError, pattern
            ):
                validator.validate_tasks(graph, self.texts)

    def test_verified_commands_preserve_order_and_multiplicity(self) -> None:
        for mutation in ("reverse", "duplicate"):
            graph = copy.deepcopy(self.graph)
            task = graph["tasks"][0]
            task["status"] = "VERIFIED"
            task["blockers"] = []
            task["evidence"]["commits"] = ["44515a0"]
            report_path = "docs/program/evidence/test-reports/TL-R0-001/report.json"
            task["evidence"]["test_reports"] = [report_path]
            task["evidence"]["reviews"] = [
                "docs/program/evidence/reviews/TL-R0-001/product.json",
                "docs/program/evidence/reviews/TL-R0-001/quality.json",
                "docs/program/evidence/reviews/TL-R0-001/security.json",
            ]
            report = self.valid_test_report(task)
            if mutation == "reverse":
                report["commands"] = list(reversed(report["commands"]))
            else:
                report["commands"].append(copy.deepcopy(report["commands"][-1]))
            documents = {report_path: report}
            for path, role in zip(task["evidence"]["reviews"], task["required_reviewers"], strict=True):
                documents[path] = self.valid_review(task, role, report_path)
            with self.subTest(mutation=mutation), patch.object(validator, "validate_verification_candidate"), patch.object(
                validator, "git_commit_paths", return_value=["scripts/validate_control_plane.py"]
            ), patch.object(validator, "load_typed_evidence", side_effect=lambda reference, _: documents[reference]), self.assertRaisesRegex(
                validator.ControlPlaneError, "order and multiplicity"
            ):
                validator.validate_tasks(graph, self.texts)

    def test_verified_task_security_review_covers_every_recorded_report(self) -> None:
        graph = copy.deepcopy(self.graph)
        task = graph["tasks"][0]
        task["status"] = "VERIFIED"
        task["blockers"] = []
        task["evidence"]["commits"] = ["44515a0"]
        reports = [
            "docs/program/evidence/test-reports/TL-R0-001/part-1.json",
            "docs/program/evidence/test-reports/TL-R0-001/part-2.json",
        ]
        task["evidence"]["test_reports"] = reports
        task["evidence"]["reviews"] = [
            "docs/program/evidence/reviews/TL-R0-001/product.json",
            "docs/program/evidence/reviews/TL-R0-001/quality.json",
            "docs/program/evidence/reviews/TL-R0-001/security.json",
        ]
        first = self.valid_test_report(task)
        second = self.valid_test_report(task)
        split_at = len(first["commands"]) // 2
        first["commands"] = first["commands"][:split_at]
        second["commands"] = second["commands"][split_at:]
        documents = {reports[0]: first, reports[1]: second}
        for path, role in zip(task["evidence"]["reviews"], task["required_reviewers"], strict=True):
            review = self.valid_review(task, role, reports[0])
            if role != "security_privacy_reviewer":
                review["test_evidence"] = reports
            documents[path] = review
        with patch.object(validator, "validate_verification_candidate"), patch.object(
            validator, "git_commit_paths", return_value=["scripts/validate_control_plane.py"]
        ), patch.object(
            validator, "load_typed_evidence", side_effect=lambda reference, _: documents[reference]
        ), self.assertRaisesRegex(validator.ControlPlaneError, "security review must cover every recorded task report"):
            validator.validate_tasks(graph, self.texts)

    def test_review_cannot_use_tests_from_another_commit(self) -> None:
        graph = copy.deepcopy(self.graph)
        task = graph["tasks"][0]
        task["status"] = "VERIFIED"
        task["blockers"] = []
        task["evidence"]["commits"] = ["44515a0"]
        report_path = "docs/program/evidence/test-reports/TL-R0-001/report.json"
        task["evidence"]["test_reports"] = [report_path]
        task["evidence"]["reviews"] = ["docs/program/evidence/reviews/TL-R0-001/product.json", "docs/program/evidence/reviews/TL-R0-001/quality.json", "docs/program/evidence/reviews/TL-R0-001/security.json"]
        documents = {
            report_path: self.valid_test_report(task, commit="fc57594"),
            task["evidence"]["reviews"][0]: self.valid_review(task, "product_systems_architect", report_path),
            task["evidence"]["reviews"][1]: self.valid_review(task, "quality_engineer", report_path),
            task["evidence"]["reviews"][2]: self.valid_review(task, "security_privacy_reviewer", report_path),
        }
        with patch.object(validator, "validate_verification_candidate"), patch.object(validator, "git_commit_paths", return_value=["scripts/validate_control_plane.py"]), patch.object(validator, "load_typed_evidence", side_effect=lambda reference, _: documents[reference]), self.assertRaisesRegex(validator.ControlPlaneError, "stale test evidence"):
            validator.validate_tasks(graph, self.texts)

    def test_git_internal_and_source_files_cannot_be_test_reports(self) -> None:
        for relative, pattern in ((".git/HEAD", "integration staging route|Git internals|approved roots"), ("scripts/validate_control_plane.py", "integration staging route|approved roots")):
            graph = copy.deepcopy(self.graph)
            task = graph["tasks"][0]
            task["status"] = "VERIFIED"
            task["blockers"] = []
            task["evidence"]["commits"] = ["44515a0"]
            task["evidence"]["test_reports"] = [relative]
            task["evidence"]["reviews"] = ["docs/program/evidence/reviews/TL-R0-001/missing.json"]
            with self.subTest(relative=relative), patch.object(validator, "validate_verification_candidate"), patch.object(validator, "git_commit_paths", return_value=["scripts/validate_control_plane.py"]), self.assertRaisesRegex(validator.ControlPlaneError, pattern):
                validator.validate_tasks(graph, self.texts)

    def test_untracked_file_cannot_be_test_evidence(self) -> None:
        relative = "docs/program/evidence/test-reports/TL-R0-001/untracked-validator-fixture.json"
        path = validator.ROOT / Path(relative)
        created_parent = not path.parent.exists()
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            path.write_text('{"schema_version": 1, "evidence_type": "test_report"}', encoding="utf-8")
            graph = copy.deepcopy(self.graph)
            task = graph["tasks"][0]
            task["status"] = "VERIFIED"
            task["blockers"] = []
            task["evidence"]["commits"] = ["44515a0"]
            task["evidence"]["test_reports"] = [relative]
            task["evidence"]["reviews"] = ["docs/program/evidence/reviews/TL-R0-001/missing.json"]
            with patch.object(validator, "validate_verification_candidate"), patch.object(validator, "git_commit_paths", return_value=["scripts/validate_control_plane.py"]), self.assertRaisesRegex(validator.ControlPlaneError, "staged or tracked"):
                validator.validate_tasks(graph, self.texts)
        finally:
            path.unlink(missing_ok=True)
            if created_parent:
                current = path.parent
                evidence_root = validator.ROOT / "docs/program/evidence"
                while current != evidence_root and current.exists() and not any(current.iterdir()):
                    parent = current.parent
                    current.rmdir()
                    current = parent

    def test_typed_evidence_rejects_wrong_document_type(self) -> None:
        document = {"schema_version": 1, "evidence_type": "independent_review"}
        with self.assertRaisesRegex(validator.ControlPlaneError, "type confusion"):
            validator.validate_evidence_document(document, "test_report")

    def test_evidence_schemas_reject_underspecified_records(self) -> None:
        records = (
            ({"schema_version": 1, "evidence_type": "test_report", "task_id": "TL-R0-001", "commit": "44515a0", "commands": [{"command": "anything", "exit_code": 0}]}, "test_report", "fields drifted"),
            ({"schema_version": 2, "evidence_type": "human_approval_ledger", "decision_id": "TL-D-001"}, "human_approval_ledger", "fields drifted"),
            ({"schema_version": 1, "evidence_type": "independent_review", "scope_id": "TL-R0-001", "reviewed_commit": "44515a0", "reviewer_role": "quality_engineer", "reviewed_at": "2026-08-11T12:00:00Z", "findings": [], "findings_dispositioned": True, "test_evidence": [1], "recommendation": "PASS", "summary": "fixture"}, "independent_review", "allowlisted test-report"),
        )
        for document, evidence_type, pattern in records:
            with self.subTest(evidence_type=evidence_type), self.assertRaisesRegex(validator.ControlPlaneError, pattern):
                validator.validate_evidence_document(document, evidence_type)
        feature = self.registry["features"][1]
        for field, value in (("approved_by", [{}]), ("artifact_commits", [True])):
            document = self.valid_approval("TL-D-013", feature, ["44515a0"])["ledger"]
            document["events"][0][field] = value
            with self.subTest(field=field), self.assertRaises(validator.ControlPlaneError):
                validator.validate_evidence_document(document, "human_approval_ledger")

    def test_evidence_nested_fields_are_allowlisted_and_recursively_sanitized(self) -> None:
        task = self.graph["tasks"][0]
        extra_environment = self.valid_test_report(task)
        extra_environment["environment"]["api_token"] = "synthetic"
        absolute_path = self.valid_test_report(task)
        absolute_path["summary"] = r"Synthetic path C:\Users\example\private"
        secret_value = self.valid_test_report(task)
        secret_value["summary"] = "SENTINEL_NOT_A_REAL_SECRET"
        failure_text = self.valid_test_report(task)
        failure_text["commands"][0]["sanitized_failure"] = "unexpected"
        for document, pattern in (
            (extra_environment, "environment fields drifted"),
            (absolute_path, "absolute private path"),
            (secret_value, "secret-like content"),
            (failure_text, "null sanitized_failure"),
        ):
            with self.subTest(pattern=pattern), self.assertRaisesRegex(validator.ControlPlaneError, pattern):
                validator.validate_evidence_document(document, "test_report")

    def test_numeric_evidence_fields_reject_booleans_and_float_integers(self) -> None:
        task = self.graph["tasks"][0]
        mutations = []
        schema = self.valid_test_report(task)
        schema["schema_version"] = True
        mutations.append(schema)
        exit_code = self.valid_test_report(task)
        exit_code["commands"][0]["exit_code"] = False
        mutations.append(exit_code)
        result_count = self.valid_test_report(task)
        result_count["commands"][0]["result_count"] = True
        mutations.append(result_count)
        accounted = self.valid_test_report(task)
        accounted["resource_status"]["accounted_bytes"] = 1.0
        mutations.append(accounted)
        cap = self.valid_test_report(task)
        cap["resource_status"]["cap_gb"] = 18.0
        mutations.append(cap)
        for document in mutations:
            with self.subTest(document=document), self.assertRaises(validator.ControlPlaneError):
                validator.validate_evidence_document(document, "test_report")

    def test_evidence_rejects_git_symlink_mode(self) -> None:
        with self.assertRaisesRegex(validator.ControlPlaneError, "symlink"):
            validator.validate_evidence_git_mode("120000")

    def test_evidence_requires_one_regular_conflict_free_stage_zero_entry(self) -> None:
        path = "docs/program/evidence/test-reports/TL-R0-001/report.json"
        object_id = "a" * 40
        with self.assertRaisesRegex(validator.ControlPlaneError, "conflict-free stage-0"):
            validator.validate_evidence_git_entries([("100644", object_id, 2, path)], path)
        with self.assertRaisesRegex(validator.ControlPlaneError, "conflict-free stage-0"):
            validator.validate_evidence_git_entries(
                [("100644", object_id, 1, path), ("100644", "b" * 40, 2, path)], path
            )
        self.assertEqual(validator.validate_evidence_git_entries([("100644", object_id, 0, path)], path), object_id)

    def test_typed_evidence_is_loaded_from_stage_zero_blob(self) -> None:
        task = self.graph["tasks"][0]
        document = self.valid_test_report(task)
        encoded = json.dumps(document).encode("utf-8")
        with patch.object(
            validator,
            "validate_indexed_evidence",
            return_value=(Path("working-tree-content-is-not-read.json"), "a" * 40),
        ), patch.object(validator, "git_blob_size", return_value=len(encoded)), patch.object(
            validator, "read_git_blob", return_value=encoded
        ):
            loaded = validator.load_typed_evidence("docs/program/evidence/test-reports/TL-R0-001/report.json", "test_report")
        self.assertEqual(loaded, document)

    def test_typed_evidence_blob_size_is_capped_before_read(self) -> None:
        with patch.object(
            validator, "git_blob_size", return_value=validator.MAX_TYPED_EVIDENCE_BYTES + 1
        ), patch.object(validator, "read_git_blob") as read_blob, self.assertRaisesRegex(
            validator.ControlPlaneError, "bounded typed-evidence policy"
        ):
            validator.load_json_blob("a" * 40, "historical typed evidence")
        read_blob.assert_not_called()

    def test_every_task_retains_exact_independent_evidence_staging_routes(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][3]["integration_owned_paths"].remove(
            "docs/program/evidence/reviews/TL-R0-004/**"
        )
        with self.assertRaisesRegex(validator.ControlPlaneError, "integration-owned reviews staging route"):
            validator.validate_tasks(graph, self.texts)

    def test_control_task_retains_gitignore_ownership(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][0]["status"] = "READY"
        graph["tasks"][0]["blockers"] = []
        for task in graph["tasks"][1:3]:
            task["status"] = "BLOCKED"
            task["blockers"] = ["Synthetic dependency fixture"]
        graph["tasks"][0]["owned_paths"].remove(".gitignore")
        with self.assertRaisesRegex(validator.ControlPlaneError, "own its staged .gitignore"):
            validator.validate_tasks(graph, self.texts)

    def test_pending_approval_blocks_human_attested_feature_state(self) -> None:
        registry = copy.deepcopy(self.registry)
        registry["features"][1]["state"] = "DOMAIN_REVIEWED"
        tasks = copy.deepcopy(self.task_map())
        tasks["TL-R0-001"]["status"] = "VERIFIED"
        with self.assertRaisesRegex(validator.ControlPlaneError, "feature-specific human approval"):
            validator.validate_features(registry, tasks, self.approval_states)

    def test_security_review_is_independent_but_needs_review_evidence(self) -> None:
        registry = copy.deepcopy(self.registry)
        registry["features"][1]["state"] = "SECURITY_REVIEWED"
        tasks = copy.deepcopy(self.task_map())
        tasks["TL-R0-001"]["status"] = "VERIFIED"
        with self.assertRaisesRegex(validator.ControlPlaneError, "independent review evidence"):
            validator.validate_features(registry, tasks, self.approval_states)

    def test_security_review_requires_security_role_and_current_lineage(self) -> None:
        for role, commit, pattern in (
            ("ux_design_director", "44515a0", "security_privacy_reviewer"),
            ("security_privacy_reviewer", "fc57594", "stale"),
        ):
            registry = copy.deepcopy(self.registry)
            feature = registry["features"][1]
            feature["state"] = "SECURITY_REVIEWED"
            feature["evidence"] = ["review:review"]
            tasks = copy.deepcopy(self.task_map())
            tasks["TL-R0-001"]["status"] = "VERIFIED"
            tasks["TL-R0-001"]["evidence"]["commits"] = ["44515a0"]
            tasks["TL-R0-001"]["evidence"]["test_reports"] = ["report"]
            report = self.valid_test_report(tasks["TL-R0-001"], commit=commit)
            review = self.valid_review(tasks["TL-R0-001"], role, commit=commit)
            review["scope_id"] = feature["id"]
            documents = {"review": review, "report": report}
            with self.subTest(role=role, commit=commit), patch.object(
                validator, "load_typed_evidence", side_effect=lambda reference, _: documents[reference]
            ), self.assertRaisesRegex(validator.ControlPlaneError, pattern):
                validator.validate_features(registry, tasks, self.approval_states)

    def test_security_review_must_cover_every_recorded_linked_task_report(self) -> None:
        registry = copy.deepcopy(self.registry)
        feature = registry["features"][1]
        feature["state"] = "SECURITY_REVIEWED"
        feature["evidence"] = ["review:security-review"]
        tasks = copy.deepcopy(self.task_map())
        task = tasks["TL-R0-001"]
        task["status"] = "VERIFIED"
        task["evidence"]["commits"] = ["44515a0"]
        task["evidence"]["test_reports"] = ["report-a", "report-b"]
        documents = {
            "report-a": self.valid_test_report(task),
            "report-b": self.valid_test_report(task),
            "security-review": self.valid_review(task, "security_privacy_reviewer", "report-a"),
        }
        documents["security-review"]["scope_id"] = feature["id"]
        with patch.object(validator, "load_typed_evidence", side_effect=lambda reference, _: documents[reference]), self.assertRaisesRegex(
            validator.ControlPlaneError, "every recorded linked task report"
        ):
            validator.validate_features(registry, tasks, self.approval_states)

    def test_device_states_require_matching_surface_and_current_commit(self) -> None:
        registry = copy.deepcopy(self.registry)
        control = next(item for item in registry["features"] if item["id"] == "TL-F-R0-CONTROL")
        control["state"] = "SPECIFIED"
        control["evidence"] = ["task:TL-R0-001"]
        feature = next(item for item in registry["features"] if item["id"] == "TL-F-R0-MOBILE")
        feature["state"] = "PHYSICAL_DEVICE_VERIFIED"
        feature["evidence"] = ["device:device", "approval:TL-D-013/TL-D-013-G-0001"]
        tasks = copy.deepcopy(self.task_map())
        for task_id in ("TL-R0-007", "TL-R0-008"):
            tasks[task_id]["status"] = "VERIFIED"
            tasks[task_id]["evidence"]["commits"] = ["44515a0"]
        approvals = dict(self.approval_states)
        approvals["TL-D-013"] = self.valid_approval("TL-D-013", feature, ["44515a0"])
        device = self.valid_device_report(feature["id"], surface="android_emulator")
        control_report = self.valid_test_report(
            tasks["TL-R0-001"], commit=tasks["TL-R0-001"]["evidence"]["commits"][0]
        )
        with patch.object(
            validator,
            "load_typed_evidence",
            side_effect=lambda _, evidence_type: control_report if evidence_type == "test_report" else device,
        ), self.assertRaisesRegex(validator.ControlPlaneError, "physical-surface"):
            validator.validate_features(registry, tasks, approvals)

    def test_dataset_report_requires_dataset_licence_decision(self) -> None:
        dataset = self.valid_dataset_report("TL-F-R2-MEAL-AI")
        dataset["license_decision_id"] = "TL-D-011"
        with self.assertRaisesRegex(validator.ControlPlaneError, "licence decision"):
            validator.validate_evidence_document(dataset, "dataset_report")

    def test_device_evidence_requires_terminal_feature_commits(self) -> None:
        tasks = copy.deepcopy(self.task_map())
        tasks["TL-R0-007"]["status"] = "VERIFIED"
        tasks["TL-R0-007"]["evidence"]["commits"] = ["fc57594"]
        tasks["TL-R0-008"]["status"] = "VERIFIED"
        tasks["TL-R0-008"]["evidence"]["commits"] = ["44515a0"]
        registry = copy.deepcopy(self.registry)
        control = next(item for item in registry["features"] if item["id"] == "TL-F-R0-CONTROL")
        control["state"] = "SPECIFIED"
        control["evidence"] = ["task:TL-R0-001"]
        feature = next(item for item in registry["features"] if item["id"] == "TL-F-R0-MOBILE")
        feature["state"] = "PHYSICAL_DEVICE_VERIFIED"
        feature["evidence"] = ["device:device", "approval:TL-D-013/TL-D-013-G-0001"]
        approvals = dict(self.approval_states)
        approvals["TL-D-013"] = self.valid_approval("TL-D-013", feature, ["44515a0"])
        device = self.valid_device_report(feature["id"], commit="fc57594")
        control_report = self.valid_test_report(
            tasks["TL-R0-001"], commit=tasks["TL-R0-001"]["evidence"]["commits"][0]
        )
        with patch.object(
            validator,
            "load_typed_evidence",
            side_effect=lambda _, evidence_type: control_report if evidence_type == "test_report" else device,
        ), self.assertRaisesRegex(
            validator.ControlPlaneError, "non-current commit"
        ):
            validator.validate_features(registry, tasks, approvals)

    def test_dataset_schema_requires_finite_matched_numeric_thresholds_that_pass(self) -> None:
        feature_id = "TL-F-R2-MEAL-AI"
        mutations = []
        nonnumeric = self.valid_dataset_report(feature_id)
        nonnumeric["metrics"]["accuracy"] = "0.9"
        mutations.append(nonnumeric)
        boolean = self.valid_dataset_report(feature_id)
        boolean["metrics"]["accuracy"] = True
        mutations.append(boolean)
        infinite = self.valid_dataset_report(feature_id)
        infinite["thresholds"]["accuracy"]["value"] = float("inf")
        mutations.append(infinite)
        mismatched = self.valid_dataset_report(feature_id)
        mismatched["thresholds"] = {"precision": {"operator": "gte", "value": 0.8}}
        mutations.append(mismatched)
        failed = self.valid_dataset_report(feature_id)
        failed["metrics"]["accuracy"] = 0.7
        mutations.append(failed)
        for document in mutations:
            with self.subTest(document=document), self.assertRaises(validator.ControlPlaneError):
                validator.validate_evidence_document(document, "dataset_report")

    def test_device_and_dataset_metadata_schemas_are_exact(self) -> None:
        feature_id = "TL-F-R2-MEAL-AI"
        device = self.valid_device_report(feature_id)
        validator.validate_evidence_document(device, "device_report")
        dataset = self.valid_dataset_report(feature_id)
        validator.validate_evidence_document(dataset, "dataset_report")
        device_mutations = []
        for field, value in (
            ("device_class", "fixture"),
            ("os_version", "14 unsafe"),
            ("app_artifact_hash", "0" * 64),
            ("tests", ["unsafe path/test"]),
            ("recorded_at", "2026-08-11"),
        ):
            mutation = copy.deepcopy(device)
            mutation[field] = value
            device_mutations.append(mutation)
        dataset_mutations = []
        for field, value in (
            ("dataset_id", "unsafe path"),
            ("dataset_version", True),
            ("recorded_at", "2026-08-11"),
        ):
            mutation = copy.deepcopy(dataset)
            mutation[field] = value
            dataset_mutations.append(mutation)
        for evidence_type, mutations in (("device_report", device_mutations), ("dataset_report", dataset_mutations)):
            for document in mutations:
                with self.subTest(evidence_type=evidence_type, document=document), self.assertRaises(validator.ControlPlaneError):
                    validator.validate_evidence_document(document, evidence_type)

    def test_feature_approval_requires_matching_feature_release_artifact_and_expiry(self) -> None:
        feature = copy.deepcopy(self.registry["features"][1])
        current = {"44515a0"}
        for field, value, pattern in (
            ("feature_id", "TL-F-R6-OTHER", "another feature"),
            ("release", "R6", "release does not match"),
            ("artifact_commits", [validator.git_resolve_commit("fc57594")], "do not exactly match"),
        ):
            metadata = self.valid_approval("TL-D-013", feature, ["44515a0"])
            metadata["ledger"]["events"][0][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(validator.ControlPlaneError, pattern):
                validator.validate_approval_for_feature(metadata, feature, current, "TL-D-013", "TL-D-013-G-0001")
        metadata = self.valid_approval("TL-D-013", feature, ["44515a0"])
        metadata["ledger"]["events"][0]["expires_or_review_on"] = "2026-08-11"
        with self.assertRaisesRegex(validator.ControlPlaneError, "expired"):
            validator.validate_approval_for_feature(metadata, feature, current, "TL-D-013", "TL-D-013-G-0001")

    def test_physical_and_dataset_states_need_specific_evidence(self) -> None:
        tasks = copy.deepcopy(self.task_map())
        tasks["TL-R0-001"]["status"] = "VERIFIED"
        for state, pattern in (("PHYSICAL_DEVICE_VERIFIED", "device evidence"), ("DATASET_EVALUATED", "dataset evidence")):
            registry = copy.deepcopy(self.registry)
            registry["features"][1]["state"] = state
            with self.subTest(state=state), self.assertRaisesRegex(validator.ControlPlaneError, pattern):
                validator.validate_features(registry, tasks, self.approval_states)

    def test_integrated_feature_requires_verified_linked_tasks(self) -> None:
        registry = copy.deepcopy(self.registry)
        registry["features"][1]["state"] = "INTEGRATED"
        registry["features"][1]["evidence"] = ["task:TL-R0-001"]
        tasks = copy.deepcopy(self.task_map())
        tasks["TL-R0-001"]["status"] = "READY"
        tasks["TL-R0-001"]["blockers"] = []
        with self.assertRaisesRegex(validator.ControlPlaneError, "requires verified linked tasks"):
            validator.validate_features(registry, tasks, self.approval_states)

    def test_code_complete_feature_rejects_missing_commit(self) -> None:
        registry = copy.deepcopy(self.registry)
        registry["features"][0]["evidence"] = ["commit:ffffffffffffffffffffffffffffffffffffffff"]
        with self.assertRaisesRegex(validator.ControlPlaneError, "missing commit"):
            validator.validate_features(registry, self.task_map(), self.approval_states)

    def test_not_started_feature_cannot_claim_evidence(self) -> None:
        registry = copy.deepcopy(self.registry)
        registry["features"][2]["evidence"] = ["commit:44515a0"]
        with self.assertRaisesRegex(validator.ControlPlaneError, "cannot claim implementation evidence"):
            validator.validate_features(registry, self.task_map(), self.approval_states)

    def test_expected_red_harness_cannot_disappear(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][1]["required_tests"] = [
            command for command in graph["tasks"][1]["required_tests"] if "assert_expected_red.ps1" not in command
        ]
        with self.assertRaisesRegex(validator.ControlPlaneError, "expected-red harness"):
            validator.validate_tasks(graph, self.texts)

    def test_quality_harness_retains_early_dependencies(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][8]["dependencies"].remove("TL-R0-002")
        with self.assertRaisesRegex(validator.ControlPlaneError, "early contract/platform gates"):
            validator.validate_tasks(graph, self.texts)

    def test_flutter_install_follows_resource_phase_activation(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][6]["dependencies"].remove("TL-R0-003")
        with self.assertRaisesRegex(validator.ControlPlaneError, "resource-phase activation"):
            validator.validate_tasks(graph, self.texts)

    def test_install_tasks_retain_pre_and_post_resource_gates(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][2]["required_tests"].pop()
        with self.assertRaisesRegex(validator.ControlPlaneError, "before and after"):
            validator.validate_tasks(graph, self.texts)

    def test_flutter_cli_requires_package_root_wrapper(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][6]["required_tests"][1] = "flutter build web apps/mobile"
        with self.assertRaisesRegex(validator.ControlPlaneError, "package-root wrappers"):
            validator.validate_tasks(graph, self.texts)

    def test_integration_owned_paths_require_integration_review(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][1]["required_reviewers"].remove("integration_release_lead")
        with self.assertRaisesRegex(validator.ControlPlaneError, "without integration review"):
            validator.validate_tasks(graph, self.texts)

    def test_same_origin_contract_cannot_disappear(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][1]["acceptance_criteria"] = [
            criterion for criterion in graph["tasks"][1]["acceptance_criteria"] if "same-origin" not in criterion
        ]
        with self.assertRaisesRegex(validator.ControlPlaneError, "same-origin web contract"):
            validator.validate_tasks(graph, self.texts)

    def test_android_loopback_transport_cannot_disappear(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][1]["acceptance_criteria"] = [
            criterion for criterion in graph["tasks"][1]["acceptance_criteria"] if "adb reverse" not in criterion
        ]
        with self.assertRaisesRegex(validator.ControlPlaneError, "Android debug transport"):
            validator.validate_tasks(graph, self.texts)

    def test_api_static_mount_uses_fixture_without_flutter_dependency(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][4]["acceptance_criteria"] = [
            criterion for criterion in graph["tasks"][4]["acceptance_criteria"] if "deterministic fixture" not in criterion
        ]
        with self.assertRaisesRegex(validator.ControlPlaneError, "fixture-test"):
            validator.validate_tasks(graph, self.texts)

    def test_decision_and_approval_ledgers_must_match(self) -> None:
        texts = dict(self.texts)
        texts["docs/program/HUMAN_APPROVALS.md"] = "\n".join(
            line for line in texts["docs/program/HUMAN_APPROVALS.md"].splitlines() if "| TL-D-017 |" not in line
        )
        with self.assertRaisesRegex(validator.ControlPlaneError, "Human approval IDs drifted|not one-to-one"):
            validator.validate_decisions(texts)

    def test_role_label_or_missing_identity_cannot_approve(self) -> None:
        for approved_by, pattern in (("Product Owner", "actual named humans"), ("-", "lacks approver")):
            texts = dict(self.texts)
            decision_lines = texts["docs/program/DECISIONS_REQUIRED.md"].splitlines()
            texts["docs/program/DECISIONS_REQUIRED.md"] = "\n".join(
                line.replace("| PENDING |", "| APPROVED |") if line.startswith("| TL-D-001 |") else line
                for line in decision_lines
            )
            approval_lines = texts["docs/program/HUMAN_APPROVALS.md"].splitlines()
            replacement = f"| TL-D-001 | First pilot jurisdiction | Product/legal owner | {approved_by} | APPROVED | 2026-08-11 | docs/program/evidence/approvals/TL-D-001.json | SCOPED GRANTS ONLY; SEE LEDGER |"
            texts["docs/program/HUMAN_APPROVALS.md"] = "\n".join(
                replacement if line.startswith("| TL-D-001 |") else line for line in approval_lines
            )
            with self.subTest(approved_by=approved_by), self.assertRaisesRegex(validator.ControlPlaneError, pattern):
                validator.validate_decisions(texts)

    def test_approved_decision_propagates_typed_scope_and_expiry_metadata(self) -> None:
        texts = dict(self.texts)
        texts["docs/program/DECISIONS_REQUIRED.md"] = "\n".join(
            line.replace("| PENDING |", "| APPROVED |") if line.startswith("| TL-D-001 |") else line
            for line in texts["docs/program/DECISIONS_REQUIRED.md"].splitlines()
        )
        texts["docs/program/HUMAN_APPROVALS.md"] = "\n".join(
            "| TL-D-001 | First pilot jurisdiction | Product/legal owner | Jane Doe | APPROVED | 2026-08-11 | docs/program/evidence/approvals/TL-D-001.json | SCOPED GRANTS ONLY; SEE LEDGER |"
            if line.startswith("| TL-D-001 |")
            else line
            for line in texts["docs/program/HUMAN_APPROVALS.md"].splitlines()
        )
        feature = next(item for item in self.registry["features"] if item["id"] == "TL-F-R6-PILOT")
        ledger = validator.validate_evidence_document(
            self.valid_approval("TL-D-001", feature, ["44515a0"])["ledger"],
            "human_approval_ledger",
        )
        with patch.object(validator, "load_typed_evidence", return_value=ledger):
            approvals = validator.validate_decisions(texts)
        self.assertEqual(approvals["TL-D-001"]["state"], "APPROVED")
        self.assertEqual(approvals["TL-D-001"]["ledger"]["events"][0]["feature_id"], "TL-F-R6-PILOT")

    def test_resource_cap_cannot_drift(self) -> None:
        budget = copy.deepcopy(self.budget)
        budget["cap_gb"] = 19
        with self.assertRaisesRegex(validator.ControlPlaneError, "exactly integer 18 GB"):
            validator.validate_budget(budget)

    def test_resource_thresholds_and_keys_cannot_drift(self) -> None:
        mutations = []
        threshold = copy.deepcopy(self.budget)
        threshold["hard_stop_percent"] = 99
        mutations.append(threshold)
        top_level = copy.deepcopy(self.budget)
        top_level["unapproved"] = True
        mutations.append(top_level)
        rule = copy.deepcopy(self.budget)
        rule["rules"]["unapproved"] = True
        mutations.append(rule)
        missing_rule = copy.deepcopy(self.budget)
        del missing_rule["rules"]["local_builds_are_sequential"]
        mutations.append(missing_rule)
        changed_rule = copy.deepcopy(self.budget)
        changed_rule["rules"]["model_downloads_in_bootstrap"] = True
        mutations.append(changed_rule)
        purpose = copy.deepcopy(self.budget)
        purpose["additional_roots"][0]["purpose"] = "different"
        mutations.append(purpose)
        second_root = copy.deepcopy(self.budget)
        duplicate = copy.deepcopy(second_root["additional_roots"][0])
        duplicate["label"] = "second"
        second_root["additional_roots"].append(duplicate)
        mutations.append(second_root)
        float_cap = copy.deepcopy(self.budget)
        float_cap["cap_gb"] = 18.0
        mutations.append(float_cap)
        boolean_warning = copy.deepcopy(self.budget)
        boolean_warning["warning_percent"] = True
        mutations.append(boolean_warning)
        for mutation in mutations:
            with self.subTest(keys=sorted(mutation)), self.assertRaises(validator.ControlPlaneError):
                validator.validate_budget(mutation)

    def test_network_policy_semantics_are_exact(self) -> None:
        policy = validator.load_json_yaml("config/r0-network-policy.json")
        mutations = []
        for section, key, value in (
            ("api", "bind_host", "0.0.0.0"),
            ("api", "cors_enabled", True),
            ("api", "reject_cross_origin_options", False),
            ("android_debug", "transport", "direct_lan"),
            ("android_debug", "selected_device_required", False),
            ("android_debug", "remove_mapping_on_exit", False),
            ("android_debug", "cleartext_allowed", False),
            ("android_release", "cleartext_allowed", True),
            ("android_release", "reject_debug_base_url", False),
            ("android_release", "production_enabled", True),
        ):
            mutation = copy.deepcopy(policy)
            mutation[section][key] = value
            mutations.append(mutation)
        production = copy.deepcopy(policy)
        production["production_enabled"] = True
        mutations.append(production)
        port = copy.deepcopy(policy)
        port["android_debug"]["host_port"] = 8001
        mutations.append(port)
        extra = copy.deepcopy(policy)
        extra["api"]["allow_lan"] = True
        mutations.append(extra)
        missing = copy.deepcopy(policy)
        del missing["android_debug"]["remove_mapping_on_exit"]
        mutations.append(missing)
        float_port = copy.deepcopy(policy)
        float_port["api"]["port"] = 8000.0
        mutations.append(float_port)
        boolean_port = copy.deepcopy(policy)
        boolean_port["api"]["port"] = True
        mutations.append(boolean_port)
        integer_boolean = copy.deepcopy(policy)
        integer_boolean["production_enabled"] = 0
        mutations.append(integer_boolean)
        for mutation in mutations:
            with self.subTest(mutation=mutation), self.assertRaisesRegex(validator.ControlPlaneError, "network policy drifted"):
                validator.validate_network_policy(mutation)

    def test_head_resolution_and_staged_verification_transition_are_exact(self) -> None:
        real_head = validator.git_head_commit()
        self.assertIsNotNone(real_head)
        self.assertRegex(real_head or "", r"^[0-9a-f]{40}$")
        self.assertIsNone(validator.git_resolve_commit("HEAD"))

        canonical = "a" * 40
        task = self.lifecycle_task(canonical)
        prior = copy.deepcopy(task)
        prior["status"] = "INTEGRATED"
        allowed = {
            "docs/program/TASK_GRAPH.yaml",
            *task["evidence"]["test_reports"],
            *task["evidence"]["reviews"],
        }
        with patch.object(validator, "git_resolve_commit", side_effect=lambda value: canonical if value == canonical else None), patch.object(
            validator, "git_head_commit", return_value=canonical
        ), patch.object(validator, "task_at_commit", return_value=prior), patch.object(
            validator, "git_unmerged_paths", return_value=set()
        ), patch.object(validator, "git_worktree_changes", return_value=set()), patch.object(
            validator, "git_staged_changes", return_value=allowed
        ):
            validator.validate_task_verification_lifecycle(task, canonical)

        unrelated = {"docs/program/TASK_GRAPH.yaml", "docs/program/evidence/test-reports/TL-R0-999/unrelated.json"}
        with patch.object(validator, "git_resolve_commit", return_value=canonical), patch.object(
            validator, "git_head_commit", return_value=canonical
        ), patch.object(validator, "task_at_commit", return_value=prior), patch.object(
            validator, "git_unmerged_paths", return_value=set()
        ), patch.object(validator, "git_worktree_changes", return_value=set()), patch.object(
            validator, "git_staged_changes", return_value=unrelated
        ), self.assertRaisesRegex(validator.ControlPlaneError, "unrelated verification metadata"):
            validator.validate_task_verification_lifecycle(task, canonical)

    def test_retained_verification_supports_distinct_ancestor_checkpoints(self) -> None:
        head = "f" * 40
        lineages = [
            (self.lifecycle_task("1" * 40), "1" * 40, "2" * 40),
            (self.lifecycle_task("3" * 40), "3" * 40, "4" * 40),
        ]
        lineages[1][0]["id"] = "TL-R0-002"
        lineages[1][0]["evidence"]["test_reports"] = [
            "docs/program/evidence/test-reports/TL-R0-002/report.json"
        ]
        lineages[1][0]["evidence"]["reviews"] = [
            "docs/program/evidence/reviews/TL-R0-002/review.json"
        ]
        for task, canonical, checkpoint in lineages:
            prior = copy.deepcopy(task)
            prior["status"] = "INTEGRATED"

            def historical(reference: str, _: str) -> dict:
                return prior if reference == canonical else task

            def ancestry(ancestor: str, descendant: str) -> list[str]:
                if (ancestor, descendant) == (canonical, head):
                    return [checkpoint, head]
                if (ancestor, descendant) == (checkpoint, head):
                    return [head]
                return []

            with self.subTest(task=task["id"]), patch.object(
                validator, "git_resolve_commit", side_effect=lambda value: value if value in {canonical, checkpoint, head} else None
            ), patch.object(validator, "git_head_commit", return_value=head), patch.object(
                validator, "task_at_commit", side_effect=historical
            ), patch.object(validator, "git_unmerged_paths", return_value=set()), patch.object(
                validator, "git_worktree_changes", return_value=set()
            ), patch.object(validator, "git_is_ancestor", return_value=True), patch.object(
                validator, "git_ancestry_path", side_effect=ancestry
            ), patch.object(
                validator,
                "git_parent_commits",
                side_effect=lambda reference: [canonical] if reference == checkpoint else [checkpoint],
            ), patch.object(
                validator, "git_commit_paths_between", return_value=["docs/program/TASK_GRAPH.yaml"]
            ), patch.object(
                validator,
                "task_evidence_blob_ids_at_commit",
                side_effect=lambda historical_task, _: {
                    **{path: "a" * 40 for path in historical_task["evidence"]["test_reports"]},
                    **{path: "b" * 40 for path in historical_task["evidence"]["reviews"]},
                },
            ), patch.object(
                validator,
                "task_evidence_blob_ids_from_index",
                return_value={
                    **{path: "a" * 40 for path in task["evidence"]["test_reports"]},
                    **{path: "b" * 40 for path in task["evidence"]["reviews"]},
                },
            ):
                validator.validate_task_verification_lifecycle(task, canonical)

    def test_retained_verification_rejects_lineage_projection_and_history_drift(self) -> None:
        canonical, checkpoint, intermediate, head = (character * 40 for character in "abcd")
        task = self.lifecycle_task(canonical)
        prior = copy.deepcopy(task)
        prior["status"] = "INTEGRATED"
        historical_task = copy.deepcopy(task)
        blobs = {
            task["evidence"]["test_reports"][0]: "1" * 40,
            task["evidence"]["reviews"][0]: "2" * 40,
        }

        def run(current: dict, *, ancestor: bool = True, parent: str | None = None, checkpoint_paths: list[str] | None = None, index_blobs: dict[str, str] | None = None, drift_history: bool = False) -> None:
            mutated = copy.deepcopy(historical_task)
            mutated["owned_paths"].append("drifted/**")

            def historical(reference: str, _: str) -> dict:
                if reference == canonical:
                    return prior
                if reference == intermediate and drift_history:
                    return mutated
                return historical_task

            def ancestry_path(ancestor_commit: str, descendant_commit: str) -> list[str]:
                if ancestor_commit == canonical:
                    return [checkpoint, intermediate, head] if drift_history else [checkpoint, head]
                if ancestor_commit == checkpoint:
                    return [intermediate, head] if drift_history else [head]
                return []

            with ExitStack() as stack:
                stack.enter_context(patch.object(validator, "git_resolve_commit", side_effect=lambda value: value if validator.FULL_GIT_COMMIT.fullmatch(value) else None))
                stack.enter_context(patch.object(validator, "git_head_commit", return_value=head))
                stack.enter_context(patch.object(validator, "task_at_commit", side_effect=historical))
                stack.enter_context(patch.object(validator, "git_unmerged_paths", return_value=set()))
                stack.enter_context(patch.object(validator, "git_worktree_changes", return_value=set()))
                stack.enter_context(patch.object(validator, "git_is_ancestor", return_value=ancestor))
                stack.enter_context(patch.object(validator, "git_ancestry_path", side_effect=ancestry_path))
                stack.enter_context(patch.object(validator, "git_parent_commits", side_effect=lambda reference: [parent or canonical] if reference == checkpoint else [checkpoint]))
                stack.enter_context(patch.object(validator, "git_commit_paths_between", return_value=checkpoint_paths or ["docs/program/TASK_GRAPH.yaml"]))
                stack.enter_context(patch.object(validator, "task_evidence_blob_ids_at_commit", return_value=blobs))
                stack.enter_context(patch.object(validator, "task_evidence_blob_ids_from_index", return_value=index_blobs or blobs))
                validator.validate_task_verification_lifecycle(current, current["evidence"]["commits"][0])

        run(copy.deepcopy(task))
        mutations: list[tuple[str, dict, dict]] = []
        scope = copy.deepcopy(task)
        scope["owned_paths"].append("scope-drift/**")
        mutations.append(("scope", scope, {}))
        substitution = copy.deepcopy(task)
        substitution["evidence"]["commits"] = ["e" * 40]
        mutations.append(("canonical", substitution, {}))
        mutations.append(("blob", copy.deepcopy(task), {"index_blobs": {**blobs, task["evidence"]["reviews"][0]: "9" * 40}}))
        mutations.append(("nonancestor", copy.deepcopy(task), {"ancestor": False}))
        mutations.append(("parent", copy.deepcopy(task), {"parent": "9" * 40}))
        mutations.append(("checkpoint", copy.deepcopy(task), {"checkpoint_paths": ["docs/program/TASK_GRAPH.yaml", "src/drift.py"]}))
        mutations.append(("history", copy.deepcopy(task), {"drift_history": True}))
        for label, mutation, options in mutations:
            with self.subTest(label=label), self.assertRaises(validator.ControlPlaneError):
                run(mutation, **options)

    def test_explicit_reopen_is_metadata_only_and_preserves_verified_projection(self) -> None:
        head = "a" * 40
        verified = self.lifecycle_task("1" * 40)
        reopened = copy.deepcopy(verified)
        reopened["status"] = "CHANGES_REQUIRED"
        reopened["blockers"] = ["Protected implementation or scope requires rework"]
        blobs = {
            reopened["evidence"]["test_reports"][0]: "2" * 40,
            reopened["evidence"]["reviews"][0]: "3" * 40,
        }
        with patch.object(validator, "git_unmerged_paths", return_value=set()), patch.object(
            validator, "git_worktree_changes", return_value=set()
        ), patch.object(validator, "git_staged_changes", return_value={"docs/program/TASK_GRAPH.yaml"}), patch.object(
            validator, "task_evidence_blob_ids_from_index", return_value=blobs
        ), patch.object(validator, "task_evidence_blob_ids_at_commit", return_value=blobs):
            validator.validate_task_reopen_lifecycle(reopened, head, verified)

        direct_downgrade = copy.deepcopy(reopened)
        direct_downgrade["status"] = "READY"
        with self.assertRaisesRegex(validator.ControlPlaneError, "explicitly reopened"):
            validator.validate_task_reopen_lifecycle(direct_downgrade, head, verified)

        scope_drift = copy.deepcopy(reopened)
        scope_drift["owned_paths"].append("drift/**")
        with patch.object(validator, "git_unmerged_paths", return_value=set()), patch.object(
            validator, "git_worktree_changes", return_value=set()
        ), patch.object(validator, "git_staged_changes", return_value={"docs/program/TASK_GRAPH.yaml"}), patch.object(
            validator, "task_evidence_blob_ids_from_index", return_value=blobs
        ), patch.object(validator, "task_evidence_blob_ids_at_commit", return_value=blobs), self.assertRaisesRegex(
            validator.ControlPlaneError, "protected scope or evidence|canonical, scope"
        ):
            validator.validate_task_reopen_lifecycle(scope_drift, head, verified)

    def test_committed_reopen_checkpoint_rejects_material_changes(self) -> None:
        canonical, checkpoint, verified_parent, reopen = (character * 40 for character in "abcd")
        verified = self.lifecycle_task(canonical)
        reopened = copy.deepcopy(verified)
        reopened["status"] = "CHANGES_REQUIRED"
        reopened["blockers"] = ["Rework required"]
        blobs = {
            verified["evidence"]["test_reports"][0]: "1" * 40,
            verified["evidence"]["reviews"][0]: "2" * 40,
        }

        def historical(reference: str, _: str) -> dict:
            return reopened if reference == reopen else verified

        def run(paths: list[str]) -> None:
            with patch.object(
                validator, "git_parent_commits", side_effect=lambda reference: [verified_parent] if reference == reopen else [canonical]
            ), patch.object(validator, "task_at_commit", side_effect=historical), patch.object(
                validator, "git_commit_paths_between", return_value=paths
            ), patch.object(validator, "task_evidence_blob_ids_at_commit", return_value=blobs), patch.object(
                validator, "git_resolve_commit", side_effect=lambda value: value
            ), patch.object(validator, "git_is_ancestor", return_value=True), patch.object(
                validator, "find_verification_checkpoint", return_value=(checkpoint, verified)
            ), patch.object(validator, "validate_retained_projection_history"):
                validator.validate_committed_reopen(verified["id"], verified_parent, reopen)

        run(["docs/program/TASK_GRAPH.yaml"])
        with self.assertRaisesRegex(validator.ControlPlaneError, "metadata only"):
            run(["docs/program/TASK_GRAPH.yaml", "scripts/material.py"])

    def test_task_evidence_lists_and_duplicate_resource_reports_are_unique(self) -> None:
        for key in validator.EVIDENCE_KEYS:
            graph = copy.deepcopy(self.graph)
            value = graph["tasks"][0]["evidence"][key][0] if graph["tasks"][0]["evidence"][key] else f"duplicate-{key}"
            graph["tasks"][0]["evidence"][key] = [value, value]
            with self.subTest(key=key), self.assertRaisesRegex(validator.ControlPlaneError, "unique entries"):
                validator.validate_tasks(graph, self.texts)

        graph = copy.deepcopy(self.graph)
        platform = next(task for task in graph["tasks"] if task["id"] == "TL-R0-003")
        self.assertGreaterEqual(sum("check_resource_budget.ps1" in command for command in platform["required_tests"]), 2)
        report = "docs/program/evidence/test-reports/TL-R0-003/resource.json"
        platform["evidence"]["test_reports"] = [report, report]
        with self.assertRaisesRegex(validator.ControlPlaneError, "unique entries"):
            validator.validate_tasks(graph, self.texts)

    def test_evidence_inventory_is_complete_and_exact(self) -> None:
        report = "docs/program/evidence/test-reports/TL-R0-001/report.json"
        entry = ("100644", "a" * 40, 0, report)
        with patch.object(validator, "collect_referenced_evidence", return_value={report: "test_report"}), patch.object(
            validator, "git_index_entries_under", return_value=[entry]
        ), patch.object(validator, "load_typed_evidence", return_value={}):
            validator.validate_evidence_inventory(self.graph, self.registry, self.approval_states)

        with patch.object(validator, "collect_referenced_evidence", return_value={}), patch.object(
            validator, "git_index_entries_under", return_value=[entry]
        ), self.assertRaisesRegex(validator.ControlPlaneError, "unreferenced"):
            validator.validate_evidence_inventory(self.graph, self.registry, self.approval_states)

        with patch.object(validator, "collect_referenced_evidence", return_value={report: "test_report"}), patch.object(
            validator, "git_index_entries_under", return_value=[]
        ), self.assertRaisesRegex(validator.ControlPlaneError, "not staged/tracked"):
            validator.validate_evidence_inventory(self.graph, self.registry, self.approval_states)

    def test_screenshot_parser_rejects_incomplete_metadata_trailing_and_crc_mutations(self) -> None:
        valid = self.valid_png()

        def validate_png(data: bytes) -> None:
            with patch.object(validator, "validate_indexed_evidence", return_value=(Path("fixture.png"), "a" * 40)), patch.object(
                validator, "git_blob_size", return_value=len(data)
            ), patch.object(validator, "read_git_blob", return_value=data):
                validator.validate_screenshot_evidence("docs/program/evidence/screenshots/TL-R0-001/fixture.png")

        validate_png(valid)
        compressed = zlib.compress(b"\x00\x00\x00\x00\x00")
        validate_png(self.valid_png(idat_payloads=[compressed[:3], compressed[3:]]))
        bad_crc = bytearray(valid)
        bad_crc[29] ^= 1
        token_palette = b"sk-svcacct-abcdefgh12345678"
        token_palette += b"X" * ((3 - len(token_palette) % 3) % 3)
        mutations = {
            "header-only": valid[:33],
            "trailing": valid + b"trailing",
            "text": self.valid_png([self.png_chunk(b"tEXt", b"key\x00value")]),
            "exif": self.valid_png([self.png_chunk(b"eXIf", b"metadata")]),
            "unknown": self.valid_png([self.png_chunk(b"vpAg", b"unknown")]),
            "bad-crc": bytes(bad_crc),
            "truncated": valid[:-3],
            "post-idat-metadata": valid[:-12] + self.png_chunk(b"pHYs", b"\x00" * 9) + valid[-12:],
            "interlaced": self.valid_png(interlace=1),
            "invalid-zlib": self.valid_png(idat_payloads=[b"not-zlib"]),
            "short-scanline": self.valid_png(raw_scanlines=b"\x00\x00\x00\x00"),
            "long-scanline": self.valid_png(raw_scanlines=b"\x00\x00\x00\x00\x00\x00"),
            "invalid-filter": self.valid_png(raw_scanlines=b"\x05\x00\x00\x00\x00"),
            "zlib-unused-data": self.valid_png(idat_payloads=[compressed + b"unused"]),
            "concatenated-zlib-stream": self.valid_png(idat_payloads=[compressed + compressed]),
            "invalid-srgb-length": self.valid_png([self.png_chunk(b"sRGB", b"\x00\x00")]),
            "invalid-phys-unit": self.valid_png([self.png_chunk(b"pHYs", b"\x00" * 8 + b"\x02")]),
            "token-bearing-palette": self.valid_png([self.png_chunk(b"PLTE", token_palette)]),
        }
        for label, data in mutations.items():
            with self.subTest(label=label), self.assertRaises(validator.ControlPlaneError):
                validate_png(data)

    def test_recursive_sanitizer_rejects_secret_and_private_path_families(self) -> None:
        sensitive_values = [
            "sk-proj-abcdefgh12345678",
            "sk-svcacct-abcdefgh12345678",
            "ghp_abcdefghijklmnopqrstuvwxyz1234",
            "github_pat_abcdefghijklmnopqrstuvwxyz123456",
            "AKIAABCDEFGHIJKLMNOP",
            "xoxb-1234567890-secretvalue",
            "sk_live_abcdefgh12345678",
            "Bearer abcdefghijklmnopqrstuvwxyz",
            "eyJabcde.eyJfghij.signature123",
            "postgresql://user:pass@db.invalid/data",
            "https://public:secret@o1.ingest.sentry.io/2",
            "/root/private/evidence.json",
            "/workspace/build/output.json",
            "/private/var/mobile/data.json",
            "/github/workspace/build/output.json",
            "/mnt/c/Users/person/private.json",
        ]
        for sensitive in sensitive_values:
            with self.subTest(value=sensitive):
                with self.assertRaises(validator.ControlPlaneError) as raised:
                    validator.validate_sanitized_evidence({"outer": [{"detail": sensitive}]})
                self.assertNotIn(sensitive, str(raised.exception))

    def test_typed_json_and_valid_png_payloads_reject_system_posix_roots(self) -> None:
        roots = [
            "/var/lib/postgresql/data",
            "/etc/service/config.json",
            "/opt/toolchain/bin/tool",
            "/srv/application/state",
            "/usr/local/bin/runtime",
            "/run/secrets/provider",
            "/data/private/export.json",
            "/app/config/settings.json",
        ]
        task = self.graph["tasks"][0]
        for private_path in roots:
            report = self.valid_test_report(task)
            report["summary"] = f"Synthetic private path {private_path}"
            with self.subTest(private_path=private_path), self.assertRaisesRegex(
                validator.ControlPlaneError, "absolute private path"
            ):
                validator.validate_evidence_document(report, "test_report")
        relative_route = self.valid_test_report(task)
        relative_route["summary"] = "Synthetic relative service route /api/v1/status"
        validator.validate_evidence_document(relative_route, "test_report")

        def validate_png(data: bytes) -> None:
            with patch.object(validator, "validate_indexed_evidence", return_value=(Path("fixture.png"), "a" * 40)), patch.object(
                validator, "git_blob_size", return_value=len(data)
            ), patch.object(validator, "read_git_blob", return_value=data):
                validator.validate_screenshot_evidence("docs/program/evidence/screenshots/TL-R0-001/fixture.png")

        palette_path = b"/opt/private/model"
        palette_path += b"X" * ((3 - len(palette_path) % 3) % 3)
        with self.assertRaisesRegex(validator.ControlPlaneError, "absolute private path"):
            validate_png(self.valid_png([self.png_chunk(b"PLTE", palette_path)]))

        decoded_path = b"/etc/private"
        decoded_png = self.valid_png(
            width=len(decoded_path),
            color_type=0,
            raw_scanlines=b"\x00" + decoded_path,
        )
        with self.assertRaisesRegex(validator.ControlPlaneError, "absolute private path"):
            validate_png(decoded_png)

    def test_human_approval_ledger_supports_multiple_scoped_grants_and_people(self) -> None:
        decision = "TL-D-003"
        first_feature = {"id": "TL-F-R1-MEALS", "release": "R1"}
        second_feature = {"id": "TL-F-R2-MEAL-AI", "release": "R2"}
        metadata = self.valid_approval(decision, first_feature, ["44515a0"])
        first_grant = metadata["ledger"]["events"][0]
        second_grant = copy.deepcopy(first_grant)
        second_grant.update(
            {
                "event_id": f"{decision}-G-0002",
                "approved_by": ["John Smith"],
                "feature_id": second_feature["id"],
                "release": second_feature["release"],
                "scope": "Synthetic second feature scope",
            }
        )
        ledger = copy.deepcopy(metadata["ledger"])
        ledger["events"].append(second_grant)
        validator.validate_evidence_document(ledger, "human_approval_ledger")
        self.assertEqual(validator.approval_ledger_actors(ledger), ["Jane Doe", "John Smith"])
        metadata = {
            "state": "APPROVED",
            "ledger_path": f"docs/program/evidence/approvals/{decision}.json",
            "ledger": ledger,
            "active_grants": validator.active_approval_grants(ledger),
        }
        validator.validate_approval_for_feature(metadata, first_feature, {"44515a0"}, decision, first_grant["event_id"])
        validator.validate_approval_for_feature(metadata, second_feature, {"44515a0"}, decision, second_grant["event_id"])
        with self.assertRaisesRegex(validator.ControlPlaneError, "another feature"):
            validator.validate_approval_for_feature(metadata, second_feature, {"44515a0"}, decision, first_grant["event_id"])

    def test_human_approval_events_are_append_only_revocable_and_date_bounded(self) -> None:
        decision = "TL-D-003"
        feature = {"id": "TL-F-R1-MEALS", "release": "R1"}
        previous = self.valid_approval(decision, feature, ["44515a0"])["ledger"]
        current = copy.deepcopy(previous)
        second = copy.deepcopy(current["events"][0])
        second["event_id"] = f"{decision}-G-0002"
        second["approved_by"] = ["John Smith"]
        second["scope"] = "Second immutable scoped grant"
        current["events"].append(second)
        validator.validate_evidence_document(current, "human_approval_ledger")
        validator.validate_approval_ledger_extension(previous, current)
        mutations = []
        identity = copy.deepcopy(current)
        identity["decision_id"] = "TL-D-004"
        mutations.append(identity)
        edited = copy.deepcopy(current)
        edited["events"][0]["scope"] = "edited"
        mutations.append(edited)
        mutations.append({**copy.deepcopy(current), "events": []})
        reordered = copy.deepcopy(current)
        reordered["events"].reverse()
        mutations.append(reordered)
        for mutation in mutations:
            with self.subTest(mutation=mutation), self.assertRaises(validator.ControlPlaneError):
                validator.validate_approval_ledger_extension(previous, mutation)

        revoked = copy.deepcopy(previous)
        revoked["events"].append(
            {
                "event_id": f"{decision}-R-0002",
                "event": "REVOKE",
                "revoked_by": ["Mary Roe"],
                "approval_date": "2026-08-12",
                "revokes_event_id": f"{decision}-G-0001",
                "reason": "Approval scope withdrawn",
            }
        )
        validator.validate_evidence_document(revoked, "human_approval_ledger")
        self.assertEqual(validator.active_approval_grants(revoked), {})
        inactive = {"state": "INACTIVE", "ledger": revoked, "active_grants": {}}
        with self.assertRaisesRegex(validator.ControlPlaneError, "unapproved decision"):
            validator.validate_approval_for_feature(inactive, feature, {"44515a0"}, decision, f"{decision}-G-0001")

        for approval_date in ("2026-02-30", "2999-01-01"):
            invalid = copy.deepcopy(previous)
            invalid["events"][0]["approval_date"] = approval_date
            with self.subTest(approval_date=approval_date), self.assertRaises(validator.ControlPlaneError):
                validator.validate_evidence_document(invalid, "human_approval_ledger")

        duplicate_people = copy.deepcopy(previous)
        duplicate_people["events"][0]["approved_by"] = ["Jane Doe", "jane doe"]
        with self.assertRaisesRegex(validator.ControlPlaneError, "bounded unique list"):
            validator.validate_evidence_document(duplicate_people, "human_approval_ledger")
        nonmonotonic = copy.deepcopy(current)
        nonmonotonic["events"][1]["approval_date"] = "2026-08-10"
        with self.assertRaisesRegex(validator.ControlPlaneError, "monotonic"):
            validator.validate_evidence_document(nonmonotonic, "human_approval_ledger")
        obsolete_ledger_actor = copy.deepcopy(previous)
        obsolete_ledger_actor["approved_by"] = ["Jane Doe"]
        with self.assertRaisesRegex(validator.ControlPlaneError, "fields drifted"):
            validator.validate_evidence_document(obsolete_ledger_actor, "human_approval_ledger")
        missing_revoker = copy.deepcopy(revoked)
        del missing_revoker["events"][1]["revoked_by"]
        with self.assertRaisesRegex(validator.ControlPlaneError, "REVOKE fields"):
            validator.validate_evidence_document(missing_revoker, "human_approval_ledger")
        duplicate_revoker = copy.deepcopy(revoked)
        duplicate_revoker["events"][1]["revoked_by"] = ["Mary Roe", "mary roe"]
        with self.assertRaisesRegex(validator.ControlPlaneError, "bounded unique list"):
            validator.validate_evidence_document(duplicate_revoker, "human_approval_ledger")
        duplicate_commits = copy.deepcopy(previous)
        duplicate_commits["events"][0]["artifact_commits"] *= 2
        with self.assertRaisesRegex(validator.ControlPlaneError, "unique full existing commits"):
            validator.validate_evidence_document(duplicate_commits, "human_approval_ledger")
        short_commit = copy.deepcopy(previous)
        short_commit["events"][0]["artifact_commits"] = ["44515a0"]
        with self.assertRaisesRegex(validator.ControlPlaneError, "unique full existing commits"):
            validator.validate_evidence_document(short_commit, "human_approval_ledger")

    def test_decision_ledger_preserves_deleted_history_and_allows_truthful_inactive_state(self) -> None:
        hidden_path = "docs/program/evidence/approvals/TL-D-001.json"
        with patch.object(validator, "git_historical_paths_under", return_value={hidden_path}), patch.object(
            validator, "git_index_entries_under", return_value=[]
        ), self.assertRaisesRegex(validator.ControlPlaneError, "cannot delete or hide"):
            validator.validate_decisions(self.texts)

        feature = {"id": "TL-F-R6-PILOT", "release": "R6"}
        ledger = self.valid_approval("TL-D-001", feature, ["44515a0"])["ledger"]
        ledger["events"].append(
            {
                "event_id": "TL-D-001-R-0002",
                "event": "REVOKE",
                "revoked_by": ["Mary Roe"],
                "approval_date": "2026-08-12",
                "revokes_event_id": "TL-D-001-G-0001",
                "reason": "Synthetic approval revoked",
            }
        )
        texts = dict(self.texts)
        texts["docs/program/DECISIONS_REQUIRED.md"] = "\n".join(
            line.replace("| PENDING |", "| INACTIVE |") if line.startswith("| TL-D-001 |") else line
            for line in texts["docs/program/DECISIONS_REQUIRED.md"].splitlines()
        )
        texts["docs/program/HUMAN_APPROVALS.md"] = "\n".join(
            "| TL-D-001 | First pilot jurisdiction | Product/legal owner | Jane Doe; Mary Roe | INACTIVE | 2026-08-11 | docs/program/evidence/approvals/TL-D-001.json | SCOPED GRANTS ONLY; SEE LEDGER |"
            if line.startswith("| TL-D-001 |")
            else line
            for line in texts["docs/program/HUMAN_APPROVALS.md"].splitlines()
        )
        with patch.object(validator, "git_historical_paths_under", return_value=set()), patch.object(
            validator, "git_index_entries_under", return_value=[]
        ), patch.object(validator, "load_typed_evidence", return_value=ledger), patch.object(
            validator, "validate_approval_ledger_history"
        ):
            approvals = validator.validate_decisions(texts)
        self.assertEqual(approvals["TL-D-001"]["state"], "INACTIVE")
        self.assertEqual(approvals["TL-D-001"]["active_grants"], {})
        actor_mismatch = dict(texts)
        actor_mismatch["docs/program/HUMAN_APPROVALS.md"] = actor_mismatch[
            "docs/program/HUMAN_APPROVALS.md"
        ].replace("Jane Doe; Mary Roe | INACTIVE", "Jane Doe | INACTIVE")
        with patch.object(validator, "git_historical_paths_under", return_value=set()), patch.object(
            validator, "git_index_entries_under", return_value=[]
        ), patch.object(validator, "load_typed_evidence", return_value=ledger), patch.object(
            validator, "validate_approval_ledger_history"
        ), self.assertRaisesRegex(validator.ControlPlaneError, "actor union"):
            validator.validate_decisions(actor_mismatch)

    def test_json_and_evidence_numerics_are_finite_bounded_and_overflow_safe(self) -> None:
        self.assertFalse(validator.is_finite_number(10**10000))
        for raw in ('{"value":' + "9" * 5000 + "}", '{"value":1e309}'):
            with self.subTest(raw_length=len(raw)), self.assertRaises(validator.ControlPlaneError):
                validator.parse_json_object(raw, "synthetic numeric fixture")
        oversized_integer = ('{"value":' + "9" * 5000 + "}").encode("ascii")
        with patch.object(validator, "git_blob_size", return_value=len(oversized_integer)), patch.object(
            validator, "read_git_blob", return_value=oversized_integer
        ), self.assertRaises(validator.ControlPlaneError):
            validator.load_json_blob("a" * 40, "synthetic evidence")

        task = self.graph["tasks"][0]
        mutations = []
        duration = self.valid_test_report(task)
        duration["duration_seconds"] = validator.MAX_DURATION_SECONDS + 1
        mutations.append((duration, "test_report"))
        result_count = self.valid_test_report(task)
        result_count["commands"][0]["result_count"] = validator.MAX_RESULT_COUNT + 1
        mutations.append((result_count, "test_report"))
        memory = self.valid_test_report(task)
        memory["resource_status"]["host_free_memory_gb"] = validator.MAX_HOST_MEMORY_GB + 1
        mutations.append((memory, "test_report"))
        metric = self.valid_dataset_report("TL-F-R2-MEAL-AI")
        metric["metrics"]["accuracy"] = 10**100
        mutations.append((metric, "dataset_report"))
        for document, evidence_type in mutations:
            with self.subTest(evidence_type=evidence_type), self.assertRaises(validator.ControlPlaneError):
                validator.validate_evidence_document(document, evidence_type)

    def test_typed_evidence_array_counts_are_bounded(self) -> None:
        task = self.graph["tasks"][0]
        report = self.valid_test_report(task)
        report["commands"] = [copy.deepcopy(report["commands"][0]) for _ in range(validator.MAX_REPORT_COMMANDS + 1)]

        review_findings = self.valid_review(task, "quality_engineer")
        review_findings["findings"] = [
            {"severity": "INFO", "status": "RESOLVED", "summary": f"Synthetic finding {index}"}
            for index in range(validator.MAX_REVIEW_FINDINGS + 1)
        ]
        review_tests = self.valid_review(task, "quality_engineer")
        review_tests["test_evidence"] = [
            f"docs/program/evidence/test-reports/TL-R0-001/report-{index}.json"
            for index in range(validator.MAX_REVIEW_TEST_EVIDENCE + 1)
        ]

        device = self.valid_device_report("TL-F-R0-MOBILE")
        device["tests"] = [f"test_{index}" for index in range(validator.MAX_DEVICE_TESTS + 1)]

        dataset = self.valid_dataset_report("TL-F-R2-MEAL-AI")
        dataset["metrics"] = {f"metric_{index}": 1 for index in range(validator.MAX_DATASET_METRICS + 1)}
        dataset["thresholds"] = {
            key: {"operator": "gte", "value": 1} for key in dataset["metrics"]
        }

        feature = {"id": "TL-F-R1-MEALS", "release": "R1"}
        approval_events = self.valid_approval("TL-D-003", feature, ["44515a0"])["ledger"]
        approval_events["events"] = [copy.deepcopy(approval_events["events"][0]) for _ in range(validator.MAX_APPROVAL_EVENTS + 1)]
        approval_actors = self.valid_approval("TL-D-003", feature, ["44515a0"])["ledger"]
        approval_actors["events"][0]["approved_by"] = [
            f"Person {index}" for index in range(validator.MAX_APPROVAL_EVENT_ACTORS + 1)
        ]
        approval_evidence = self.valid_approval("TL-D-003", feature, ["44515a0"])["ledger"]
        approval_evidence["events"][0]["evidence_reviewed"] = [
            f"docs/program/evidence/test-reports/TL-R0-001/report-{index}.json"
            for index in range(validator.MAX_APPROVAL_REVIEWED_EVIDENCE + 1)
        ]

        for evidence_type, document in (
            ("test_report", report),
            ("independent_review", review_findings),
            ("independent_review", review_tests),
            ("device_report", device),
            ("dataset_report", dataset),
            ("human_approval_ledger", approval_events),
            ("human_approval_ledger", approval_actors),
            ("human_approval_ledger", approval_evidence),
        ):
            with self.subTest(evidence_type=evidence_type), self.assertRaises(validator.ControlPlaneError):
                validator.validate_evidence_document(document, evidence_type)

        graph = copy.deepcopy(self.graph)
        graph["tasks"][0]["evidence"]["notes"] = [
            f"Synthetic bounded note {index}" for index in range(validator.MAX_TASK_EVIDENCE_ENTRIES + 1)
        ]
        with self.assertRaisesRegex(validator.ControlPlaneError, "bounded evidence-list"):
            validator.validate_tasks(graph, self.texts)

        actor_union = {
            "events": [
                {
                    "event": "GRANT",
                    "approved_by": [f"Person {event_index}-{actor_index}" for actor_index in range(validator.MAX_APPROVAL_EVENT_ACTORS)],
                }
                for event_index in range(5)
            ]
        }
        with self.assertRaisesRegex(validator.ControlPlaneError, "actor union"):
            validator.approval_ledger_actors(actor_union)

    def test_verified_resource_guard_cannot_remain_prebootstrap(self) -> None:
        tasks = copy.deepcopy(self.graph["tasks"])
        next(task for task in tasks if task["id"] == "TL-R0-003")["status"] = "VERIFIED"
        budget = copy.deepcopy(self.budget)
        budget["phase"] = "prebootstrap"
        with self.assertRaisesRegex(validator.ControlPlaneError, "cannot be VERIFIED"):
            validator.validate_resource_phase_for_tasks(tasks, budget)
        for phase in ("bootstrap_active", "implementation", "release"):
            budget["phase"] = phase
            validator.validate_resource_phase_for_tasks(tasks, budget)

    def test_contract_harness_handoff_and_strict_quality_worktree_are_frozen(self) -> None:
        tasks = self.task_map()
        contract_commands = tasks["TL-R0-002"]["required_tests"]
        self_test = "pwsh -NoProfile -File scripts/contracts/test_expected_red_harness.ps1"
        red_assertion = "pwsh -NoProfile -File scripts/contracts/assert_expected_red.ps1 -Manifest tests/contracts/expected-red.json"
        self.assertLess(contract_commands.index(self_test), contract_commands.index(red_assertion))
        self.assertIn("scripts/contracts/**", tasks["TL-R0-002"]["owned_paths"])
        for task_id in ("TL-R0-005", "TL-R0-008"):
            expected = (
                "pwsh -NoProfile -File scripts/contracts/assert_expected_green.ps1 "
                f"-Manifest tests/contracts/expected-red.json -Owner {task_id}"
            )
            self.assertIn(expected, tasks[task_id]["required_tests"])
            self.assertTrue(any("expected-red IDs" in criterion and "run green" in criterion for criterion in tasks[task_id]["acceptance_criteria"]))
        self.assertEqual(
            tasks["TL-R0-009"]["required_tests"][1],
            "pwsh -NoProfile -File scripts/quality/assert_clean_worktree.ps1",
        )

    def test_exact_r0_semantic_baselines_reject_deletion_gate_removal_and_weakening(self) -> None:
        for task_id in ("TL-R0-004", "TL-R0-006", "TL-R0-010"):
            graph = copy.deepcopy(self.graph)
            graph["tasks"] = [task for task in graph["tasks"] if task["id"] != task_id]
            with self.subTest(task_deleted=task_id), self.assertRaisesRegex(validator.ControlPlaneError, "task IDs drifted"):
                validator.validate_tasks(graph, self.texts)

        weakened_graph = copy.deepcopy(self.graph)
        weakened_task = next(task for task in weakened_graph["tasks"] if task["id"] == "TL-R0-004")
        weakened_task["acceptance_criteria"] = weakened_task["acceptance_criteria"][1:]
        with self.assertRaisesRegex(validator.ControlPlaneError, "immutable task specification"):
            validator.validate_tasks(weakened_graph, self.texts)

        for feature_id in ("TL-F-R0-MOBILE", "TL-F-R6-PILOT"):
            registry = copy.deepcopy(self.registry)
            registry["features"] = [feature for feature in registry["features"] if feature["id"] != feature_id]
            with self.subTest(feature_deleted=feature_id), self.assertRaisesRegex(validator.ControlPlaneError, "Feature IDs drifted"):
                validator.validate_features(registry, self.task_map(), self.approval_states)

        gate_registry = copy.deepcopy(self.registry)
        pilot = next(feature for feature in gate_registry["features"] if feature["id"] == "TL-F-R6-PILOT")
        pilot["human_gates"].remove("TL-D-017")
        with self.assertRaisesRegex(validator.ControlPlaneError, "human-gate"):
            validator.validate_features(gate_registry, self.task_map(), self.approval_states)

        name_registry = copy.deepcopy(self.registry)
        mobile = next(feature for feature in name_registry["features"] if feature["id"] == "TL-F-R0-MOBILE")
        mobile["name"] = "Generic mobile client"
        with self.assertRaisesRegex(validator.ControlPlaneError, "feature identity"):
            validator.validate_features(name_registry, self.task_map(), self.approval_states)

        for label, feature_id, task_ids in (
            ("removal", "TL-F-R0-MOBILE", ["TL-R0-007"]),
            ("substitution", "TL-F-R0-MOBILE", ["TL-R0-007", "TL-R0-006"]),
            ("later-empty-linkage", "TL-F-R1-IDENTITY", ["TL-R0-001"]),
        ):
            linkage_registry = copy.deepcopy(self.registry)
            linked_feature = next(feature for feature in linkage_registry["features"] if feature["id"] == feature_id)
            linked_feature["task_ids"] = task_ids
            with self.subTest(linkage=label), self.assertRaisesRegex(validator.ControlPlaneError, "task-link semantics drifted"):
                validator.validate_features(linkage_registry, self.task_map(), self.approval_states)

        coordinated = dict(self.texts)
        for relative in ("docs/program/DECISIONS_REQUIRED.md", "docs/program/HUMAN_APPROVALS.md"):
            coordinated[relative] = "\n".join(
                line for line in coordinated[relative].splitlines() if not line.startswith("| TL-D-017 |")
            )
        with self.assertRaisesRegex(validator.ControlPlaneError, "Decision IDs drifted"):
            validator.validate_decisions(coordinated)

        decision_weakening = dict(self.texts)
        decision_weakening["docs/program/DECISIONS_REQUIRED.md"] = decision_weakening[
            "docs/program/DECISIONS_REQUIRED.md"
        ].replace("Resolve automatic criticals; keep human acceptance pending", "Ignore automatic criticals")
        with self.assertRaisesRegex(validator.ControlPlaneError, "DECISIONS_REQUIRED semantics drifted"):
            validator.validate_decisions(decision_weakening)

        human_weakening = dict(self.texts)
        human_weakening["docs/program/HUMAN_APPROVALS.md"] = human_weakening[
            "docs/program/HUMAN_APPROVALS.md"
        ].replace("| TL-D-017 | Security risk acceptance | Authorised security owner |", "| TL-D-017 | Security risk acceptance | Any owner |")
        with self.assertRaisesRegex(validator.ControlPlaneError, "HUMAN_APPROVALS gate semantics drifted"):
            validator.validate_decisions(human_weakening)

    def test_task_and_feature_control_documents_reject_unknown_fields(self) -> None:
        graph = copy.deepcopy(self.graph)
        graph["tasks"][7]["skip_android_evidence"] = True
        with self.assertRaisesRegex(validator.ControlPlaneError, "task fields drifted"):
            validator.validate_tasks(graph, self.texts)

        registry = copy.deepcopy(self.registry)
        registry["features"][6]["human_gates_override"] = []
        with self.assertRaisesRegex(validator.ControlPlaneError, "Feature fields drifted"):
            validator.validate_features(registry, self.task_map(), self.approval_states)

        registry = copy.deepcopy(self.registry)
        registry["production_enabled"] = False
        with self.assertRaisesRegex(validator.ControlPlaneError, "top-level fields drifted"):
            validator.validate_features(registry, self.task_map(), self.approval_states)


if __name__ == "__main__":
    unittest.main()
