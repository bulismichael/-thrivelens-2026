from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from scripts.contracts.bounded_process import BoundedProcessError, run_bounded_process
from scripts.contracts.r0_transport import (
    inspect_release_apk_bytes,
    load_policy,
    load_release_policy_from_apk,
    scan_packaged_inputs,
    validate_policy,
)


ANDROID_ROOT = REPOSITORY_ROOT / "apps" / "mobile" / "android"
MOBILE_ROOT = REPOSITORY_ROOT / "apps" / "mobile"
VERIFY_WRAPPER = REPOSITORY_ROOT / "scripts" / "mobile" / "verify_android_surface.ps1"
BUILD_WRAPPER = REPOSITORY_ROOT / "scripts" / "mobile" / "build_android.ps1"
DEBUG_MANIFEST = ANDROID_ROOT / "app" / "src" / "debug" / "AndroidManifest.xml"
DEBUG_NETWORK_CONFIG = (
    ANDROID_ROOT / "app" / "src" / "debug" / "res" / "xml" / "network_security_config.xml"
)
RELEASE_MANIFEST = ANDROID_ROOT / "app" / "src" / "release" / "AndroidManifest.xml"
ANDROID_BUILD_CONFIG = ANDROID_ROOT / "app" / "build.gradle.kts"
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
INVOCATION_MODULE = REPOSITORY_ROOT / "scripts" / "contracts" / "R0AndroidInvocation.psm1"
MOBILE_TOOLCHAIN = REPOSITORY_ROOT / "config" / "toolchains" / "mobile.json"
RELEASE_APK = MOBILE_ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"


def _application(path: Path) -> ET.Element:
    root = ET.parse(path).getroot()
    application = root.find("application")
    if application is None:
        raise AssertionError(f"{path.name} must contain application")
    return application


def _build_fake_android_tools(root: Path) -> tuple[Path, Path, Path]:
    source = root / "fixture-tool.py"
    source.write_text(
        '''
from __future__ import annotations

import os
import sys
from pathlib import Path

role = Path(sys.argv[0]).stem.lower()
arguments = sys.argv[1:]
if role.startswith("fake-adb"):
    with open(os.environ["THRIVELENS_FAKE_ADB_LOG"], "a", encoding="utf-8") as handle:
        handle.write(" ".join(arguments) + "\\n")
    if (
        os.environ.get("THRIVELENS_FAKE_ADB_FAIL_REVERSE") == "1"
        and len(arguments) >= 4
        and arguments[2:4] == ["reverse", "tcp:8000"]
    ):
        raise SystemExit(9)
    raise SystemExit(0)
with open(os.environ["THRIVELENS_FAKE_PROBE_LOG"], "a", encoding="utf-8") as handle:
    handle.write(" ".join(arguments) + "\\n")
raise SystemExit(7 if role.startswith("probe-fail") else 0)
'''.strip(),
        encoding="utf-8",
    )
    adb = root / "fake-adb.py"
    probe_ok = root / "probe-ok.py"
    probe_fail = root / "probe-fail.py"
    for target in (adb, probe_ok, probe_fail):
        shutil.copyfile(source, target)
    return adb, probe_ok, probe_fail


def _pinned_aapt2_path(marker: str) -> Path:
    if not MOBILE_TOOLCHAIN.is_file():
        raise AssertionError(marker)
    try:
        manifest = json.loads(MOBILE_TOOLCHAIN.read_text(encoding="utf-8"))
        aapt2 = manifest["android"]["aapt2"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError):
        raise AssertionError(marker) from None
    if not isinstance(aapt2, dict) or set(aapt2) != {"path", "sha256", "version"}:
        raise AssertionError("pinned aapt2 record must be a closed object")
    if not isinstance(aapt2["version"], str) or re.fullmatch(
        r"[0-9]+(?:\.[0-9]+){1,3}", aapt2["version"]
    ) is None:
        raise AssertionError("pinned aapt2 version is invalid")
    if not isinstance(aapt2["sha256"], str) or re.fullmatch(
        r"[0-9a-f]{64}", aapt2["sha256"]
    ) is None:
        raise AssertionError("pinned aapt2 digest is invalid")
    if not isinstance(aapt2["path"], str) or not aapt2["path"]:
        raise AssertionError("pinned aapt2 path is invalid")
    analyzer = Path(os.path.expandvars(aapt2["path"]))
    if not analyzer.is_absolute():
        analyzer = REPOSITORY_ROOT / analyzer
    if not analyzer.is_file():
        raise AssertionError(marker)
    digest = hashlib.sha256()
    with analyzer.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    if digest.hexdigest() != aapt2["sha256"]:
        raise AssertionError("installed aapt2 digest differs from its pin")
    return analyzer


def _run_pinned_analyzer(analyzer: Path, arguments: list[str]) -> str:
    try:
        result = run_bounded_process(
            [str(analyzer), *arguments],
            cwd=REPOSITORY_ROOT,
            maximum_output_bytes=2 * 1024 * 1024,
            timeout_seconds=20,
        )
    except BoundedProcessError as error:
        raise AssertionError(str(error)) from None
    if result.returncode != 0:
        raise AssertionError("pinned Android analyzer rejected the release artifact")
    try:
        return result.stdout.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        raise AssertionError("pinned Android analyzer output is not UTF-8") from None


class AndroidHeartbeatAcceptanceTests(unittest.TestCase):
    def test_selected_device_reverse_and_failure_cleanup(self) -> None:
        marker = "THRIVELENS_MISSING_IMPLEMENTATION::TL-R0-008-ADB-REVERSE-LIFECYCLE"
        if not VERIFY_WRAPPER.is_file():
            self.fail(marker)
        wrapper_source = VERIFY_WRAPPER.read_text(encoding="utf-8")
        self.assertIn("R0AndroidInvocation.psm1", wrapper_source)
        self.assertEqual(wrapper_source.count("Invoke-R0AndroidVerification"), 1)
        for forbidden_wrapper_primitive in (
            "Start-Process",
            "ProcessStartInfo",
            "UseShellExecute",
            "ArgumentList",
            "ProcessInvoker",
            "&",
        ):
            self.assertNotIn(forbidden_wrapper_primitive, wrapper_source)
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-adb-") as temporary:
            root = Path(temporary)
            adb, probe_ok, probe_fail = _build_fake_android_tools(root)
            log = root / "adb.log"
            probe_log = root / "probe.log"
            environment = os.environ.copy()
            environment["THRIVELENS_FAKE_ADB_LOG"] = str(log)
            environment["THRIVELENS_FAKE_PROBE_LOG"] = str(probe_log)

            def run(probe: Path, serial: str = "fixture-device") -> subprocess.CompletedProcess[str]:
                return subprocess.run(
                    [
                        "pwsh",
                        "-NoProfile",
                        "-File",
                        str(VERIFY_WRAPPER),
                        "-DeviceSerial",
                        serial,
                        "-AdbPath",
                        str(adb),
                        "-HeartbeatProbePath",
                        str(probe),
                    ],
                    cwd=REPOSITORY_ROOT,
                    env=environment,
                    capture_output=True,
                    text=True,
                    timeout=20,
                    check=False,
                )

            success = run(probe_ok)
            self.assertEqual(success.returncode, 0, (success.stdout + success.stderr)[-2000:])
            success_lines = log.read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                success_lines,
                [
                    "-s fixture-device reverse tcp:8000 tcp:8000",
                    "-s fixture-device reverse --remove tcp:8000",
                ],
            )
            self.assertEqual(
                probe_log.read_text(encoding="utf-8").splitlines(),
                ["--base-url http://127.0.0.1:8000/api/v1 --mode debug"],
            )
            log.unlink()
            probe_log.unlink()
            failure = run(probe_fail)
            self.assertNotEqual(failure.returncode, 0)
            failure_lines = log.read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                failure_lines,
                [
                    "-s fixture-device reverse tcp:8000 tcp:8000",
                    "-s fixture-device reverse --remove tcp:8000",
                ],
            )
            self.assertEqual(
                probe_log.read_text(encoding="utf-8").splitlines(),
                ["--base-url http://127.0.0.1:8000/api/v1 --mode debug"],
            )
            combined = (success.stdout + success.stderr + failure.stdout + failure.stderr).lower()
            self.assertNotIn("remove-all", combined)
            log.unlink()
            probe_log.unlink()
            environment["THRIVELENS_FAKE_ADB_FAIL_REVERSE"] = "1"
            reverse_failure = run(probe_ok)
            self.assertNotEqual(reverse_failure.returncode, 0)
            self.assertEqual(
                log.read_text(encoding="utf-8").splitlines(),
                [
                    "-s fixture-device reverse tcp:8000 tcp:8000",
                    "-s fixture-device reverse --remove tcp:8000",
                ],
            )
            self.assertFalse(probe_log.exists())
            log.unlink()
            environment.pop("THRIVELENS_FAKE_ADB_FAIL_REVERSE")
            for unsafe_serial in (
                "",
                "-e",
                "--help",
                "-serial",
                "serial;TL_CANARY",
                "serial|TL_CANARY",
                "serial&TL_CANARY",
                "serial<TL_CANARY",
                "serial>TL_CANARY",
                'serial"TL_CANARY',
                "serial'TL_CANARY",
                "serial%TL_CANARY",
                "serial`TL_CANARY",
                "serial\tTL_CANARY",
                "serial TL_CANARY",
                "serial\nTL_CANARY",
                " leading",
            ):
                with self.subTest(unsafe_serial=repr(unsafe_serial)):
                    if log.exists():
                        log.unlink()
                    if probe_log.exists():
                        probe_log.unlink()
                    rejected = run(probe_ok, unsafe_serial)
                    self.assertNotEqual(rejected.returncode, 0)
                    self.assertFalse(log.exists(), "unsafe serial reached adb")
                    self.assertFalse(probe_log.exists(), "unsafe serial reached the heartbeat probe")

    def test_debug_cleartext_is_loopback_scoped(self) -> None:
        marker = "THRIVELENS_MISSING_IMPLEMENTATION::TL-R0-008-DEBUG-MANIFEST-BOUNDARY"
        if (
            not DEBUG_MANIFEST.is_file()
            or not DEBUG_NETWORK_CONFIG.is_file()
            or not ANDROID_BUILD_CONFIG.is_file()
        ):
            self.fail(marker)
        application = _application(DEBUG_MANIFEST)
        self.assertEqual(application.get(ANDROID_NS + "usesCleartextTraffic"), "true")
        self.assertEqual(
            application.get(ANDROID_NS + "networkSecurityConfig"),
            "@xml/network_security_config",
        )
        network_root = ET.parse(DEBUG_NETWORK_CONFIG).getroot()
        self.assertEqual(network_root.tag, "network-security-config")
        self.assertEqual([child.tag for child in network_root], ["base-config", "domain-config"])
        self.assertEqual(network_root.attrib, {})
        base_configs = network_root.findall("base-config")
        self.assertEqual(len(base_configs), 1)
        self.assertEqual(base_configs[0].attrib, {"cleartextTrafficPermitted": "false"})
        self.assertEqual(list(base_configs[0]), [])
        domain_configs = network_root.findall("domain-config")
        self.assertEqual(len(domain_configs), 1)
        self.assertEqual(domain_configs[0].attrib, {"cleartextTrafficPermitted": "true"})
        domains = domain_configs[0].findall("domain")
        self.assertEqual(len(domains), 1)
        self.assertEqual(list(domain_configs[0]), domains)
        self.assertEqual((domains[0].text or "").strip(), "127.0.0.1")
        self.assertEqual(domains[0].attrib, {"includeSubdomains": "false"})
        self.assertEqual(list(domains[0]), [])
        serialized = DEBUG_NETWORK_CONFIG.read_text(encoding="utf-8").lower()
        for forbidden in ("0.0.0.0", "10.0.2.2", "cleartexttrafficpermitted=\"true\"><domain>localhost"):
            self.assertNotIn(forbidden, serialized)
        build_config = ANDROID_BUILD_CONFIG.read_text(encoding="utf-8")
        self.assertIsNotNone(re.search(r"\bminSdk\s*=\s*29\b", build_config))

    def test_release_rejects_debug_transport_and_production(self) -> None:
        marker = "THRIVELENS_MISSING_IMPLEMENTATION::TL-R0-008-RELEASE-PRODUCTION-NEGATIVE"
        if (
            not RELEASE_MANIFEST.is_file()
            or not BUILD_WRAPPER.is_file()
            or not (MOBILE_ROOT / "lib").is_dir()
            or not (MOBILE_ROOT / "pubspec.yaml").is_file()
        ):
            self.fail(marker)
        application = _application(RELEASE_MANIFEST)
        self.assertEqual(application.get(ANDROID_NS + "usesCleartextTraffic"), "false")
        self.assertIsNone(application.get(ANDROID_NS + "networkSecurityConfig"))
        packaged_sources = [
            ANDROID_ROOT / "app" / "src" / "main",
            ANDROID_ROOT / "app" / "src" / "release",
            MOBILE_ROOT / "lib",
            MOBILE_ROOT / "pubspec.yaml",
        ]
        assets = MOBILE_ROOT / "assets"
        if assets.exists():
            packaged_sources.append(assets)
        packaged_scan = scan_packaged_inputs(packaged_sources)
        self.assertGreater(packaged_scan["files"], 0)
        self.assertGreater(packaged_scan["bytes"], 0)
        if not RELEASE_APK.is_file():
            self.fail(marker)
        analyzer = _pinned_aapt2_path(marker)
        inspect_release_apk_bytes(RELEASE_APK)
        self.assertEqual(
            load_release_policy_from_apk(RELEASE_APK),
            {
                "schema_version": 1,
                "resolved_api_base_url": "",
                "production_enabled": False,
            },
        )
        manifest_dump = _run_pinned_analyzer(
            analyzer,
            ["dump", "xmltree", "--file", "AndroidManifest.xml", str(RELEASE_APK)],
        ).lower()
        cleartext_lines = [
            line for line in manifest_dump.splitlines() if "usescleartexttraffic" in line
        ]
        self.assertEqual(len(cleartext_lines), 1)
        self.assertRegex(cleartext_lines[0], r"(?:\(type 0x12\)0x0\b|=\s*false\b)")
        self.assertNotIn("networksecurityconfig", manifest_dump)
        resource_dump = _run_pinned_analyzer(
            analyzer,
            ["dump", "resources", str(RELEASE_APK)],
        ).lower()
        self.assertIsNone(re.search(r"network[_-]?security|security[_-]?config", resource_dump))
        safe_environment = os.environ.copy()
        for variable in (
            "THRIVELENS_API_BASE_URL",
            "THRIVELENS_API_BASE_SCHEME",
            "THRIVELENS_API_BASE_HOST",
            "THRIVELENS_API_BASE_PORT",
            "THRIVELENS_API_BASE_PATH",
            "THRIVELENS_PRODUCTION_ENABLED",
        ):
            safe_environment.pop(variable, None)
        policy_check = subprocess.run(
            [
                "pwsh",
                "-NoProfile",
                "-File",
                str(BUILD_WRAPPER),
                "-Mode",
                "Release",
                "-PolicyCheckOnly",
            ],
            cwd=REPOSITORY_ROOT,
            env=safe_environment,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        self.assertEqual(
            policy_check.returncode,
            0,
            (policy_check.stdout + policy_check.stderr)[-2000:],
        )
        self.assertEqual(
            json.loads(policy_check.stdout),
            {
                "mode": "release",
                "minimum_android_api": 29,
                "production_enabled": False,
                "cleartext_allowed": False,
                "debug_base_url_allowed": False,
                "resolved_api_base_url": "",
            },
        )
        for label, unsafe_overrides in (
            (
                "direct debug base",
                {"THRIVELENS_API_BASE_URL": "http://127.0.0.1:8000/api/v1"},
            ),
            ("production enabled", {"THRIVELENS_PRODUCTION_ENABLED": "true"}),
            (
                "split debug base",
                {
                    "THRIVELENS_API_BASE_SCHEME": "http",
                    "THRIVELENS_API_BASE_HOST": "127.0.0.1",
                    "THRIVELENS_API_BASE_PORT": "8000",
                    "THRIVELENS_API_BASE_PATH": "/api/v1",
                },
            ),
        ):
            with self.subTest(policy_negative=label):
                unsafe_environment = safe_environment.copy()
                unsafe_environment.update(unsafe_overrides)
                unsafe_check = subprocess.run(
                    [
                        "pwsh",
                        "-NoProfile",
                        "-File",
                        str(BUILD_WRAPPER),
                        "-Mode",
                        "Release",
                        "-PolicyCheckOnly",
                    ],
                    cwd=REPOSITORY_ROOT,
                    env=unsafe_environment,
                    capture_output=True,
                    text=True,
                    timeout=20,
                    check=False,
                )
                self.assertNotEqual(unsafe_check.returncode, 0)
        policy = load_policy()
        validate_policy(policy)
        self.assertFalse(policy["android_release"]["cleartext_allowed"])
        self.assertTrue(policy["android_release"]["reject_debug_base_url"])
        self.assertFalse(policy["android_release"]["production_enabled"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
