from __future__ import annotations

import json
import hashlib
import math
import re
import struct
import subprocess
import sys
import zlib
from datetime import date
from pathlib import Path
from typing import NoReturn


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_FILES = [
    "AGENTS.md",
    "docs/program/PRODUCT_CHARTER.md",
    "docs/program/SCOPE_AND_NON_GOALS.md",
    "docs/program/RELEASE_PLAN.md",
    "docs/program/PROJECT_STATE.md",
    "docs/program/TASK_GRAPH.yaml",
    "docs/program/FEATURE_REGISTRY.yaml",
    "docs/program/DECISIONS_REQUIRED.md",
    "docs/program/HUMAN_APPROVALS.md",
    "docs/program/TRACEABILITY_MATRIX.md",
    "docs/program/QUALITY_GATES.md",
    "docs/program/PERFORMANCE_BUDGETS.md",
    "docs/program/RISK_REGISTER.md",
    "docs/program/releases/R0_FOUNDATION_HEARTBEAT.md",
    "docs/architecture/DECISION_LOG.md",
    "docs/architecture/DATA_FLOW.md",
    "docs/ux/INFORMATION_ARCHITECTURE.md",
    "docs/ux/DESIGN_SYSTEM.md",
    "docs/security/THREAT_MODEL.md",
    "docs/privacy/DATA_INVENTORY.md",
    "config/resource-budget.json",
    "config/r0-network-policy.json",
]
TASK_KEYS = {
    "id",
    "release",
    "title",
    "objective",
    "status",
    "owner_agent",
    "dependencies",
    "owned_paths",
    "integration_owned_paths",
    "forbidden_paths",
    "inputs",
    "acceptance_criteria",
    "required_tests",
    "required_reviewers",
    "evidence",
    "blockers",
    "next_action",
}
EVIDENCE_KEYS = {"commits", "test_reports", "reviews", "screenshots", "notes"}
TASK_STATES = {
    "BACKLOG",
    "BLOCKED",
    "READY",
    "IN_PROGRESS",
    "IN_REVIEW",
    "CHANGES_REQUIRED",
    "INTEGRATED",
    "VERIFIED",
    "AWAITING_HUMAN_APPROVAL",
}
ACTIVE_TASK_STATES = TASK_STATES - {"BACKLOG", "BLOCKED"}
FEATURE_STATES = {
    "NOT_STARTED",
    "SPECIFIED",
    "CODE_COMPLETE",
    "AUTOMATED_TESTED",
    "INTEGRATED",
    "EMULATOR_VERIFIED",
    "PHYSICAL_DEVICE_VERIFIED",
    "DATASET_EVALUATED",
    "DOMAIN_REVIEWED",
    "LANGUAGE_REVIEWED",
    "SECURITY_REVIEWED",
    "PILOT_READY",
    "PRODUCTION_APPROVED",
}
HUMAN_ATTESTED_FEATURE_STATES = {
    "DOMAIN_REVIEWED",
    "LANGUAGE_REVIEWED",
    "PILOT_READY",
    "PRODUCTION_APPROVED",
}
FEATURE_EVIDENCE_TYPES = {"task", "commit", "report", "review", "device", "dataset", "approval"}
EVIDENCE_ROOTS = {
    "test_report": ("docs/program/evidence/test-reports/",),
    "independent_review": ("docs/program/evidence/reviews/",),
    "device_report": ("docs/program/evidence/devices/",),
    "dataset_report": ("docs/program/evidence/datasets/",),
    "human_approval_ledger": ("docs/program/evidence/approvals/",),
    "screenshot": ("docs/program/evidence/screenshots/",),
}
EVIDENCE_PREFIX = "docs/program/evidence/"
TASK_EVIDENCE_DIRECTORIES = {
    "test_reports": "test-reports",
    "reviews": "reviews",
    "screenshots": "screenshots",
}
VERIFICATION_METADATA_PATTERNS = (
    "docs/program/TASK_GRAPH.yaml",
    "docs/program/FEATURE_REGISTRY.yaml",
    "docs/program/PROJECT_STATE.md",
    "docs/program/TRACEABILITY_MATRIX.md",
    "docs/program/evidence/**",
)
RESOURCE_ROOT_PURPOSE = (
    "Attributable SDKs, bounded caches, task worktrees, portable PostgreSQL data, "
    "and generated build evidence outside the synced path"
)
TEST_ENVIRONMENT_KEYS = {"os", "architecture", "execution_context"}
TEST_ENVIRONMENT_VALUES = {
    "os": {"windows", "linux", "macos"},
    "architecture": {"x86_64", "arm64"},
    "execution_context": {"local", "ci", "container", "test_fixture"},
}
TOOL_VERSION_KEYS = {
    "python",
    "powershell",
    "git",
    "flutter",
    "dart",
    "java",
    "android_sdk",
    "postgresql",
    "docker",
}
UTC_TIMESTAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
FEATURE_ID = re.compile(r"TL-F-R[0-6]-[A-Z0-9]+(?:-[A-Z0-9]+)*$")
EVIDENCE_IDENTIFIER = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:+-]{0,127}$")
REVIEWER_ROLE = re.compile(r"[a-z][a-z0-9_]{2,63}$")
SHA256_ARTIFACT = re.compile(r"sha256:[0-9a-f]{64}$")
FULL_GIT_COMMIT = re.compile(r"[0-9a-f]{40}$")
APPROVAL_EVENT_SUFFIX = re.compile(r"([GR])-(\d{4})$")
MAX_BOUNDED_NUMBER = 1_000_000_000_000
MAX_DURATION_SECONDS = 604_800
MAX_RESULT_COUNT = 10_000_000
MAX_HOST_MEMORY_GB = 1_000_000
MAX_SCREENSHOT_BYTES = 10 * 1024 * 1024
MAX_SCREENSHOT_DIMENSION = 4096
MAX_SCREENSHOT_DECOMPRESSED_BYTES = 32 * 1024 * 1024
MAX_TYPED_EVIDENCE_BYTES = 1 * 1024 * 1024
MAX_TASK_EVIDENCE_ENTRIES = 64
MAX_REPORT_COMMANDS = 128
MAX_REVIEW_FINDINGS = 128
MAX_REVIEW_TEST_EVIDENCE = 128
MAX_DEVICE_TESTS = 128
MAX_DATASET_METRICS = 128
MAX_APPROVAL_EVENTS = 256
MAX_APPROVAL_EVENT_ACTORS = 32
MAX_APPROVAL_LEDGER_ACTORS = 128
MAX_APPROVAL_REVIEWED_EVIDENCE = 128
VERIFIED_PROTECTED_FIELDS = (
    "id",
    "release",
    "title",
    "objective",
    "owner_agent",
    "dependencies",
    "owned_paths",
    "integration_owned_paths",
    "forbidden_paths",
    "inputs",
    "acceptance_criteria",
    "required_tests",
    "required_reviewers",
)
R0_TASK_IDS = tuple(f"TL-R0-{index:03d}" for index in range(1, 11))
# Canonical SHA-256 of each task's VERIFIED_PROTECTED_FIELDS projection. Runtime
# status, blockers, next action, and evidence are intentionally excluded.
R0_TASK_SPEC_SHA256 = {
    "TL-R0-001": "c03c6a6dfbbeda602acb8d86076549964b856d67e66c9c19ae5afaf337ba6f1d",
    "TL-R0-002": "d0e5a1128ccf121b95a4c0a3e2f3ed3e74785df6e69bd89bcf5e221898ea6323",
    "TL-R0-003": "5d1a81f9bf8cda119ef150246c59f3781c2f050eb3eca4063e79acebd2927055",
    "TL-R0-004": "309ec095157c77c8637d29e1a224056ffb1483e9e1c245ebd1385fc031092266",
    "TL-R0-005": "e7452dbf463de3de574d0756332882a3b9ca94881721cb24a7d4dd4e70e6e736",
    "TL-R0-006": "10a759b4a2ab5ab6bdc6a00a93d8c5301489f0e877818bcfe110183928b0c784",
    "TL-R0-007": "235a609821c73bf0674da99e4172bb303694d3f4c79f535dd96664e8c5c9ff9d",
    "TL-R0-008": "67bdea067732468688ed51874ea3d6891df3ce656fafb933ebd1f83197114c9a",
    "TL-R0-009": "1da1207e7dd1a71348e2808c6d300c77544af1d7e810d2cb86c81af998ed385c",
    "TL-R0-010": "484d42ca77f2e35bc1d7c142aa36a92de9c9db0a208d793549220c9cc8712bf6",
}
R0_FEATURE_SEMANTICS = {
    "TL-F-R0-AGENTS": ("R0", "Project delivery contract and agent pool", (), ()),
    "TL-F-R0-CONTROL": ("R0", "Durable delivery control plane", (), ("TL-R0-001",)),
    "TL-F-R0-CONTRACT": ("R0", "Canonical heartbeat and structured-error contracts", (), ("TL-R0-002",)),
    "TL-F-R0-POSTGRES": ("R0", "PostgreSQL migration-aware readiness", (), ("TL-R0-003", "TL-R0-004")),
    "TL-F-R0-API": ("R0", "FastAPI liveness readiness status and version", (), ("TL-R0-005",)),
    "TL-F-R0-CLIENT": ("R0", "Generated Dart API client", (), ("TL-R0-006",)),
    "TL-F-R0-MOBILE": ("R0", "Flutter system-status experience", ("TL-D-007", "TL-D-013"), ("TL-R0-007", "TL-R0-008")),
    "TL-F-R0-CI": ("R0", "Sequential quality and supply-chain harness", (), ("TL-R0-009", "TL-R0-010")),
    "TL-F-R1-IDENTITY": ("R1", "Adult identity consent and profile", ("TL-D-001", "TL-D-002", "TL-D-005", "TL-D-009", "TL-D-015"), ()),
    "TL-F-R1-EVIDENCE": ("R1", "Evidence approval and grounded assistant", ("TL-D-008",), ()),
    "TL-F-R1-MEALS": ("R1", "Manual meals portions and deterministic nutrition", ("TL-D-003", "TL-D-008"), ()),
    "TL-F-R1-PLANS": ("R1", "Safe goals and deterministic weekly plans", ("TL-D-003", "TL-D-004"), ()),
    "TL-F-R1-PRIVACY": ("R1", "Progress export and deletion", ("TL-D-005", "TL-D-009"), ()),
    "TL-F-R2-MEAL-AI": ("R2", "Meal image candidate assistance", ("TL-D-003", "TL-D-011", "TL-D-012"), ()),
    "TL-F-R3-MOVEMENT": ("R3", "Workouts routes and nearby places", ("TL-D-004", "TL-D-005", "TL-D-013"), ()),
    "TL-F-R3-POSE": ("R3", "Two-exercise optional on-device pose", ("TL-D-004", "TL-D-012", "TL-D-013"), ()),
    "TL-F-R4-ADVANCED": ("R4", "Advanced gated intelligence and personalisation", ("TL-D-003", "TL-D-004", "TL-D-006", "TL-D-008", "TL-D-011", "TL-D-012", "TL-D-017"), ()),
    "TL-F-R5-OPERATIONS": ("R5", "Operational hardening and reference deployment", ("TL-D-005", "TL-D-009", "TL-D-010", "TL-D-015", "TL-D-017"), ()),
    "TL-F-R6-PILOT": ("R6", "Controlled-pilot validation package", ("TL-D-001", "TL-D-002", "TL-D-003", "TL-D-004", "TL-D-005", "TL-D-006", "TL-D-007", "TL-D-008", "TL-D-009", "TL-D-010", "TL-D-011", "TL-D-012", "TL-D-013", "TL-D-014", "TL-D-015", "TL-D-016", "TL-D-017"), ()),
}
R0_DECISION_IDS = tuple(f"TL-D-{index:03d}" for index in range(1, 18))
# Canonical SHA-256 of DECISIONS_REQUIRED rows excluding Status, and
# HUMAN_APPROVALS rows restricted to ID, Gate, and Required named approver.
R0_DECISION_SPEC_SHA256 = {
    "TL-D-001": "918b3993e68d057f12855dc60af84a4e7680b6280809d9cf989466f434eec798",
    "TL-D-002": "d64ecabbd9b55d6d385ad17374b7224a6f660db31baf9a9a52c5adbbf8f056af",
    "TL-D-003": "2ea5d82919345fb5d3e1e6d07362f57005df8905be0105f15fd94b22fdfc816e",
    "TL-D-004": "629a624eb01c707eee43c93e143bfbd3ba81748b1cb621f646dcf6c79aef870e",
    "TL-D-005": "c5ac22194ce7f56278e76ff5fbad910ca4629e3639581434d2e6b48fbcffa820",
    "TL-D-006": "36fab172fa3dc91e24afee4a4d10d6350ae8c6c97a949626feefcb9319c8f4b6",
    "TL-D-007": "0746ab07f5e43b3b908b3c86e05d5f376253a2b806d029d95205940fa32ff207",
    "TL-D-008": "033ae3995ac27402aa871b8476a5489e32fe49bec45ed4230881e01f574aa81a",
    "TL-D-009": "5891f22bb072b1da6a3e9f3df2e9f1a561c631b03a08c8e12d560eb99f6a37d5",
    "TL-D-010": "03c625a806c4d9df9dcf9997e623a3ce89c4fdf49ecf95aae8aa75dde9f4c893",
    "TL-D-011": "a40f1a585131100d25a351a66e0f38f5569a621270f1dc3e56c00229259b6ea2",
    "TL-D-012": "f251cac5d2a856cd2c4e24e56b2a06f873fb98c4964e36919f28c7e8e810e2b1",
    "TL-D-013": "3e81f746fda726da5c8d3baaa9e5a159ba445d573a54b81f380b5c5abf47e421",
    "TL-D-014": "7d8a97d8e0c07e04f39a6bda22739aa85ef23e5842e58544ba16ebfaecbf821e",
    "TL-D-015": "851bb92a2c6b1a5affc489ba6b37baa31dd14a680b9a6a50fe2483bc459683ba",
    "TL-D-016": "c87809f3f00ff007577a7738fe9c060c6c6eafe1a5c5bf3977d4813a39b013be",
    "TL-D-017": "2041d96b5b25144715642874c38eb470c34eaef422660c54cc646c331a1f8e4a",
}
R0_HUMAN_GATE_SPEC_SHA256 = {
    "TL-D-001": "b86f23cb1fbeb3f8427b1480b3e2cf7b7ba3bb557ceffc4efbffb70fa7bf2c0d",
    "TL-D-002": "cff03791e68d5b97e0e0c9382cd4545f7757fab8ae9e0e2d6f97e30981600a79",
    "TL-D-003": "114b0b893ede2271f0044f9405ac16dd816185639e39f39f571e3990cf9df6c5",
    "TL-D-004": "c7e8a77d60ea6526255f05dd00f792ba6f11cb2d28d56e1339a9a949b6d45cac",
    "TL-D-005": "4968df8d2872cd375d55e4f534a9cb06aa3c0c60041ff8dbe94f3b890d7f86de",
    "TL-D-006": "c331bdadd4351f3dbab1176653d3e86330ad657d42731bc9e253fdfff17dde2b",
    "TL-D-007": "fd75a394b36db916844835a8f4863a2d1a35610071cc1142e90f07e5ced7762e",
    "TL-D-008": "4a056331ce051af97441eb6b4acefbc050eedd2a0c13d3605770802fd29dcb45",
    "TL-D-009": "d8c0871da3cd366869a57ebb647921f02e50222920db6abb7525d8b8c8f4bc58",
    "TL-D-010": "d2f1cf4ee91951710d73b1211502c43e3b19ece5ab8ec4cfac4db9b3955d80c0",
    "TL-D-011": "c2c0b9d8cf5b65bc00a2c0868db0a1248b554c732ca2689666bf3d97f72f447f",
    "TL-D-012": "5d33d856af2c295873b411b4e34b7995ab1b06a247b7a9cc1db72b18fdc35ded",
    "TL-D-013": "47c789a15b8d8495db2a7eeb5f35f314a3daed13704daf4e2cb3211aacd248e8",
    "TL-D-014": "4244ca9b5770e9b2daf7d5cf0122eaa5e20d47010e74ff0d8ff5607a3090f84a",
    "TL-D-015": "9e11b8d7bf2ac736809ed2ae3369005f0508a8de147425a22f377241d27aec59",
    "TL-D-016": "0bd6acb5ddf20c5039a9ee387e962b7cf357d5cfcc9b5dfe8e2252af26d21f97",
    "TL-D-017": "1e3f03b22f861efad44f26a4d68c0dc6af24bac1c5790f294d4aa01c4d365edc",
}
SENSITIVE_FIELD_NAME = re.compile(
    r"(?:^|[_-])(?:api[_-]?key|authorization|cookie|credential|dsn|password|secret|token)(?:$|[_-])",
    re.IGNORECASE,
)
ABSOLUTE_PRIVATE_PATH = re.compile(
    r"(?i)(?<![A-Za-z0-9])(?:[A-Za-z]:[\\/]|\\\\|"
    r"/(?:home|users|tmp|var/tmp|var/lib|etc|opt|srv|usr/local|run|data|app|root|workspace|private/var|github/workspace)(?:/|$)|"
    r"/mnt/[a-z]/users(?:/|$))"
)
SECRET_VALUE = re.compile(
    r"(?i)(?:-----BEGIN [A-Z ]*PRIVATE KEY-----|"
    r"(?:api[_-]?key|authorization|cookie|credential|dsn|password|secret|token)\s*[:=]\s*\S+|"
    r"sk-proj-[A-Za-z0-9_-]{8,}|"
    r"sk-svcacct-[A-Za-z0-9_-]{8,}|"
    r"ghp_[A-Za-z0-9]{20,}|"
    r"github_pat_[A-Za-z0-9_]{20,}|"
    r"AKIA[0-9A-Z]{16}|"
    r"xox[A-Za-z]-[A-Za-z0-9-]{8,}|"
    r"sk_live_[A-Za-z0-9]{8,}|"
    r"(?<![A-Za-z0-9])Bearer\s+[A-Za-z0-9._~+/-]{8,}|"
    r"eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}|"
    r"(?:postgres(?:ql)?|mysql|mariadb|mongodb(?:\+srv)?|redis|amqp)://\S+|"
    r"https://[^\s/@:]+(?::[^\s/@]*)?@[^\s/]+/\S+|"
    r"sentinel[^\s]*(?:secret|token|password|credential))"
)
PROJECT_STATE_LABELS = (
    "Current release:",
    "Current integration branch:",
    "Completed and verified:",
    "Integrated but not fully verified:",
    "Active agents and task IDs:",
    "Open failures:",
    "Human decisions required:",
    "External credentials/data/hardware required:",
    "Risks changed:",
    "Tests run:",
    "Latest stable checkpoint:",
    "Next dependency-safe tasks:",
    "Next exact orchestrator action:",
)
SHARED_PATH_MARKERS = (
    "contracts/openapi",
    "/migrations",
    "decision_log.md",
)
SCRIPT_REFERENCE = re.compile(
    r"(?<![A-Za-z0-9_.-])([A-Za-z0-9_.\-/]+\.(?:ps1|py))(?=\s|$)", re.IGNORECASE
)
TASK_ID = re.compile(r"TL-R0-\d{3}$")
DECISION_ID = re.compile(r"TL-D-\d{3}$")


class ControlPlaneError(RuntimeError):
    """A deterministic, user-safe control-plane validation failure."""


def fail(message: str) -> NoReturn:
    raise ControlPlaneError(message)


def check(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def read_text(relative: str) -> str:
    path = ROOT / relative
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        fail(f"Cannot read required UTF-8 file {relative}: {type(exc).__name__}")


def parse_bounded_json_int(raw: str, label: str) -> int:
    digits = raw.lstrip("-")
    check(bool(digits) and len(digits) <= 16, f"{label} contains an out-of-range JSON integer")
    try:
        value = int(raw)
    except ValueError:
        fail(f"{label} contains an invalid JSON integer")
    check(-MAX_BOUNDED_NUMBER <= value <= MAX_BOUNDED_NUMBER, f"{label} contains an out-of-range JSON integer")
    return value


def parse_bounded_json_float(raw: str, label: str) -> float:
    try:
        value = float(raw)
    except ValueError:
        fail(f"{label} contains an invalid JSON number")
    check(math.isfinite(value) and -MAX_BOUNDED_NUMBER <= value <= MAX_BOUNDED_NUMBER, f"{label} contains an out-of-range JSON number")
    return value


def parse_json_object(raw: str, label: str) -> dict:
    try:
        value = json.loads(
            raw,
            parse_int=lambda item: parse_bounded_json_int(item, label),
            parse_float=lambda item: parse_bounded_json_float(item, label),
            parse_constant=lambda _: fail(f"{label} contains a non-finite JSON number"),
        )
    except json.JSONDecodeError as exc:
        fail(f"{label} is invalid JSON at line {exc.lineno}")
    except ValueError:
        fail(f"{label} contains an invalid or out-of-range JSON number")
    check(isinstance(value, dict), f"{label} must contain one object")
    return value


def load_json_yaml(relative: str) -> dict:
    return parse_json_object(read_text(relative), relative)


def require_string_list(value: object, label: str, *, nonempty: bool = False) -> list[str]:
    check(isinstance(value, list), f"{label} must be a list")
    check(all(isinstance(item, str) and item.strip() for item in value), f"{label} has a blank or non-string item")
    if nonempty:
        check(bool(value), f"{label} must not be empty")
    return value


def ancestors_for(task_id: str, by_id: dict[str, dict], memo: dict[str, set[str]], stack: set[str]) -> set[str]:
    if task_id in memo:
        return memo[task_id]
    check(task_id not in stack, f"Task dependency cycle includes {task_id}")
    stack.add(task_id)
    ancestors: set[str] = set()
    for dependency in by_id[task_id]["dependencies"]:
        check(dependency in by_id, f"Unknown dependency {dependency} in {task_id}")
        ancestors.add(dependency)
        ancestors.update(ancestors_for(dependency, by_id, memo, stack))
    stack.remove(task_id)
    memo[task_id] = ancestors
    return ancestors


def normalize_pattern(pattern: str) -> tuple[str, bool]:
    normalized = pattern.replace("\\", "/").strip().strip("/").lower()
    check(normalized and not normalized.startswith("../") and "/../" not in normalized, f"Unsafe path claim: {pattern}")
    wildcard_at = min((normalized.find(char) for char in "*?[" if char in normalized), default=-1)
    if wildcard_at >= 0:
        base = normalized[:wildcard_at].rstrip("/")
        check(bool(base), f"Over-broad path claim: {pattern}")
        return base, True
    return normalized, False


def patterns_overlap(first: str, second: str) -> bool:
    first_base, first_glob = normalize_pattern(first)
    second_base, second_glob = normalize_pattern(second)
    if first_base == second_base:
        return True
    if first_glob and (second_base.startswith(first_base + "/") or second_base == first_base):
        return True
    if second_glob and (first_base.startswith(second_base + "/") or first_base == second_base):
        return True
    return False


def pattern_covers(pattern: str, relative: str) -> bool:
    base, is_glob = normalize_pattern(pattern)
    target = relative.replace("\\", "/").strip("/").lower()
    return target == base or (is_glob and target.startswith(base + "/"))


def normalize_command(command: str) -> str:
    return " ".join(command.split())


def is_exact_int(value: object) -> bool:
    return type(value) is int


def is_finite_number(
    value: object,
    *,
    minimum: int | float = -MAX_BOUNDED_NUMBER,
    maximum: int | float = MAX_BOUNDED_NUMBER,
) -> bool:
    if type(value) is int:
        return minimum <= value <= maximum
    if type(value) is float:
        return math.isfinite(value) and minimum <= value <= maximum
    return False


def parse_nonfuture_date(value: object, label: str) -> date:
    check(type(value) is str and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) is not None, f"{label} must be an ISO date")
    try:
        parsed = date.fromisoformat(value)
    except ValueError:
        fail(f"{label} must be a valid ISO date")
    check(parsed <= date.today(), f"{label} cannot be in the future")
    return parsed


def parse_iso_date(value: object, label: str) -> date:
    check(type(value) is str and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) is not None, f"{label} must be an ISO date")
    try:
        return date.fromisoformat(value)
    except ValueError:
        fail(f"{label} must be a valid ISO date")


def validate_approval_event_expiry(event: dict, *, require_current: bool) -> bool:
    approval_date = parse_nonfuture_date(event.get("approval_date"), "Human approval event date")
    expiry = event.get("expires_or_review_on")
    if expiry == "REVIEW_ON_ARTIFACT_OR_SCOPE_CHANGE":
        return True
    expiry_date = parse_iso_date(expiry, "Human approval event expiry")
    check(expiry_date >= approval_date, "Human approval event expiry predates its approval date")
    if require_current:
        check(expiry_date >= date.today(), "Human approval event is expired")
    return expiry_date >= date.today()


def exact_value_equal(actual: object, expected: object) -> bool:
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return set(actual) == set(expected) and all(exact_value_equal(actual[key], value) for key, value in expected.items())
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(exact_value_equal(left, right) for left, right in zip(actual, expected, strict=True))
    return actual == expected


def validate_sanitized_evidence(value: object, label: str = "evidence") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            check(isinstance(key, str) and not SENSITIVE_FIELD_NAME.search(key), f"{label} contains a prohibited sensitive field name")
            validate_sanitized_evidence(child, f"{label}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            validate_sanitized_evidence(child, f"{label}[{index}]")
    elif isinstance(value, str):
        check(0 < len(value) <= 2048, f"{label} is blank or unbounded")
        check(re.search(r"[\x00-\x1f\x7f]", value) is None, f"{label} contains control characters")
        check(ABSOLUTE_PRIVATE_PATH.search(value) is None, f"{label} contains an absolute private path")
        check(SECRET_VALUE.search(value) is None, f"{label} contains secret-like content")


def validate_binary_chunk_sanitized(value: bytes, label: str) -> None:
    text = value.decode("latin-1")
    check(ABSOLUTE_PRIVATE_PATH.search(text) is None, f"{label} contains an absolute private path")
    check(SECRET_VALUE.search(text) is None, f"{label} contains secret-like content")


def validate_human_actor_list(value: object, label: str) -> list[str]:
    check(
        isinstance(value, list)
        and 1 <= len(value) <= MAX_APPROVAL_EVENT_ACTORS
        and all(type(identity) is str and looks_like_named_human(identity) for identity in value)
        and len(value) == len({identity.casefold() for identity in value}),
        f"{label} requires a bounded unique list of actual named humans",
    )
    return value


def git_commit_exists(reference: str) -> bool:
    if re.fullmatch(r"[0-9a-f]{7,40}", reference) is None:
        return False
    try:
        result = subprocess.run(
            ["git", "cat-file", "-e", f"{reference}^{{commit}}"],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return False
    return result.returncode == 0


def git_resolve_commit(reference: str) -> str | None:
    if not git_commit_exists(reference):
        return None
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--verify", f"{reference}^{{commit}}"],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        return None
    resolved = result.stdout.strip().lower()
    return resolved if result.returncode == 0 and re.fullmatch(r"[0-9a-f]{40,64}", resolved) else None


def git_head_commit() -> str | None:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--verify", "HEAD^{commit}"],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        return None
    resolved = result.stdout.strip().lower()
    return resolved if result.returncode == 0 and FULL_GIT_COMMIT.fullmatch(resolved) is not None else None


def git_path_output(arguments: list[str]) -> list[str]:
    try:
        result = subprocess.run(
            ["git", *arguments],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        fail("Cannot inspect exact Git candidate state")
    check(result.returncode == 0, "Cannot inspect exact Git candidate state")
    try:
        return [item.decode("utf-8", errors="strict").replace("\\", "/") for item in result.stdout.split(b"\0") if item]
    except UnicodeError:
        fail("Git candidate paths are not valid UTF-8")


def git_candidate_changes(reference: str) -> set[str]:
    return {
        *git_path_output(["diff", "--name-only", "-z", "--cached", reference, "--"]),
        *git_path_output(["diff", "--name-only", "-z", "--"]),
        *git_path_output(["ls-files", "--others", "--exclude-standard", "-z"]),
    }


def git_staged_changes(reference: str) -> set[str]:
    return set(git_path_output(["diff", "--name-only", "-z", "--cached", reference, "--"]))


def git_worktree_changes() -> set[str]:
    return {
        *git_path_output(["diff", "--name-only", "-z", "--"]),
        *git_path_output(["ls-files", "--others", "--exclude-standard", "-z"]),
    }


def git_unmerged_paths() -> set[str]:
    return set(git_path_output(["diff", "--name-only", "--diff-filter=U", "-z", "--"] ) )


def validate_staged_verification_candidate(reference: str) -> None:
    resolved = git_resolve_commit(reference)
    check(resolved is not None and resolved == git_head_commit(), "Verified task commit must be the exact checked-out integration candidate")
    check(not git_unmerged_paths(), "Verified task cannot use a conflicted Git index")
    check(not git_worktree_changes(), "Verified task working-tree bytes must exactly match the staged candidate")
    staged_changes = git_staged_changes(resolved)
    check(bool(staged_changes), "New VERIFIED transition requires a staged verification checkpoint")
    material_changes = sorted(
        relative
        for relative in staged_changes
        if not any(pattern_covers(pattern, relative) for pattern in VERIFICATION_METADATA_PATTERNS)
    )
    check(not material_changes, "Verified task candidate bytes differ from its canonical commit outside evidence metadata")


def validate_verification_candidate(reference: str, task: dict | None = None) -> None:
    if task is None:
        validate_staged_verification_candidate(reference)
        return
    validate_task_verification_lifecycle(task, reference)


def git_is_ancestor(ancestor: str, descendant: str) -> bool:
    resolved_ancestor = git_resolve_commit(ancestor)
    resolved_descendant = git_resolve_commit(descendant)
    if resolved_ancestor is None or resolved_descendant is None:
        return False
    try:
        result = subprocess.run(
            ["git", "merge-base", "--is-ancestor", resolved_ancestor, resolved_descendant],
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        fail("Cannot inspect verification ancestry")
    check(result.returncode in {0, 1}, "Cannot inspect verification ancestry")
    return result.returncode == 0


def git_parent_commits(reference: str) -> list[str]:
    resolved = git_resolve_commit(reference)
    check(resolved is not None, "Verification checkpoint commit is missing")
    try:
        result = subprocess.run(
            ["git", "rev-list", "--parents", "-n", "1", resolved],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        fail("Cannot inspect verification checkpoint parents")
    parts = result.stdout.strip().lower().split()
    check(result.returncode == 0 and parts and parts[0] == resolved, "Cannot inspect verification checkpoint parents")
    check(all(FULL_GIT_COMMIT.fullmatch(item) is not None for item in parts), "Verification checkpoint contains an invalid commit identifier")
    return parts[1:]


def git_ancestry_path(ancestor: str, descendant: str) -> list[str]:
    resolved_ancestor = git_resolve_commit(ancestor)
    resolved_descendant = git_resolve_commit(descendant)
    check(resolved_ancestor is not None and resolved_descendant is not None, "Verification ancestry contains a missing commit")
    check(git_is_ancestor(resolved_ancestor, resolved_descendant), "Canonical implementation commit is not an ancestor of the current HEAD")
    try:
        result = subprocess.run(
            ["git", "rev-list", "--ancestry-path", "--reverse", f"{resolved_ancestor}..{resolved_descendant}"],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        fail("Cannot inspect verification ancestry path")
    commits = [line.strip().lower() for line in result.stdout.splitlines() if line.strip()]
    check(result.returncode == 0 and all(FULL_GIT_COMMIT.fullmatch(item) is not None for item in commits), "Cannot inspect verification ancestry path")
    return commits


def git_commit_paths_between(parent: str, child: str) -> list[str]:
    return git_path_output(["diff", "--name-only", "-z", parent, child, "--"])


def git_commit_paths(reference: str) -> list[str]:
    try:
        result = subprocess.run(
            ["git", "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", reference],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        return []
    return [line.strip().replace("\\", "/") for line in result.stdout.splitlines() if line.strip()] if result.returncode == 0 else []


def parse_git_index_entries(output: str) -> list[tuple[str, str, int, str]]:
    entries: list[tuple[str, str, int, str]] = []
    for record in output.split("\0"):
        if not record:
            continue
        try:
            header, path = record.split("\t", 1)
            mode, object_id, stage_text = header.split()
            stage = int(stage_text)
        except (ValueError, TypeError):
            fail("Evidence has malformed Git index metadata")
        check(re.fullmatch(r"[0-9a-f]{40,64}", object_id) is not None, "Evidence Git object ID is invalid")
        entries.append((mode, object_id, stage, path.replace("\\", "/")))
    return entries


def git_index_entries(relative: str) -> list[tuple[str, str, int, str]]:
    try:
        result = subprocess.run(
            ["git", "ls-files", "--stage", "-z", "--error-unmatch", "--", relative],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        return []
    if result.returncode != 0 or not result.stdout.strip():
        return []
    return parse_git_index_entries(result.stdout)


def git_index_entries_under(relative: str) -> list[tuple[str, str, int, str]]:
    try:
        result = subprocess.run(
            ["git", "ls-files", "--stage", "-z", "--", relative],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        fail("Cannot enumerate staged evidence")
    check(result.returncode == 0, "Cannot enumerate staged evidence")
    return parse_git_index_entries(result.stdout)


def validate_evidence_git_entries(entries: list[tuple[str, str, int, str]], relative: str) -> str:
    check(bool(entries), "Evidence must be staged or tracked")
    check(len(entries) == 1 and entries[0][2] == 0, "Evidence must have exactly one conflict-free stage-0 Git index entry")
    mode, object_id, _, indexed_path = entries[0]
    check(indexed_path == relative, "Evidence Git index path does not match its reference")
    validate_evidence_git_mode(mode)
    return object_id


def validate_evidence_git_mode(mode: str | None) -> None:
    check(mode is not None, "Evidence must be staged or tracked")
    check(mode in {"100644", "100755"}, "Evidence must be a regular staged/tracked file, not a symlink, reparse point, or submodule")


def read_git_blob(object_id: str) -> bytes:
    try:
        result = subprocess.run(
            ["git", "cat-file", "blob", object_id],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        fail("Evidence stage-0 Git blob is unavailable")
    check(result.returncode == 0, "Evidence stage-0 Git blob is unavailable")
    return result.stdout


def git_blob_size(object_id: str) -> int:
    try:
        result = subprocess.run(
            ["git", "cat-file", "-s", object_id],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        fail("Evidence Git blob size is unavailable")
    value = result.stdout.strip()
    check(result.returncode == 0 and value.isdigit(), "Evidence Git blob size is unavailable")
    size = int(value)
    check(0 <= size <= MAX_BOUNDED_NUMBER, "Evidence Git blob size is outside the bounded policy")
    return size


def git_blob_entry_at_commit(reference: str, relative: str) -> tuple[str, str] | None:
    resolved = git_resolve_commit(reference)
    check(resolved is not None, "Evidence history cites a missing commit")
    try:
        result = subprocess.run(
            ["git", "ls-tree", "-z", resolved, "--", relative],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        fail("Cannot inspect historical evidence blob")
    check(result.returncode == 0, "Cannot inspect historical evidence blob")
    if not result.stdout:
        return None
    records = [record for record in result.stdout.split(b"\0") if record]
    check(len(records) == 1, "Historical evidence path is ambiguous")
    try:
        header, raw_path = records[0].split(b"\t", 1)
        mode, object_type, object_id = header.decode("ascii").split()
        indexed_path = raw_path.decode("utf-8", errors="strict").replace("\\", "/")
    except (ValueError, UnicodeError):
        fail("Historical evidence metadata is malformed")
    check(indexed_path == relative and object_type == "blob" and mode in {"100644", "100755"}, "Historical evidence must remain one regular file")
    check(re.fullmatch(r"[0-9a-f]{40,64}", object_id) is not None, "Historical evidence blob identifier is invalid")
    return mode, object_id


def load_json_blob(object_id: str, label: str) -> dict:
    size = git_blob_size(object_id)
    check(2 <= size <= MAX_TYPED_EVIDENCE_BYTES, f"{label} size is outside the bounded typed-evidence policy")
    try:
        encoded = read_git_blob(object_id)
        check(len(encoded) == size, f"{label} blob size changed during validation")
        raw = encoded.decode("utf-8")
    except UnicodeError:
        fail(f"{label} is not valid UTF-8 JSON")
    return parse_json_object(raw, label)


def load_json_at_commit(reference: str, relative: str) -> dict | None:
    entry = git_blob_entry_at_commit(reference, relative)
    return None if entry is None else load_json_blob(entry[1], f"Historical {relative}")


def task_at_commit(reference: str, task_id: str) -> dict | None:
    graph = load_json_at_commit(reference, "docs/program/TASK_GRAPH.yaml")
    if graph is None:
        return None
    tasks = graph.get("tasks")
    check(isinstance(tasks, list), "Historical task graph is malformed")
    matches = [task for task in tasks if isinstance(task, dict) and task.get("id") == task_id]
    check(len(matches) <= 1, "Historical task graph has duplicate task identities")
    return matches[0] if matches else None


def git_path_history(relative: str, head: str) -> list[str]:
    resolved = git_resolve_commit(head)
    check(resolved is not None, "Evidence history HEAD is missing")
    try:
        result = subprocess.run(
            ["git", "log", "--format=%H", "--reverse", "--follow", resolved, "--", relative],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        fail("Cannot inspect append-only evidence history")
    commits = [line.strip().lower() for line in result.stdout.splitlines() if line.strip()]
    check(result.returncode == 0 and all(FULL_GIT_COMMIT.fullmatch(item) is not None for item in commits), "Cannot inspect append-only evidence history")
    return commits


def git_historical_paths_under(prefix: str, head: str) -> set[str]:
    resolved = git_resolve_commit(head)
    check(resolved is not None, "Evidence history HEAD is missing")
    return set(git_path_output(["log", "--format=", "--name-only", "-z", resolved, "--", prefix]))


def is_reparse_or_symlink(path: Path) -> bool:
    try:
        info = path.lstat()
    except OSError:
        return True
    return path.is_symlink() or bool(getattr(info, "st_file_attributes", 0) & 0x400)


def validate_indexed_evidence(relative: str, evidence_type: str) -> tuple[Path, str]:
    normalized = relative.replace("\\", "/")
    candidate = Path(normalized)
    check(evidence_type in EVIDENCE_ROOTS, f"Unknown evidence type {evidence_type}")
    check(not candidate.is_absolute() and normalized and ".." not in candidate.parts, f"Unsafe {evidence_type} evidence path")
    check(not normalized.lower().startswith(".git/"), f"Git internals cannot be {evidence_type} evidence")
    matched_root = next((root for root in EVIDENCE_ROOTS[evidence_type] if normalized.lower().startswith(root)), None)
    check(matched_root is not None, f"{evidence_type} evidence is outside its approved roots")
    object_id = validate_evidence_git_entries(git_index_entries(normalized), normalized)
    try:
        lexical_path = ROOT / candidate
        current = lexical_path
        root_resolved = ROOT.resolve(strict=True)
        while current != ROOT:
            check(not is_reparse_or_symlink(current), f"{evidence_type} evidence cannot traverse a symlink or reparse point")
            current = current.parent
        resolved = lexical_path.resolve(strict=True)
        approved_root = (ROOT / matched_root.rstrip("/")).resolve(strict=True)
        approved_root.relative_to(root_resolved)
        resolved.relative_to(approved_root)
    except (OSError, ValueError):
        fail(f"{evidence_type} evidence file is missing or escaped its approved root")
    check(resolved.is_file(), f"{evidence_type} evidence must be a file")
    return resolved, object_id


def resolve_indexed_evidence(relative: str, evidence_type: str) -> Path:
    return validate_indexed_evidence(relative, evidence_type)[0]


def validate_evidence_document(document: object, evidence_type: str) -> dict:
    check(isinstance(document, dict), f"{evidence_type} evidence must be one JSON object")
    expected_schema = 2 if evidence_type == "human_approval_ledger" else 1
    check(is_exact_int(document.get("schema_version")) and document["schema_version"] == expected_schema, f"{evidence_type} evidence schema_version must be integer {expected_schema}")
    check(document.get("evidence_type") == evidence_type, f"Evidence type confusion: expected {evidence_type}")
    if evidence_type == "test_report":
        check(set(document) == {"schema_version", "evidence_type", "task_id", "commit", "generated_at", "environment", "tool_versions", "duration_seconds", "resource_status", "commands", "summary"}, "Test report fields drifted or are incomplete")
        check(isinstance(document.get("task_id"), str) and TASK_ID.fullmatch(document["task_id"]) is not None, "Test report has an invalid task_id")
        check(git_commit_exists(document.get("commit", "")), "Test report cites a missing commit")
        check(isinstance(document.get("generated_at"), str) and UTC_TIMESTAMP.fullmatch(document["generated_at"]) is not None, "Test report timestamp is invalid")
        environment = document.get("environment")
        check(isinstance(environment, dict) and set(environment) == TEST_ENVIRONMENT_KEYS, "Test report environment fields drifted")
        check(all(type(environment[key]) is str and environment[key] in allowed for key, allowed in TEST_ENVIRONMENT_VALUES.items()), "Test report environment values are invalid")
        tool_versions = document.get("tool_versions")
        check(isinstance(tool_versions, dict) and tool_versions and set(tool_versions) <= TOOL_VERSION_KEYS, "Test report tool-version fields are not allowlisted")
        check(all(type(value) is str and value.strip() for value in tool_versions.values()), "Test report tool versions are incomplete")
        check(is_finite_number(document.get("duration_seconds"), minimum=0, maximum=MAX_DURATION_SECONDS), "Test report duration is invalid")
        resource = document.get("resource_status")
        check(isinstance(resource, dict) and set(resource) == {"cap_gb", "accounted_bytes", "status", "host_free_memory_gb"}, "Test report resource status fields are incomplete")
        check(is_exact_int(resource["cap_gb"]) and resource["cap_gb"] == 18 and is_exact_int(resource["accounted_bytes"]) and 0 <= resource["accounted_bytes"] < 18 * 1024**3 and resource["status"] in {"OK", "WARNING"}, "Test report resource status is invalid")
        check(resource["host_free_memory_gb"] is None or is_finite_number(resource["host_free_memory_gb"], minimum=0, maximum=MAX_HOST_MEMORY_GB), "Test report memory value is invalid")
        commands = document.get("commands")
        check(isinstance(commands, list) and 1 <= len(commands) <= MAX_REPORT_COMMANDS, "Test report must record a bounded command list")
        for command in commands:
            check(isinstance(command, dict) and set(command) == {"command", "exit_code", "duration_seconds", "result_count", "sanitized_failure"}, "Test report command fields are incomplete")
            check(isinstance(command.get("command"), str) and command["command"].strip() and is_exact_int(command.get("exit_code")) and command["exit_code"] == 0, "Test report contains a missing or failing command")
            check(is_finite_number(command["duration_seconds"], minimum=0, maximum=MAX_DURATION_SECONDS), "Test command duration is invalid")
            check(is_exact_int(command["result_count"]) and 0 <= command["result_count"] <= MAX_RESULT_COUNT, "Test command result count is invalid")
            check(command["sanitized_failure"] is None, "Passing test command must have null sanitized_failure")
        check(isinstance(document.get("summary"), str) and document["summary"].strip(), "Test report summary is missing")
    elif evidence_type == "independent_review":
        check(set(document) == {"schema_version", "evidence_type", "scope_id", "reviewed_commit", "reviewer_role", "reviewed_at", "findings", "findings_dispositioned", "test_evidence", "recommendation", "summary"}, "Independent review fields drifted or are incomplete")
        check(isinstance(document.get("scope_id"), str) and (TASK_ID.fullmatch(document["scope_id"]) is not None or FEATURE_ID.fullmatch(document["scope_id"]) is not None), "Independent review has an invalid scope_id")
        check(git_commit_exists(document.get("reviewed_commit", "")), "Independent review cites a missing commit")
        check(isinstance(document.get("reviewer_role"), str) and REVIEWER_ROLE.fullmatch(document["reviewer_role"]) is not None, "Independent review has an invalid reviewer role")
        check(isinstance(document.get("reviewed_at"), str) and UTC_TIMESTAMP.fullmatch(document["reviewed_at"]) is not None, "Independent review timestamp is invalid")
        check(document.get("recommendation") in {"PASS", "CHANGES_REQUIRED"}, "Independent review recommendation is invalid")
        check(isinstance(document.get("findings_dispositioned"), bool), "Independent review lacks findings disposition")
        findings = document.get("findings")
        check(isinstance(findings, list) and len(findings) <= MAX_REVIEW_FINDINGS, "Independent review findings must be a bounded list")
        for finding in findings:
            check(isinstance(finding, dict) and set(finding) == {"severity", "status", "summary"}, "Independent review finding fields are invalid")
            check(finding["severity"] in {"CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"} and finding["status"] in {"RESOLVED", "NOT_APPLICABLE", "OPEN"} and isinstance(finding["summary"], str) and finding["summary"].strip(), "Independent review finding is invalid")
        test_evidence = document.get("test_evidence")
        check(
            isinstance(test_evidence, list)
            and 1 <= len(test_evidence) <= MAX_REVIEW_TEST_EVIDENCE
            and len(test_evidence) == len(set(test_evidence))
            and all(type(item) is str and item.startswith(EVIDENCE_ROOTS["test_report"][0]) and item.endswith(".json") and ".." not in Path(item).parts for item in test_evidence),
            "Independent review must cite a bounded unique list of allowlisted test-report evidence paths",
        )
        check(isinstance(document.get("summary"), str) and document["summary"].strip(), "Independent review summary is missing")
        if document["recommendation"] == "PASS":
            check(document["findings_dispositioned"] is True and all(finding["status"] in {"RESOLVED", "NOT_APPLICABLE"} for finding in findings), "Passing review retains open findings")
    elif evidence_type == "device_report":
        check(set(document) == {"schema_version", "evidence_type", "feature_id", "commit", "surface", "device_class", "os_version", "app_artifact_hash", "tests", "result", "recorded_at"}, "Device report fields drifted or are incomplete")
        check(isinstance(document.get("feature_id"), str) and FEATURE_ID.fullmatch(document["feature_id"]) is not None, "Device report has an invalid feature_id")
        check(git_commit_exists(document.get("commit", "")), "Device report cites a missing commit")
        check(document.get("surface") in {"android_emulator", "android_physical", "ios_physical"}, "Device report surface is invalid")
        allowed_device_classes = {"emulator"} if document["surface"] == "android_emulator" else {"phone", "tablet"}
        check(type(document.get("device_class")) is str and document["device_class"] in allowed_device_classes, "Device report device_class does not match its surface")
        check(type(document.get("os_version")) is str and EVIDENCE_IDENTIFIER.fullmatch(document["os_version"]) is not None, "Device report os_version is invalid")
        check(type(document.get("app_artifact_hash")) is str and SHA256_ARTIFACT.fullmatch(document["app_artifact_hash"]) is not None, "Device report app_artifact_hash must be a canonical SHA-256 digest")
        check(
            isinstance(document.get("tests"), list)
            and 1 <= len(document["tests"]) <= MAX_DEVICE_TESTS
            and len(document["tests"]) == len(set(document["tests"]))
            and all(type(item) is str and EVIDENCE_IDENTIFIER.fullmatch(item) is not None for item in document["tests"]),
            "Device report tests must be a bounded unique list of allowlisted identifiers",
        )
        check(type(document.get("recorded_at")) is str and UTC_TIMESTAMP.fullmatch(document["recorded_at"]) is not None, "Device report timestamp is invalid")
        check(document.get("result") == "PASS", "Device report is not passing")
    elif evidence_type == "dataset_report":
        check(set(document) == {"schema_version", "evidence_type", "feature_id", "commit", "dataset_id", "dataset_version", "license_decision_id", "metrics", "thresholds", "result", "recorded_at"}, "Dataset report fields drifted or are incomplete")
        check(isinstance(document.get("feature_id"), str) and FEATURE_ID.fullmatch(document["feature_id"]) is not None, "Dataset report has an invalid feature_id")
        check(git_commit_exists(document.get("commit", "")), "Dataset report cites a missing commit")
        check(type(document.get("dataset_id")) is str and EVIDENCE_IDENTIFIER.fullmatch(document["dataset_id"]) is not None, "Dataset report dataset_id is invalid")
        check(type(document.get("dataset_version")) is str and EVIDENCE_IDENTIFIER.fullmatch(document["dataset_version"]) is not None, "Dataset report dataset_version is invalid")
        check(document.get("license_decision_id") == "TL-D-012", "Dataset report lacks the model/dataset licence decision")
        metrics = document.get("metrics")
        thresholds = document.get("thresholds")
        check(isinstance(metrics, dict) and 1 <= len(metrics) <= MAX_DATASET_METRICS and isinstance(thresholds, dict) and set(metrics) == set(thresholds), "Dataset report metrics and thresholds must have identical bounded non-empty keys")
        check(all(isinstance(key, str) and re.fullmatch(r"[a-z][a-z0-9_]{0,63}", key) is not None for key in metrics), "Dataset metric names are invalid")
        for key, measured in metrics.items():
            threshold = thresholds[key]
            check(is_finite_number(measured), f"Dataset metric {key} must be a finite number")
            check(isinstance(threshold, dict) and set(threshold) == {"operator", "value"}, f"Dataset threshold {key} schema is invalid")
            check(threshold["operator"] in {"gte", "lte"} and is_finite_number(threshold["value"]), f"Dataset threshold {key} is invalid")
            passed = measured >= threshold["value"] if threshold["operator"] == "gte" else measured <= threshold["value"]
            check(passed, f"Dataset metric {key} does not meet its threshold")
        check(type(document.get("recorded_at")) is str and UTC_TIMESTAMP.fullmatch(document["recorded_at"]) is not None, "Dataset report timestamp is invalid")
        check(document.get("result") == "PASS", "Dataset report is not passing")
    elif evidence_type == "human_approval_ledger":
        check(set(document) == {"schema_version", "evidence_type", "decision_id", "events"}, "Human approval ledger fields drifted or are incomplete")
        decision_id = document.get("decision_id")
        check(type(decision_id) is str and DECISION_ID.fullmatch(decision_id) is not None, "Human approval ledger has an invalid decision_id")
        events = document.get("events")
        check(isinstance(events, list) and 1 <= len(events) <= MAX_APPROVAL_EVENTS, "Human approval ledger requires a bounded non-empty event list")
        seen_events: dict[str, dict] = {}
        revoked_grants: set[str] = set()
        previous_event_date: date | None = None
        for index, event in enumerate(events, start=1):
            check(isinstance(event, dict), "Human approval event must be an object")
            event_type = event.get("event")
            event_letter = "G" if event_type == "GRANT" else "R" if event_type == "REVOKE" else None
            check(event_letter is not None, "Human approval event type is invalid")
            expected_event_id = f"{decision_id}-{event_letter}-{index:04d}"
            check(event.get("event_id") == expected_event_id and expected_event_id not in seen_events, "Human approval events must be unique and sequential")
            if event_type == "GRANT":
                check(set(event) == {"event_id", "event", "approved_by", "approval_date", "feature_id", "release", "artifact_commits", "jurisdiction", "scope", "limitations", "evidence_reviewed", "expires_or_review_on"}, "Human approval GRANT fields drifted or are incomplete")
                validate_human_actor_list(event.get("approved_by"), "Human approval GRANT approved_by")
                event_date = parse_nonfuture_date(event.get("approval_date"), "Human approval event date")
                check(type(event.get("feature_id")) is str and FEATURE_ID.fullmatch(event["feature_id"]) is not None, "Human approval GRANT feature is invalid")
                check(event.get("release") in {f"R{release}" for release in range(7)}, "Human approval GRANT release is invalid")
                commits = event.get("artifact_commits")
                check(isinstance(commits, list) and commits and all(type(item) is str and FULL_GIT_COMMIT.fullmatch(item) is not None and git_resolve_commit(item) == item for item in commits) and len(commits) == len(set(commits)), "Human approval GRANT artifacts must be unique full existing commits")
                for key in ("jurisdiction", "scope", "limitations"):
                    check(type(event.get(key)) is str and len(event[key].strip()) >= 3, f"Human approval GRANT {key} is incomplete")
                reviewed = event.get("evidence_reviewed")
                check(isinstance(reviewed, list) and 1 <= len(reviewed) <= MAX_APPROVAL_REVIEWED_EVIDENCE and all(type(item) is str and evidence_type_for_path(item) in {"test_report", "independent_review", "device_report", "dataset_report", "screenshot"} for item in reviewed) and len(reviewed) == len(set(reviewed)), "Human approval GRANT must cite a bounded unique list of typed evidence paths")
                validate_approval_event_expiry(event, require_current=False)
            else:
                check(set(event) == {"event_id", "event", "revoked_by", "approval_date", "revokes_event_id", "reason"}, "Human approval REVOKE fields drifted or are incomplete")
                validate_human_actor_list(event.get("revoked_by"), "Human approval REVOKE revoked_by")
                event_date = parse_nonfuture_date(event.get("approval_date"), "Human approval revocation date")
                target = event.get("revokes_event_id")
                check(type(target) is str and target in seen_events and seen_events[target]["event"] == "GRANT", "Human approval REVOKE must target a prior GRANT")
                check(target not in revoked_grants, "Human approval GRANT cannot be revoked more than once")
                check(event_date >= parse_nonfuture_date(seen_events[target]["approval_date"], "Human approval event date"), "Human approval revocation predates its GRANT")
                check(type(event.get("reason")) is str and len(event["reason"].strip()) >= 3, "Human approval REVOKE reason is incomplete")
                revoked_grants.add(target)
            check(previous_event_date is None or event_date >= previous_event_date, "Human approval event dates must be monotonic nondecreasing")
            previous_event_date = event_date
            seen_events[expected_event_id] = event
    else:
        fail(f"Unknown evidence type {evidence_type}")
    validate_sanitized_evidence(document, evidence_type)
    return document


def load_typed_evidence(relative: str, evidence_type: str) -> dict:
    _, object_id = validate_indexed_evidence(relative, evidence_type)
    document = load_json_blob(object_id, f"{evidence_type} stage-0 evidence")
    return validate_evidence_document(document, evidence_type)


def evidence_type_for_path(relative: object) -> str | None:
    if type(relative) is not str:
        return None
    normalized = relative.replace("\\", "/")
    candidate = Path(normalized)
    if candidate.is_absolute() or ".." in candidate.parts:
        return None
    matches = [
        evidence_type
        for evidence_type, roots in EVIDENCE_ROOTS.items()
        if any(normalized.startswith(root) for root in roots)
    ]
    if len(matches) != 1:
        return None
    evidence_type = matches[0]
    if evidence_type == "screenshot":
        return evidence_type if normalized.lower().endswith(".png") else None
    return evidence_type if normalized.lower().endswith(".json") else None


def validate_screenshot_evidence(relative: str) -> None:
    _, object_id = validate_indexed_evidence(relative, "screenshot")
    size = git_blob_size(object_id)
    check(33 <= size <= MAX_SCREENSHOT_BYTES, "Screenshot evidence size is outside the bounded PNG policy")
    data = read_git_blob(object_id)
    check(len(data) == size and data.startswith(b"\x89PNG\r\n\x1a\n"), "Screenshot evidence must be one canonical PNG blob")
    allowed_chunks = {b"IHDR", b"PLTE", b"IDAT", b"IEND", b"sRGB", b"gAMA", b"cHRM", b"pHYs", b"tRNS"}
    prohibited_metadata = {b"tEXt", b"zTXt", b"iTXt", b"eXIf"}
    offset = 8
    seen_ihdr = False
    seen_idat = False
    seen_iend = False
    seen_singletons: set[bytes] = set()
    idat_payload = bytearray()
    width: int | None = None
    height: int | None = None
    bit_depth: int | None = None
    color_type: int | None = None
    palette_entries = 0
    while offset < len(data):
        check(offset + 12 <= len(data), "Screenshot PNG chunk is truncated")
        chunk_length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_end = offset + 12 + chunk_length
        check(chunk_length <= MAX_SCREENSHOT_BYTES and chunk_end <= len(data), "Screenshot PNG chunk length is invalid")
        chunk_data = data[offset + 8 : offset + 8 + chunk_length]
        expected_crc = struct.unpack(">I", data[offset + 8 + chunk_length : chunk_end])[0]
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        check(expected_crc == actual_crc, "Screenshot PNG chunk CRC is invalid")
        check(chunk_type not in prohibited_metadata and chunk_type in allowed_chunks, "Screenshot PNG contains prohibited or unknown metadata")
        validate_binary_chunk_sanitized(chunk_data, "Screenshot PNG chunk")
        if not seen_ihdr:
            check(chunk_type == b"IHDR" and chunk_length == 13, "Screenshot PNG must begin with one IHDR chunk")
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk_data)
            valid_depths = {0: {1, 2, 4, 8, 16}, 2: {8, 16}, 3: {1, 2, 4, 8}, 4: {8, 16}, 6: {8, 16}}
            check(color_type in valid_depths and bit_depth in valid_depths[color_type] and compression == 0 and filtering == 0 and interlace == 0, "Screenshot PNG IHDR fields are invalid")
            check(1 <= width <= MAX_SCREENSHOT_DIMENSION and 1 <= height <= MAX_SCREENSHOT_DIMENSION and width * height <= MAX_SCREENSHOT_DIMENSION**2, "Screenshot evidence dimensions exceed the bounded policy")
            seen_ihdr = True
        elif chunk_type == b"IHDR":
            fail("Screenshot PNG contains duplicate IHDR")
        elif chunk_type == b"IDAT":
            check(not seen_iend, "Screenshot PNG IDAT chunks must precede IEND")
            seen_idat = True
            idat_payload.extend(chunk_data)
            check(len(idat_payload) <= MAX_SCREENSHOT_BYTES, "Screenshot PNG compressed image data exceeds the bounded policy")
        elif chunk_type != b"IEND":
            check(not seen_idat, "Screenshot PNG metadata and palette chunks must precede IDAT")
            check(chunk_type not in seen_singletons, "Screenshot PNG contains a duplicate singleton chunk")
            seen_singletons.add(chunk_type)
            if chunk_type == b"PLTE":
                check(color_type in {2, 3, 6} and 3 <= chunk_length <= 768 and chunk_length % 3 == 0, "Screenshot PNG PLTE fields are invalid")
                palette_entries = chunk_length // 3
                check(color_type != 3 or palette_entries <= 2 ** (bit_depth or 0), "Screenshot PNG palette exceeds its bit depth")
            elif chunk_type == b"tRNS":
                valid_transparency = (
                    (color_type == 0 and chunk_length == 2)
                    or (color_type == 2 and chunk_length == 6)
                    or (color_type == 3 and b"PLTE" in seen_singletons and 1 <= chunk_length <= palette_entries)
                )
                check(valid_transparency, "Screenshot PNG tRNS fields are invalid")
            elif chunk_type == b"sRGB":
                check(chunk_length == 1 and chunk_data[0] <= 3, "Screenshot PNG sRGB fields are invalid")
            elif chunk_type == b"gAMA":
                check(chunk_length == 4 and struct.unpack(">I", chunk_data)[0] > 0, "Screenshot PNG gAMA fields are invalid")
            elif chunk_type == b"cHRM":
                check(chunk_length == 32, "Screenshot PNG cHRM fields are invalid")
            elif chunk_type == b"pHYs":
                check(chunk_length == 9 and chunk_data[8] in {0, 1}, "Screenshot PNG pHYs fields are invalid")
        if chunk_type == b"IEND":
            check(
                chunk_length == 0
                and seen_idat
                and not seen_iend
                and (color_type != 3 or b"PLTE" in seen_singletons),
                "Screenshot PNG IEND is invalid",
            )
            seen_iend = True
            check(chunk_end == len(data), "Screenshot PNG has trailing bytes after IEND")
        offset = chunk_end
    check(seen_ihdr and seen_idat and seen_iend and offset == len(data), "Screenshot PNG is structurally incomplete")
    check(width is not None and height is not None and bit_depth is not None and color_type is not None, "Screenshot PNG IHDR state is incomplete")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    row_bytes = (width * channels * bit_depth + 7) // 8
    expected_size = height * (row_bytes + 1)
    check(1 <= expected_size <= MAX_SCREENSHOT_DECOMPRESSED_BYTES, "Screenshot PNG decompressed image exceeds the bounded policy")
    decompressor = zlib.decompressobj()
    try:
        decoded = decompressor.decompress(bytes(idat_payload), expected_size + 1)
        check(len(decoded) <= expected_size and not decompressor.unconsumed_tail, "Screenshot PNG decompressed image exceeds its exact expected size")
        decoded += decompressor.flush(expected_size + 1 - len(decoded))
    except zlib.error:
        fail("Screenshot PNG image data is not one valid bounded zlib stream")
    check(
        len(decoded) == expected_size
        and decompressor.eof
        and not decompressor.unused_data
        and not decompressor.unconsumed_tail,
        "Screenshot PNG image data length or zlib stream boundary is invalid",
    )
    validate_binary_chunk_sanitized(decoded, "Screenshot PNG decompressed image")
    stride = row_bytes + 1
    check(all(decoded[row * stride] in {0, 1, 2, 3, 4} for row in range(height)), "Screenshot PNG contains an invalid row filter byte")


def verified_task_projection(task: dict, evidence_blob_ids: dict[str, str]) -> dict:
    evidence = task.get("evidence", {})
    return {
        "task": {field: task.get(field) for field in VERIFIED_PROTECTED_FIELDS},
        "canonical_commit": list(evidence.get("commits", [])),
        "evidence_references": {
            key: list(evidence.get(key, []))
            for key in ("test_reports", "reviews", "screenshots")
        },
        "evidence_blob_ids": dict(sorted(evidence_blob_ids.items())),
    }


def projection_digest(projection: dict) -> str:
    canonical = json.dumps(projection, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def task_evidence_blob_ids_from_index(task: dict) -> dict[str, str]:
    paths = [
        relative
        for key in ("test_reports", "reviews", "screenshots")
        for relative in task["evidence"][key]
    ]
    return {
        relative: validate_evidence_git_entries(git_index_entries(relative), relative)
        for relative in paths
    }


def task_evidence_blob_ids_at_commit(task: dict, checkpoint: str) -> dict[str, str]:
    blob_ids: dict[str, str] = {}
    for key in ("test_reports", "reviews", "screenshots"):
        for relative in task["evidence"][key]:
            entry = git_blob_entry_at_commit(checkpoint, relative)
            check(entry is not None, "Verification checkpoint omits referenced evidence")
            blob_ids[relative] = entry[1]
    return blob_ids


def task_verification_metadata_paths(task: dict) -> set[str]:
    return {
        "docs/program/TASK_GRAPH.yaml",
        "docs/program/FEATURE_REGISTRY.yaml",
        "docs/program/PROJECT_STATE.md",
        "docs/program/TRACEABILITY_MATRIX.md",
        *(
            relative
            for key in ("test_reports", "reviews", "screenshots")
            for relative in task["evidence"][key]
        ),
    }


def task_projection_at_commit(task: dict, commit: str) -> dict:
    return verified_task_projection(task, task_evidence_blob_ids_at_commit(task, commit))


def validate_index_projection_matches_commit(current_task: dict, historical_task: dict, commit: str, label: str) -> None:
    current = verified_task_projection(current_task, task_evidence_blob_ids_from_index(current_task))
    historical = task_projection_at_commit(historical_task, commit)
    check(
        projection_digest(current) == projection_digest(historical),
        f"{label} has canonical, scope, evidence-reference, or evidence-blob drift",
    )


def validate_retained_projection_history(task_id: str, checkpoint: str, head: str, expected: dict) -> None:
    for descendant in [checkpoint, *git_ancestry_path(checkpoint, head)]:
        descendant_task = task_at_commit(descendant, task_id)
        check(descendant_task is not None and descendant_task.get("status") == "VERIFIED", f"Retained VERIFIED task {task_id} has an unrecorded lifecycle transition")
        descendant_projection = task_projection_at_commit(descendant_task, descendant)
        check(
            projection_digest(descendant_projection) == projection_digest(expected),
            f"Retained VERIFIED task {task_id} protected projection drifted in history",
        )


def validate_committed_reopen(task_id: str, verified_parent: str, reopen_commit: str) -> None:
    parents = git_parent_commits(reopen_commit)
    check(parents == [verified_parent], f"Reopen checkpoint for {task_id} must directly descend one VERIFIED parent")
    previous_task = task_at_commit(verified_parent, task_id)
    reopened_task = task_at_commit(reopen_commit, task_id)
    check(
        previous_task is not None
        and previous_task.get("status") == "VERIFIED"
        and reopened_task is not None
        and reopened_task.get("status") == "CHANGES_REQUIRED",
        f"Reopen checkpoint for {task_id} must be an explicit VERIFIED-to-CHANGES_REQUIRED transition",
    )
    check(bool(reopened_task.get("blockers")), f"Reopen checkpoint for {task_id} must record why verification was reopened")
    changes = set(git_commit_paths_between(verified_parent, reopen_commit))
    check(
        bool(changes)
        and "docs/program/TASK_GRAPH.yaml" in changes
        and changes <= task_verification_metadata_paths(previous_task),
        f"Reopen checkpoint for {task_id} must change verification metadata only",
    )
    previous_projection = task_projection_at_commit(previous_task, verified_parent)
    reopened_projection = task_projection_at_commit(reopened_task, reopen_commit)
    check(
        projection_digest(previous_projection) == projection_digest(reopened_projection),
        f"Reopen checkpoint for {task_id} changed protected scope or evidence",
    )
    canonical_references = previous_task.get("evidence", {}).get("commits", [])
    check(len(canonical_references) == 1, f"Verified parent for {task_id} has no canonical implementation commit")
    canonical = git_resolve_commit(canonical_references[0])
    check(canonical is not None and git_is_ancestor(canonical, verified_parent), f"Verified parent for {task_id} has invalid canonical ancestry")
    checkpoint, checkpoint_task = find_verification_checkpoint(task_id, canonical, verified_parent)
    expected_projection = task_projection_at_commit(checkpoint_task, checkpoint)
    validate_retained_projection_history(task_id, checkpoint, verified_parent, expected_projection)


def validate_task_reopen_lifecycle(task: dict, head: str, head_task: dict) -> None:
    task_id = task["id"]
    if head_task.get("status") == "VERIFIED":
        if task.get("status") == "VERIFIED":
            return
        check(task.get("status") == "CHANGES_REQUIRED", f"Verified task {task_id} must be explicitly reopened as CHANGES_REQUIRED")
        check(bool(task.get("blockers")), f"Reopened task {task_id} must record why verification was reopened")
        check(not git_unmerged_paths(), f"Reopened task {task_id} cannot use a conflicted index")
        check(not git_worktree_changes(), f"Reopened task {task_id} requires staged bytes matching the working tree")
        staged_changes = git_staged_changes(head)
        check(
            bool(staged_changes)
            and "docs/program/TASK_GRAPH.yaml" in staged_changes
            and staged_changes <= task_verification_metadata_paths(head_task),
            f"Reopened task {task_id} must stage verification metadata only",
        )
        validate_index_projection_matches_commit(task, head_task, head, f"Reopened task {task_id}")
        return
    if head_task.get("status") == "VERIFIED":
        return

    history = git_path_history("docs/program/TASK_GRAPH.yaml", head)
    latest_verified_index: int | None = None
    historical_tasks: list[dict | None] = []
    for index, commit in enumerate(history):
        historical = task_at_commit(commit, task_id)
        historical_tasks.append(historical)
        if historical is not None and historical.get("status") == "VERIFIED":
            latest_verified_index = index
    if latest_verified_index is None:
        return
    for reopen_commit, historical in zip(
        history[latest_verified_index + 1 :],
        historical_tasks[latest_verified_index + 1 :],
        strict=True,
    ):
        if historical is None or historical.get("status") == "VERIFIED":
            continue
        parents = git_parent_commits(reopen_commit)
        check(len(parents) == 1, f"Reopen checkpoint for {task_id} must have one parent")
        validate_committed_reopen(task_id, parents[0], reopen_commit)
        return
    fail(f"Verified task {task_id} lost verification without an explicit reopen checkpoint")


def find_verification_checkpoint(task_id: str, canonical: str, head: str) -> tuple[str, dict]:
    candidates: list[tuple[str, dict]] = []
    for commit in git_ancestry_path(canonical, head):
        parents = git_parent_commits(commit)
        if parents != [canonical]:
            continue
        historical_task = task_at_commit(commit, task_id)
        if historical_task is not None and historical_task.get("status") == "VERIFIED":
            candidates.append((commit, historical_task))
    check(len(candidates) == 1, f"Retained VERIFIED task {task_id} lacks one direct metadata checkpoint")
    return candidates[0]


def validate_task_verification_lifecycle(task: dict, reference: str) -> None:
    task_id = task["id"]
    canonical = git_resolve_commit(reference)
    head = git_head_commit()
    check(canonical is not None and head is not None, f"Verified task {task_id} has unresolved Git lineage")
    head_task = task_at_commit(head, task_id)
    if head_task is None or head_task.get("status") != "VERIFIED":
        validate_staged_verification_candidate(reference)
        canonical_task = task_at_commit(canonical, task_id)
        check(canonical_task is not None and canonical_task.get("status") != "VERIFIED", f"Canonical implementation commit for {task_id} was already VERIFIED")
        staged_changes = git_staged_changes(head)
        allowed_metadata = task_verification_metadata_paths(task)
        check(staged_changes <= allowed_metadata, f"New VERIFIED transition for {task_id} stages unrelated verification metadata")
        return

    check(not git_unmerged_paths(), f"Retained VERIFIED task {task_id} cannot use a conflicted index")
    check(not git_worktree_changes(), f"Retained VERIFIED task {task_id} requires a clean working tree")
    validate_index_projection_matches_commit(task, head_task, head, f"Retained VERIFIED task {task_id}")
    check(git_is_ancestor(canonical, head), f"Retained VERIFIED task {task_id} canonical commit is not an ancestor of HEAD")
    canonical_task = task_at_commit(canonical, task_id)
    check(canonical_task is not None and canonical_task.get("status") != "VERIFIED", f"Canonical implementation commit for {task_id} was already VERIFIED")
    checkpoint, checkpoint_task = find_verification_checkpoint(task_id, canonical, head)
    parents = git_parent_commits(checkpoint)
    check(parents == [canonical], f"Verification checkpoint for {task_id} must directly descend its canonical implementation commit")
    checkpoint_changes = git_commit_paths_between(canonical, checkpoint)
    check(bool(checkpoint_changes) and "docs/program/TASK_GRAPH.yaml" in checkpoint_changes, f"Verification checkpoint for {task_id} has no task-state transition")
    allowed_metadata = task_verification_metadata_paths(checkpoint_task)
    check(set(checkpoint_changes) <= allowed_metadata, f"Verification checkpoint for {task_id} changes unrelated or non-metadata paths")
    historical_blob_ids = task_evidence_blob_ids_at_commit(checkpoint_task, checkpoint)
    current_blob_ids = task_evidence_blob_ids_from_index(task)
    historical_projection = verified_task_projection(checkpoint_task, historical_blob_ids)
    current_projection = verified_task_projection(task, current_blob_ids)
    check(projection_digest(current_projection) == projection_digest(historical_projection), f"Retained VERIFIED task {task_id} has canonical, scope, evidence-reference, or evidence-blob drift")
    validate_retained_projection_history(task_id, checkpoint, head, historical_projection)


def looks_like_named_human(value: str) -> bool:
    normalized = value.strip()
    if re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", normalized):
        return True
    if re.fullmatch(r"[\w.'-]+(?:\s+[\w.'-]+)+", normalized, re.UNICODE) is None:
        return False
    role_words = {
        "owner", "reviewer", "qualified", "named", "authorised", "authorized", "accountable",
        "product", "legal", "privacy", "security", "operations", "store", "brand", "domain",
        "evidence", "nutrition", "exercise", "sesotho", "data", "business", "platform",
    }
    tokens = {token.casefold().strip(".'-") for token in normalized.split()}
    return not bool(tokens & role_words)


def parse_feature_evidence(entries: list[str], feature_id: str) -> dict[str, list[str]]:
    parsed = {kind: [] for kind in FEATURE_EVIDENCE_TYPES}
    check(len(entries) == len(set(entries)), f"Feature {feature_id} evidence entries must be unique")
    for entry in entries:
        kind, separator, reference = entry.partition(":")
        check(separator == ":" and kind in FEATURE_EVIDENCE_TYPES and reference.strip(), f"Malformed evidence in {feature_id}: {entry}")
        parsed[kind].append(reference)
    return parsed


def add_evidence_reference(references: dict[str, str], relative: str, evidence_type: str) -> None:
    inferred = evidence_type_for_path(relative)
    check(inferred == evidence_type, f"Evidence reference {relative} does not match its typed root")
    prior = references.get(relative)
    check(prior is None or prior == evidence_type, f"Evidence path {relative} is referenced with conflicting types")
    references[relative] = evidence_type


def collect_referenced_evidence(graph: dict, registry: dict, approvals: dict[str, dict]) -> dict[str, str]:
    references: dict[str, str] = {}
    for task in graph["tasks"]:
        for relative in task["evidence"]["test_reports"]:
            add_evidence_reference(references, relative, "test_report")
        for relative in task["evidence"]["reviews"]:
            add_evidence_reference(references, relative, "independent_review")
        for relative in task["evidence"]["screenshots"]:
            add_evidence_reference(references, relative, "screenshot")
        check(not any(type(note) is str and note.replace("\\", "/").startswith(EVIDENCE_PREFIX) for note in task["evidence"]["notes"]), f"{task['id']} evidence notes cannot substitute for typed evidence references")
    feature_type_map = {
        "report": "test_report",
        "review": "independent_review",
        "device": "device_report",
        "dataset": "dataset_report",
    }
    for feature in registry["features"]:
        parsed = parse_feature_evidence(feature["evidence"], feature["id"])
        for kind, evidence_type in feature_type_map.items():
            for relative in parsed[kind]:
                add_evidence_reference(references, relative, evidence_type)
    for metadata in approvals.values():
        ledger_path = metadata.get("ledger_path")
        ledger = metadata.get("ledger")
        if ledger_path is None:
            continue
        add_evidence_reference(references, ledger_path, "human_approval_ledger")
        check(isinstance(ledger, dict), "Approved decision has no typed approval ledger")
        for event in ledger["events"]:
            if event["event"] != "GRANT":
                continue
            for relative in event["evidence_reviewed"]:
                evidence_type = evidence_type_for_path(relative)
                check(evidence_type in {"test_report", "independent_review", "device_report", "dataset_report", "screenshot"}, "Human approval cites unsupported reviewed evidence")
                add_evidence_reference(references, relative, evidence_type)
    return references


def validate_evidence_inventory(graph: dict, registry: dict, approvals: dict[str, dict]) -> None:
    references = collect_referenced_evidence(graph, registry, approvals)
    grouped: dict[str, list[tuple[str, str, int, str]]] = {}
    for entry in git_index_entries_under(EVIDENCE_PREFIX):
        grouped.setdefault(entry[3], []).append(entry)
    indexed_paths = set(grouped)
    referenced_paths = set(references)
    unreferenced = sorted(indexed_paths - referenced_paths)
    missing = sorted(referenced_paths - indexed_paths)
    check(not unreferenced, f"Tracked/staged evidence file is unreferenced: {unreferenced[0] if unreferenced else ''}")
    check(not missing, f"Referenced evidence file is not staged/tracked: {missing[0] if missing else ''}")
    for relative, entries in grouped.items():
        validate_evidence_git_entries(entries, relative)
        evidence_type = references[relative]
        if evidence_type == "screenshot":
            validate_screenshot_evidence(relative)
        else:
            load_typed_evidence(relative, evidence_type)


def is_shared_path(pattern: str) -> bool:
    normalized = pattern.replace("\\", "/").lower()
    return (
        normalized.endswith(".lock")
        or any(marker in normalized for marker in SHARED_PATH_MARKERS)
    )


def validate_required_files() -> dict[str, str]:
    missing = [relative for relative in REQUIRED_FILES if not (ROOT / relative).is_file()]
    check(not missing, f"Missing required files: {missing}")
    texts = {relative: read_text(relative) for relative in REQUIRED_FILES}
    empty = [relative for relative, value in texts.items() if not value.strip()]
    check(not empty, f"Empty required files: {empty}")
    check(len(texts["AGENTS.md"].splitlines()) <= 200, "AGENTS.md exceeds 200 lines")
    for relative, value in texts.items():
        check(not any(line.rstrip("\r\n").endswith((" ", "\t")) for line in value.splitlines(keepends=True)), f"Trailing whitespace in {relative}")
        check(not re.search(r"^(?:<<<<<<<|=======|>>>>>>>)", value, re.MULTILINE), f"Merge marker in {relative}")
    return texts


def validate_tasks(graph: dict, required_texts: dict[str, str]) -> tuple[list[dict], dict[str, set[str]]]:
    check(set(graph) == {"schema_version", "release", "tasks"}, "TASK_GRAPH top-level fields drifted")
    check(is_exact_int(graph.get("schema_version")) and graph["schema_version"] == 2, "TASK_GRAPH schema_version must be integer 2")
    check(graph.get("release") == "R0", "TASK_GRAPH release must be R0")
    tasks = graph.get("tasks")
    check(isinstance(tasks, list) and 1 <= len(tasks) <= 10, "R0 task graph must contain one to ten tasks")

    by_id: dict[str, dict] = {}
    for task in tasks:
        check(isinstance(task, dict), "Each task must be an object")
        check(set(task) == TASK_KEYS, f"{task.get('id', '<unknown>')} task fields drifted from the exact schema")
        task_id = task["id"]
        check(isinstance(task_id, str) and TASK_ID.fullmatch(task_id) is not None, f"Invalid R0 task ID: {task_id}")
        check(task_id not in by_id, f"Duplicate task ID: {task_id}")
        by_id[task_id] = task

    check(set(by_id) == set(R0_TASK_IDS), "R0 task IDs drifted from the exact TL-R0-001 through TL-R0-010 baseline")

    lifecycle_head = git_head_commit()
    check(lifecycle_head is not None, "Cannot resolve HEAD while validating task lifecycle")
    historical_graph = load_json_at_commit(lifecycle_head, "docs/program/TASK_GRAPH.yaml")
    historical_tasks = {} if historical_graph is None else {
        historical["id"]: historical
        for historical in historical_graph.get("tasks", [])
        if isinstance(historical, dict) and type(historical.get("id")) is str
    }

    memo: dict[str, set[str]] = {}
    for task_id in by_id:
        ancestors_for(task_id, by_id, memo, set())

    for task in tasks:
        task_id = task["id"]
        check(task["release"] == "R0", f"{task_id} must belong to R0")
        check(task["status"] in TASK_STATES, f"Invalid task state in {task_id}")
        check(isinstance(task["owner_agent"], str) and task["owner_agent"].strip(), f"{task_id} has no owner")
        for key in ("dependencies", "owned_paths", "integration_owned_paths", "forbidden_paths", "inputs", "acceptance_criteria", "required_tests", "required_reviewers", "blockers"):
            require_string_list(task[key], f"{task_id}.{key}", nonempty=key in {"owned_paths", "forbidden_paths", "inputs", "acceptance_criteria", "required_tests", "required_reviewers"})
        check(task["owner_agent"] not in task["required_reviewers"], f"{task_id} owner cannot review its own task")
        check(len(task["required_reviewers"]) == len(set(task["required_reviewers"])), f"{task_id} has duplicate reviewers")
        check(isinstance(task["next_action"], str) and task["next_action"].strip(), f"{task_id} has no next action")
        check(isinstance(task["evidence"], dict) and set(task["evidence"]) == EVIDENCE_KEYS, f"{task_id} evidence must use {sorted(EVIDENCE_KEYS)}")
        for key in EVIDENCE_KEYS:
            values = require_string_list(task["evidence"][key], f"{task_id}.evidence.{key}")
            check(len(values) <= MAX_TASK_EVIDENCE_ENTRIES, f"{task_id}.evidence.{key} exceeds the bounded evidence-list policy")
            check(len(values) == len(set(values)), f"{task_id}.evidence.{key} must contain unique entries")
        if task_id in historical_tasks:
            validate_task_reopen_lifecycle(task, lifecycle_head, historical_tasks[task_id])
        check(len(task["dependencies"]) == len(set(task["dependencies"])), f"{task_id} has duplicate dependencies")
        if task["status"] in ACTIVE_TASK_STATES:
            incomplete = [dependency for dependency in task["dependencies"] if by_id[dependency]["status"] != "VERIFIED"]
            check(not incomplete, f"Active task {task_id} has unverified dependencies: {incomplete}")
        if task["status"] == "BLOCKED":
            check(bool(task["blockers"]), f"Blocked task {task_id} must name a blocker")
        if task["status"] in {"INTEGRATED", "VERIFIED"}:
            check(bool(task["evidence"]["commits"]), f"{task['status']} task {task_id} needs commit evidence")
            invalid_commits = [reference for reference in task["evidence"]["commits"] if not git_commit_exists(reference)]
            check(not invalid_commits, f"{task['status']} task {task_id} cites a missing commit")
        if task["status"] == "VERIFIED":
            check(not task["blockers"], f"Verified task {task_id} cannot retain blockers")
            check(len(task["evidence"]["commits"]) == 1, f"Verified task {task_id} must name one canonical verification commit")
            verification_commit = task["evidence"]["commits"][0]
            validate_verification_candidate(verification_commit, task)
            claimed_paths = task["owned_paths"] + task["integration_owned_paths"]
            changed_paths = git_commit_paths(verification_commit)
            check(bool(changed_paths), f"Verified task {task_id} commit has no attributable changes")
            check(all(any(pattern_covers(pattern, changed) for pattern in claimed_paths) for changed in changed_paths), f"Verified task {task_id} commit changes a path outside its ownership")
            check(all(not any(pattern_covers(pattern, changed) for pattern in task["forbidden_paths"]) for changed in changed_paths), f"Verified task {task_id} commit changes a forbidden path")
            check(bool(task["evidence"]["test_reports"]), f"Verified task {task_id} needs test evidence")
            check(bool(task["evidence"]["reviews"]), f"Verified task {task_id} needs independent review evidence")
            for evidence_key, directory in TASK_EVIDENCE_DIRECTORIES.items():
                expected_route = f"docs/program/evidence/{directory}/{task_id}/**"
                check(expected_route in task["integration_owned_paths"], f"{task_id} lacks its exact integration-owned {evidence_key} staging route")
                check(all(pattern_covers(expected_route, relative) for relative in task["evidence"][evidence_key]), f"Verified task {task_id} has {evidence_key} outside its integration staging route")
            reports = [load_typed_evidence(relative, "test_report") for relative in task["evidence"]["test_reports"]]
            check(all(report["task_id"] == task_id and report["commit"] == verification_commit for report in reports), f"Verified task {task_id} has mismatched or stale test evidence")
            recorded_commands = [normalize_command(command["command"]) for report in reports for command in report["commands"]]
            required_commands = [normalize_command(command) for command in task["required_tests"]]
            check(recorded_commands == required_commands, f"Verified task {task_id} test reports must preserve the exact required command order and multiplicity")
            report_by_path = dict(zip(task["evidence"]["test_reports"], reports, strict=True))
            reviews = [load_typed_evidence(relative, "independent_review") for relative in task["evidence"]["reviews"]]
            reviewer_roles = {review["reviewer_role"] for review in reviews}
            check(set(task["required_reviewers"]) <= reviewer_roles, f"Verified task {task_id} lacks a required independent review")
            for review in reviews:
                check(review["scope_id"] == task_id, f"Verified task {task_id} has a review for another scope")
                check(review["reviewed_commit"] == verification_commit, f"Verified task {task_id} review cites another commit")
                check(review["reviewer_role"] != task["owner_agent"], f"Verified task {task_id} has implementer self-review evidence")
                check(review["recommendation"] == "PASS" and review["findings_dispositioned"] is True, f"Verified task {task_id} has a non-passing review")
                check(set(review["test_evidence"]) <= set(task["evidence"]["test_reports"]), f"Verified task {task_id} review cites unrecorded tests")
                check(all(report_by_path[reference]["task_id"] == task_id and report_by_path[reference]["commit"] == review["reviewed_commit"] for reference in review["test_evidence"]), f"Verified task {task_id} review cites stale or unrelated tests")
            security_reviewed_reports = {
                reference
                for review in reviews
                if review["reviewer_role"] == "security_privacy_reviewer"
                for reference in review["test_evidence"]
            }
            if "security_privacy_reviewer" in task["required_reviewers"]:
                check(security_reviewed_reports == set(task["evidence"]["test_reports"]), f"Verified task {task_id} security review must cover every recorded task report")
            for relative in task["evidence"]["screenshots"]:
                resolve_indexed_evidence(relative, "screenshot")
        for owned in task["owned_paths"]:
            for forbidden in task["forbidden_paths"]:
                check(not patterns_overlap(owned, forbidden), f"{task_id} owns and forbids overlapping paths: {owned} / {forbidden}")
        if task["owner_agent"] != "integration_release_lead":
            shared = [path for path in task["owned_paths"] if is_shared_path(path)]
            check(not shared, f"{task_id} assigns shared paths outside integration ownership: {shared}")
        if task["integration_owned_paths"] and task["owner_agent"] != "integration_release_lead":
            check("integration_release_lead" in task["required_reviewers"], f"{task_id} has integration-owned paths without integration review")
        for evidence_key, directory in TASK_EVIDENCE_DIRECTORIES.items():
            expected_route = f"docs/program/evidence/{directory}/{task_id}/**"
            check(expected_route in task["integration_owned_paths"], f"{task_id} lacks its exact integration-owned {evidence_key} staging route")

    control_task = by_id.get("TL-R0-001")
    contract_task = by_id.get("TL-R0-002")
    platform_task = by_id.get("TL-R0-003")
    api_task = by_id.get("TL-R0-005")
    mobile_task = by_id.get("TL-R0-007")
    heartbeat_task = by_id.get("TL-R0-008")
    quality_task = by_id.get("TL-R0-009")
    check(control_task is not None and ".gitignore" in control_task["owned_paths"], "TL-R0-001 must own its staged .gitignore change")
    check(contract_task is not None and any("assert_expected_red.ps1" in command for command in contract_task["required_tests"]), "TL-R0-002 must retain an expected-red harness")
    check(platform_task is not None and sum("check_resource_budget.ps1" in command for command in platform_task["required_tests"]) >= 2, "TL-R0-003 must gate installation before and after with the resource policy")
    check(mobile_task is not None and "TL-R0-003" in memo["TL-R0-007"], "TL-R0-007 must follow resource-phase activation")
    check(sum("check_resource_budget.ps1" in command for command in mobile_task["required_tests"]) >= 2, "TL-R0-007 must run the resource policy before and after")
    check(not any(command.lstrip().lower().startswith(("flutter ", "dart ")) for command in mobile_task["required_tests"]), "TL-R0-007 Flutter commands must use package-root wrappers")
    for wrapper in ("scripts/mobile/run_quality.ps1", "scripts/mobile/verify_web_surface.ps1"):
        check(any(wrapper in command for command in mobile_task["required_tests"]), f"TL-R0-007 is missing required wrapper {wrapper}")
    check(heartbeat_task is not None and sum("check_resource_budget.ps1" in command for command in heartbeat_task["required_tests"]) >= 2, "TL-R0-008 must resource-gate Android installation/build before and after")
    check(not any(command.lstrip().lower().startswith(("flutter ", "dart ")) for command in heartbeat_task["required_tests"]), "TL-R0-008 Flutter commands must use package-root wrappers")
    for wrapper in ("scripts/mobile/build_android.ps1", "scripts/mobile/verify_android_surface.ps1"):
        check(any(wrapper in command for command in heartbeat_task["required_tests"]), f"TL-R0-008 is missing required wrapper {wrapper}")
    check(any("Android" in criterion and "browser" in criterion for criterion in heartbeat_task["acceptance_criteria"]), "TL-R0-008 must retain mandatory Android evidence beyond browser proof")
    check(any("same-origin" in criterion for criterion in contract_task["acceptance_criteria"]), "TL-R0-002 must freeze the same-origin web contract")
    check(any("adb reverse" in criterion and "release" in criterion for criterion in contract_task["acceptance_criteria"]), "TL-R0-002 must freeze Android debug transport without widening host loopback")
    check(any("adb reverse" in criterion and "host loopback" in criterion for criterion in heartbeat_task["acceptance_criteria"]), "TL-R0-008 must retain bounded Android-to-host transport")
    check(api_task is not None and "TL-R0-007" not in memo["TL-R0-005"], "TL-R0-005 cannot depend on the parallel real Flutter build")
    check(any("deterministic fixture" in criterion and "TL-R0-008" in criterion for criterion in api_task["acceptance_criteria"]), "TL-R0-005 must fixture-test its static mount and defer real assets to TL-R0-008")
    check(quality_task is not None and {"TL-R0-002", "TL-R0-003"} <= set(quality_task["dependencies"]), "TL-R0-009 must follow the early contract/platform gates")
    check("TL-R0-008" not in memo["TL-R0-009"], "TL-R0-009 cannot depend on the final heartbeat integration")

    for index, first in enumerate(tasks):
        first_claims = first["owned_paths"] + first["integration_owned_paths"]
        for second in tasks[index + 1 :]:
            if second["id"] in memo[first["id"]] or first["id"] in memo[second["id"]]:
                continue
            second_claims = second["owned_paths"] + second["integration_owned_paths"]
            for first_path in first_claims:
                for second_path in second_claims:
                    check(
                        not patterns_overlap(first_path, second_path),
                        f"Parallel path collision: {first['id']}:{first_path} / {second['id']}:{second_path}",
                    )

    for task in tasks:
        available_owners = {task["id"], *memo[task["id"]]}
        available_patterns: list[str] = []
        for owner_id in available_owners:
            available_patterns.extend(by_id[owner_id]["owned_paths"])
            available_patterns.extend(by_id[owner_id]["integration_owned_paths"])
        for command in task["required_tests"]:
            for script in SCRIPT_REFERENCE.findall(command):
                script = script.replace("\\", "/")
                exists = (ROOT / script).is_file()
                if task["status"] in {"IN_REVIEW", "CHANGES_REQUIRED", "INTEGRATED", "VERIFIED"}:
                    check(exists, f"{task['id']} active review test script is missing: {script}")
                available = exists or any(pattern_covers(pattern, script) for pattern in available_patterns)
                check(available, f"{task['id']} test references an unavailable script: {script}")

    graph_text = required_texts["docs/program/TASK_GRAPH.yaml"]
    inactive_docs = [relative for relative in REQUIRED_FILES if relative.startswith("docs/") and relative not in graph_text]
    check(not inactive_docs, f"Required control documents are not linked by an active task: {inactive_docs}")
    for task_id, task in by_id.items():
        protected_spec = {field: task.get(field) for field in VERIFIED_PROTECTED_FIELDS}
        check(
            projection_digest(protected_spec) == R0_TASK_SPEC_SHA256[task_id],
            f"R0 immutable task specification drifted for {task_id}",
        )
    return tasks, memo


def terminal_feature_task_ids(linked_tasks: list[str], tasks_by_id: dict[str, dict]) -> set[str]:
    linked = set(linked_tasks)
    depended_on: set[str] = set()
    memo: dict[str, set[str]] = {}
    for task_id in linked_tasks:
        depended_on.update(ancestors_for(task_id, tasks_by_id, memo, set()) & linked)
    return linked - depended_on


def resolved_commit_set(references: list[str] | set[str]) -> set[str] | None:
    resolved = [git_resolve_commit(reference) for reference in references]
    if any(reference is None for reference in resolved):
        return None
    return set(resolved)


def parse_approval_reference(reference: str, feature_id: str) -> tuple[str, str]:
    decision_id, separator, event_id = reference.partition("/")
    check(separator == "/" and DECISION_ID.fullmatch(decision_id) is not None and re.fullmatch(rf"{re.escape(decision_id)}-G-\d{{4}}", event_id) is not None, f"Feature {feature_id} has a malformed approval event reference")
    return decision_id, event_id


def active_approval_grants(ledger: dict) -> dict[str, dict]:
    revoked = {
        event["revokes_event_id"]
        for event in ledger["events"]
        if event["event"] == "REVOKE"
    }
    return {
        event["event_id"]: event
        for event in ledger["events"]
        if event["event"] == "GRANT"
        and event["event_id"] not in revoked
        and validate_approval_event_expiry(event, require_current=False)
    }


def validate_approval_ledger_extension(previous: dict, current: dict) -> None:
    for key in ("schema_version", "evidence_type", "decision_id"):
        check(exact_value_equal(current.get(key), previous.get(key)), "Human approval ledger identity is immutable")
    previous_events = previous.get("events")
    current_events = current.get("events")
    check(isinstance(previous_events, list) and isinstance(current_events, list) and len(current_events) >= len(previous_events), "Human approval ledger events are append-only")
    check(exact_value_equal(current_events[: len(previous_events)], previous_events), "Human approval ledger prior events cannot be edited, removed, or reordered")


def approval_ledger_actors(ledger: dict) -> list[str]:
    actors: list[str] = []
    seen: set[str] = set()
    for event in ledger["events"]:
        field = "approved_by" if event["event"] == "GRANT" else "revoked_by"
        for identity in event[field]:
            normalized = identity.casefold()
            if normalized not in seen:
                seen.add(normalized)
                actors.append(identity)
    check(len(actors) <= MAX_APPROVAL_LEDGER_ACTORS, "Human approval ledger actor union exceeds the bounded policy")
    return actors


def validate_approval_ledger_history(relative: str, current: dict) -> None:
    head = git_head_commit()
    check(head is not None, "Cannot resolve HEAD for approval history")
    previous: dict | None = None
    for commit in git_path_history(relative, head):
        entry = git_blob_entry_at_commit(commit, relative)
        check(entry is not None, "Human approval ledger history contains a deletion or rename")
        historical = validate_evidence_document(load_json_blob(entry[1], "Historical human approval ledger"), "human_approval_ledger")
        if previous is not None:
            validate_approval_ledger_extension(previous, historical)
        previous = historical
    if previous is not None:
        validate_approval_ledger_extension(previous, current)


def validate_approval_for_feature(
    metadata: dict,
    feature: dict,
    current_commits: set[str],
    decision_id: str,
    event_id: str,
) -> None:
    check(metadata["state"] == "APPROVED" and isinstance(metadata.get("ledger"), dict), f"{feature['id']} cites an unapproved decision")
    grant = metadata["active_grants"].get(event_id)
    check(grant is not None, f"{feature['id']} cites an inactive, expired, or revoked approval event")
    check(grant["feature_id"] == feature["id"], f"{decision_id} approval event is scoped to another feature")
    check(grant["release"] == feature["release"], f"{decision_id} approval event release does not match {feature['id']}")
    approved_commits = resolved_commit_set(grant["artifact_commits"])
    resolved_current = resolved_commit_set(current_commits)
    check(approved_commits is not None and resolved_current is not None and approved_commits == resolved_current, f"{decision_id} approval event artifacts do not exactly match the current feature artifact commits")
    validate_approval_event_expiry(grant, require_current=True)


def validate_features(registry: dict, tasks_by_id: dict[str, dict], approvals: dict[str, dict]) -> list[dict]:
    check(set(registry) == {"schema_version", "allowed_states", "features", "providers"}, "FEATURE_REGISTRY top-level fields drifted")
    check(is_exact_int(registry.get("schema_version")) and registry["schema_version"] == 2, "FEATURE_REGISTRY schema_version must be integer 2")
    allowed = registry.get("allowed_states")
    check(isinstance(allowed, list) and set(allowed) == FEATURE_STATES, "FEATURE_REGISTRY allowed states drifted")
    features = registry.get("features")
    check(isinstance(features, list) and features, "FEATURE_REGISTRY must have features")
    baseline_feature_ids = [feature.get("id") for feature in features if isinstance(feature, dict)]
    check(
        len(baseline_feature_ids) == len(features)
        and len(baseline_feature_ids) == len(set(baseline_feature_ids))
        and set(baseline_feature_ids) == set(R0_FEATURE_SEMANTICS),
        "Feature IDs drifted from the exact R0-to-R6 semantic baseline",
    )
    for feature in features:
        feature_id = feature["id"]
        expected_release, expected_name, expected_gates, expected_task_ids = R0_FEATURE_SEMANTICS[feature_id]
        check(
            feature.get("release") == expected_release
            and feature.get("name") == expected_name
            and isinstance(feature.get("human_gates"), list)
            and tuple(feature["human_gates"]) == expected_gates
            and isinstance(feature.get("task_ids"), list)
            and tuple(feature["task_ids"]) == expected_task_ids,
            f"Immutable feature identity, release, name, human-gate, or task-link semantics drifted for {feature_id}",
        )
    ids: set[str] = set()
    required_keys = {"id", "release", "name", "state", "task_ids", "evidence", "human_gates"}
    for feature in features:
        check(isinstance(feature, dict) and set(feature) == required_keys, "Feature fields drifted from the exact schema")
        feature_id = feature["id"]
        check(isinstance(feature_id, str) and FEATURE_ID.fullmatch(feature_id) is not None, f"Invalid feature ID: {feature_id}")
        check(feature_id not in ids, f"Duplicate feature ID: {feature_id}")
        ids.add(feature_id)
        state = feature["state"]
        check(state in FEATURE_STATES, f"Invalid feature state in {feature_id}")
        linked_tasks = require_string_list(feature["task_ids"], f"{feature_id}.task_ids")
        evidence = require_string_list(feature["evidence"], f"{feature_id}.evidence")
        human_gates = require_string_list(feature["human_gates"], f"{feature_id}.human_gates")
        check(all(reference in approvals for reference in human_gates), f"{feature_id} has an unknown human gate")
        check(all(task_id in tasks_by_id for task_id in linked_tasks), f"{feature_id} links an unknown task")
        parsed = parse_feature_evidence(evidence, feature_id)
        check(all(git_commit_exists(reference) for reference in parsed["commit"]), f"{feature_id} cites a missing commit")
        report_documents = [load_typed_evidence(relative, "test_report") for relative in parsed["report"]]
        review_documents = [load_typed_evidence(relative, "independent_review") for relative in parsed["review"]]
        device_documents = [load_typed_evidence(relative, "device_report") for relative in parsed["device"]]
        dataset_documents = [load_typed_evidence(relative, "dataset_report") for relative in parsed["dataset"]]
        approval_bindings = [parse_approval_reference(reference, feature_id) for reference in parsed["approval"]]
        approval_decisions = [decision_id for decision_id, _ in approval_bindings]
        check(len(approval_decisions) == len(set(approval_decisions)), f"{feature_id} cannot cite multiple approval events for one decision")
        check(all(reference in linked_tasks for reference in parsed["task"]), f"{feature_id} cites an unlinked task")
        check(all(document["task_id"] in linked_tasks for document in report_documents), f"{feature_id} cites a test report for an unlinked task")
        linked_commits = {
            task["evidence"]["commits"][0]
            for task_id in linked_tasks
            for task in [tasks_by_id[task_id]]
            if task["status"] == "VERIFIED" and len(task["evidence"]["commits"]) == 1
        }
        terminal_tasks = terminal_feature_task_ids(linked_tasks, tasks_by_id) if linked_tasks else set()
        current_commits = {
            tasks_by_id[task_id]["evidence"]["commits"][0]
            for task_id in terminal_tasks
            if tasks_by_id[task_id]["status"] == "VERIFIED" and len(tasks_by_id[task_id]["evidence"]["commits"]) == 1
        }
        check(all(document["commit"] in linked_commits for document in report_documents), f"{feature_id} cites stale test evidence")
        linked_owners = {tasks_by_id[task_id]["owner_agent"] for task_id in linked_tasks}
        linked_report_paths = {
            relative
            for task_id in linked_tasks
            for relative in tasks_by_id[task_id]["evidence"]["test_reports"]
        }
        linked_report_documents = {
            relative: load_typed_evidence(relative, "test_report")
            for relative in linked_report_paths
        }
        for relative, document in linked_report_documents.items():
            check(document["task_id"] in linked_tasks, f"{feature_id} linked task report belongs to another task")
            check(document["commit"] == tasks_by_id[document["task_id"]]["evidence"]["commits"][0], f"{feature_id} linked task report is stale")
        cited_review_tests: set[str] = set()
        for document in review_documents:
            check(document["scope_id"] == feature_id, f"{feature_id} cites a review for another scope")
            check(document["reviewer_role"] not in linked_owners, f"{feature_id} cites implementer self-review")
            check(document["recommendation"] == "PASS" and document["findings_dispositioned"] is True, f"{feature_id} cites a non-passing review")
            check(document["reviewed_commit"] in linked_commits, f"{feature_id} cites a review for a stale commit")
            for test_reference in document["test_evidence"]:
                check(test_reference in linked_report_documents, f"{feature_id} review cites a test report not recorded by a linked task")
                test_document = linked_report_documents[test_reference]
                check(test_document["task_id"] in linked_tasks and test_document["commit"] == document["reviewed_commit"], f"{feature_id} review cites stale or unrelated test evidence")
                cited_review_tests.add(test_reference)
        check(all(document["feature_id"] == feature_id for document in device_documents), f"{feature_id} cites device evidence for another feature")
        check(all(document["feature_id"] == feature_id for document in dataset_documents), f"{feature_id} cites dataset evidence for another feature")
        check(all(document["commit"] in current_commits for document in device_documents), f"{feature_id} cites device evidence for a non-current commit")
        check(all(document["commit"] in current_commits for document in dataset_documents), f"{feature_id} cites dataset evidence for a non-current commit")
        check(all(decision_id in human_gates for decision_id in approval_decisions), f"{feature_id} cites an unrelated human approval")
        for decision_id, event_id in approval_bindings:
            validate_approval_for_feature(approvals[decision_id], feature, current_commits, decision_id, event_id)
        if state == "NOT_STARTED":
            check(not evidence, f"NOT_STARTED feature {feature_id} cannot claim implementation evidence")
        else:
            check(bool(evidence), f"Advanced feature {feature_id} needs evidence")
        if state == "SPECIFIED":
            check(bool(linked_tasks) and bool(parsed["task"]), f"SPECIFIED feature {feature_id} needs task evidence")
        if state == "CODE_COMPLETE":
            check(bool(parsed["commit"]), f"CODE_COMPLETE feature {feature_id} needs verifiable commit evidence")
            check(not linked_tasks or all(tasks_by_id[task_id]["status"] in {"INTEGRATED", "VERIFIED"} for task_id in linked_tasks), f"CODE_COMPLETE feature {feature_id} has incomplete linked tasks")
            check(not linked_commits or set(parsed["commit"]) >= linked_commits, f"CODE_COMPLETE feature {feature_id} omits a linked commit")
        if state in FEATURE_STATES - {"NOT_STARTED", "SPECIFIED", "CODE_COMPLETE"}:
            check(bool(linked_tasks) and all(tasks_by_id[task_id]["status"] == "VERIFIED" for task_id in linked_tasks), f"{state} feature {feature_id} requires verified linked tasks")
        if state == "AUTOMATED_TESTED":
            check(bool(parsed["report"]), f"AUTOMATED_TESTED feature {feature_id} needs a test report")
        if state == "INTEGRATED":
            check(bool(parsed["commit"]) and bool(parsed["report"]), f"INTEGRATED feature {feature_id} needs commit and test-report evidence")
            check(set(parsed["commit"]) >= linked_commits, f"INTEGRATED feature {feature_id} omits a linked verification commit")
        if state in {"EMULATOR_VERIFIED", "PHYSICAL_DEVICE_VERIFIED"}:
            check(bool(parsed["device"]), f"{state} feature {feature_id} needs device evidence")
            check({document["commit"] for document in device_documents} == current_commits, f"{state} feature {feature_id} must cover every current terminal commit")
        if state == "EMULATOR_VERIFIED":
            check(all(document["surface"] == "android_emulator" for document in device_documents), f"EMULATOR_VERIFIED feature {feature_id} needs emulator-surface evidence")
        if state == "PHYSICAL_DEVICE_VERIFIED":
            check(all(document["surface"] in {"android_physical", "ios_physical"} for document in device_documents), f"PHYSICAL_DEVICE_VERIFIED feature {feature_id} needs physical-surface evidence")
            check("TL-D-013" in approval_decisions, f"PHYSICAL_DEVICE_VERIFIED feature {feature_id} needs approved decision TL-D-013")
        if state == "DATASET_EVALUATED":
            check(bool(parsed["dataset"]), f"DATASET_EVALUATED feature {feature_id} needs dataset evidence")
            check({document["commit"] for document in dataset_documents} == current_commits, f"DATASET_EVALUATED feature {feature_id} must cover every current terminal commit")
            check("TL-D-012" in approval_decisions, f"DATASET_EVALUATED feature {feature_id} needs approved decision TL-D-012")
        if state == "SECURITY_REVIEWED":
            check(bool(parsed["review"]), f"SECURITY_REVIEWED feature {feature_id} needs independent review evidence")
            check(all(document["reviewer_role"] == "security_privacy_reviewer" for document in review_documents), f"SECURITY_REVIEWED feature {feature_id} needs security_privacy_reviewer evidence")
            check({document["reviewed_commit"] for document in review_documents} >= linked_commits, f"SECURITY_REVIEWED feature {feature_id} does not cover every linked verification commit")
            check(cited_review_tests == linked_report_paths, f"SECURITY_REVIEWED feature {feature_id} does not cover every recorded linked task report")
        if state in HUMAN_ATTESTED_FEATURE_STATES:
            check(bool(parsed["approval"]), f"{state} feature {feature_id} needs a feature-specific human approval")
        if state in {"PILOT_READY", "PRODUCTION_APPROVED"}:
            check(bool(human_gates) and all(approvals[reference]["state"] == "APPROVED" for reference in human_gates), f"{state} feature {feature_id} has pending feature gates")
            check(set(approval_decisions) >= set(human_gates), f"{state} feature {feature_id} must cite every approved feature gate")
    check(not registry.get("providers"), "R0 must not configure external providers")
    return features


def parse_decision_table(text: str, label: str) -> dict[str, list[str]]:
    rows: dict[str, list[str]] = {}
    for line in text.splitlines():
        if not line.lstrip().startswith("| TL-D-"):
            continue
        columns = [column.strip() for column in line.strip().strip("|").split("|")]
        check(columns and DECISION_ID.fullmatch(columns[0]) is not None, f"Malformed decision row in {label}")
        check(columns[0] not in rows, f"Duplicate decision {columns[0]} in {label}")
        rows[columns[0]] = columns
    check(bool(rows), f"No decision rows found in {label}")
    return rows


def validate_decisions(required_texts: dict[str, str]) -> dict[str, dict]:
    decisions = parse_decision_table(required_texts["docs/program/DECISIONS_REQUIRED.md"], "DECISIONS_REQUIRED")
    approvals = parse_decision_table(required_texts["docs/program/HUMAN_APPROVALS.md"], "HUMAN_APPROVALS")
    check(set(decisions) == set(R0_DECISION_IDS), "Decision IDs drifted from the exact TL-D-001 through TL-D-017 baseline")
    check(set(approvals) == set(R0_DECISION_IDS), "Human approval IDs drifted from the exact TL-D-001 through TL-D-017 baseline")
    for decision_id in R0_DECISION_IDS:
        check(
            projection_digest(decisions[decision_id][:-1]) == R0_DECISION_SPEC_SHA256[decision_id],
            f"Immutable DECISIONS_REQUIRED semantics drifted for {decision_id}",
        )
        check(
            projection_digest(approvals[decision_id][:3]) == R0_HUMAN_GATE_SPEC_SHA256[decision_id],
            f"Immutable HUMAN_APPROVALS gate semantics drifted for {decision_id}",
        )
    check(set(decisions) == set(approvals), "Decision and approval ledgers are not one-to-one")
    approvals_by_id: dict[str, dict] = {}
    for decision_id, columns in decisions.items():
        check(columns[-1] in {"PENDING", "APPROVED", "INACTIVE"}, f"Decision {decision_id} has an invalid state")
    head = git_head_commit()
    check(head is not None, "Cannot resolve HEAD while validating human approvals")
    approval_root = EVIDENCE_ROOTS["human_approval_ledger"][0]
    historical_approval_paths = git_historical_paths_under(approval_root, head)
    indexed_approval_paths = {entry[3] for entry in git_index_entries_under(approval_root)}
    for decision_id, columns in approvals.items():
        check(len(columns) == 8 and columns[4] in {"PENDING", "APPROVED", "INACTIVE"}, f"Approval {decision_id} has an invalid state")
        check(columns[4] == decisions[decision_id][-1], f"Decision and approval states differ for {decision_id}")
        expected_ledger_path = f"docs/program/evidence/approvals/{decision_id}.json"
        if columns[6] == "-":
            check(columns[4] == "PENDING", f"Approved decision {decision_id} has no approval ledger")
            check(columns[3] == "-" and columns[5:] == ["-", "-", "-"], f"Pending approval {decision_id} contains fabricated approval evidence")
            check(
                expected_ledger_path not in historical_approval_paths
                and expected_ledger_path not in indexed_approval_paths,
                f"Pending decision {decision_id} cannot delete or hide an existing approval ledger",
            )
            ledger = None
            active_grants: dict[str, dict] = {}
            ledger_path = None
        else:
            check(all(value != "-" for value in (columns[3], columns[5], columns[7])), f"Approval history for {decision_id} lacks approver, date, or scope")
            identities = [identity.strip() for identity in columns[3].split(";") if identity.strip()]
            check(identities and len(identities) == len({identity.casefold() for identity in identities}) and all(looks_like_named_human(identity) for identity in identities), f"Approval history for {decision_id} lacks unique actual named humans")
            check(all(identity.casefold() != columns[2].casefold() for identity in identities), f"Approval history for {decision_id} uses a role label instead of a human identity")
            ledger_date = parse_nonfuture_date(columns[5], f"Approval ledger date for {decision_id}")
            check(columns[6] == expected_ledger_path, f"Decision {decision_id} must use its canonical approval ledger path")
            check(columns[7] == "SCOPED GRANTS ONLY; SEE LEDGER", f"Decision {decision_id} approval history must remain explicitly scoped")
            ledger = load_typed_evidence(expected_ledger_path, "human_approval_ledger")
            validate_approval_ledger_history(expected_ledger_path, ledger)
            check(ledger["decision_id"] == decision_id, f"Approval ledger belongs to another decision")
            check(approval_ledger_actors(ledger) == identities, f"Approval ledger actor union does not match the human-owned table")
            first_event_date = parse_nonfuture_date(ledger["events"][0]["approval_date"], f"First approval event date for {decision_id}")
            check(first_event_date == ledger_date, f"Approval ledger activation date does not match its first event")
            active_grants = active_approval_grants(ledger)
            expected_state = "APPROVED" if active_grants else "INACTIVE"
            check(columns[4] == expected_state, f"Decision {decision_id} state does not match its active scoped grants")
            ledger_path = expected_ledger_path
        approvals_by_id[decision_id] = {
            "state": columns[4],
            "ledger_path": ledger_path,
            "ledger": ledger,
            "active_grants": active_grants,
        }
    return approvals_by_id


def validate_project_state(text: str) -> None:
    for label in PROJECT_STATE_LABELS:
        check(label in text, f"PROJECT_STATE missing label {label}")
    check("Current release: R0" in text, "PROJECT_STATE release must be R0")
    check("codex/thrivelens-integration" in text, "PROJECT_STATE must name the integration branch")
    check("44515a0" in text, "PROJECT_STATE must retain the stable checkpoint")


def validate_budget(budget: dict) -> None:
    check(set(budget) == {"schema_version", "phase", "cap_gb", "warning_percent", "hard_stop_percent", "additional_roots", "rules"}, "Resource budget top-level fields drifted")
    check(is_exact_int(budget.get("schema_version")) and budget["schema_version"] == 1, "Resource budget schema_version must be integer 1")
    check(budget.get("phase") in {"prebootstrap", "bootstrap_active", "implementation", "release"}, "Invalid resource phase")
    check(is_exact_int(budget.get("cap_gb")) and budget["cap_gb"] == 18, "Resource cap must remain exactly integer 18 GB")
    warning = budget.get("warning_percent")
    hard_stop = budget.get("hard_stop_percent")
    check(is_exact_int(warning) and is_exact_int(hard_stop) and warning == 75 and hard_stop == 85, "Resource thresholds must remain exactly integer 75/85 percent")
    roots = budget.get("additional_roots")
    expected_root = {
        "label": "local_attributable",
        "path": "%LOCALAPPDATA%\\ThriveLens",
        "purpose": RESOURCE_ROOT_PURPOSE,
        "required_in_phases": ["bootstrap_active", "implementation", "release"],
    }
    check(isinstance(roots, list) and exact_value_equal(roots, [expected_root]), "Resource budget must contain the one exact attributable root")
    rules = budget.get("rules")
    check(isinstance(rules, dict) and set(rules) == {"absolute_cap_semantics", "high_watermark_semantics", "model_downloads_in_bootstrap", "local_builds_are_sequential"}, "Resource rule fields drifted")
    check(rules.get("absolute_cap_semantics") == "fail when accounted bytes are greater than or equal to 18 GB", "Cap boundary must remain strict")
    check(rules.get("high_watermark_semantics") == "all installs and builds stop at or above 85 percent until a reviewed configuration decision changes the budget", "High-water policy drifted")
    check(rules.get("model_downloads_in_bootstrap") is False, "Bootstrap model downloads must remain disabled")
    check(rules.get("local_builds_are_sequential") is True, "Local builds must remain sequential")


def validate_resource_phase_for_tasks(tasks: list[dict], budget: dict) -> None:
    by_id = {task["id"]: task for task in tasks}
    platform_task = by_id.get("TL-R0-003")
    check(platform_task is not None, "R0 task graph is missing TL-R0-003")
    if platform_task["status"] == "VERIFIED":
        check(budget.get("phase") in {"bootstrap_active", "implementation", "release"}, "TL-R0-003 cannot be VERIFIED while the attributable resource phase is prebootstrap")


def validate_network_policy(policy: dict) -> None:
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
    check(exact_value_equal(policy, expected), "R0 network policy drifted from the exact typed loopback, same-origin, ADB cleanup, debug-only cleartext, release-negative, or production-disabled contract")


def main() -> None:
    required_texts = validate_required_files()
    approvals = validate_decisions(required_texts)
    graph = load_json_yaml("docs/program/TASK_GRAPH.yaml")
    tasks, _ = validate_tasks(graph, required_texts)
    registry = load_json_yaml("docs/program/FEATURE_REGISTRY.yaml")
    features = validate_features(registry, {task["id"]: task for task in tasks}, approvals)
    validate_project_state(required_texts["docs/program/PROJECT_STATE.md"])
    budget = load_json_yaml("config/resource-budget.json")
    validate_budget(budget)
    validate_resource_phase_for_tasks(tasks, budget)
    validate_network_policy(load_json_yaml("config/r0-network-policy.json"))
    validate_evidence_inventory(graph, registry, approvals)
    print(
        json.dumps(
            {
                "status": "PASS",
                "required_files": len(REQUIRED_FILES),
                "r0_tasks": len(tasks),
                "features": len(features),
                "pending_human_approvals": sum(metadata["state"] == "PENDING" for metadata in approvals.values()),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except ControlPlaneError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1) from None
