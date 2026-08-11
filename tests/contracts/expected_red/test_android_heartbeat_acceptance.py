from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from scripts.contracts.r0_transport import load_policy, validate_policy


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


def _application(path: Path) -> ET.Element:
    root = ET.parse(path).getroot()
    application = root.find("application")
    if application is None:
        raise AssertionError(f"{path.name} must contain application")
    return application


class AndroidHeartbeatAcceptanceTests(unittest.TestCase):
    def test_selected_device_reverse_and_failure_cleanup(self) -> None:
        marker = "THRIVELENS_MISSING_IMPLEMENTATION::TL-R0-008-ADB-REVERSE-LIFECYCLE"
        if not VERIFY_WRAPPER.is_file():
            self.fail(marker)
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-adb-") as temporary:
            root = Path(temporary)
            adb = root / "fake-adb.cmd"
            probe_ok = root / "probe-ok.cmd"
            probe_fail = root / "probe-fail.cmd"
            log = root / "adb.log"
            probe_log = root / "probe.log"
            adb.write_text(
                '@echo off\r\n'
                'echo %*>>"%THRIVELENS_FAKE_ADB_LOG%"\r\n'
                'if "%THRIVELENS_FAKE_ADB_FAIL_REVERSE%"=="1" if "%3"=="reverse" if "%4"=="tcp:8000" exit /b 9\r\n'
                'exit /b 0\r\n',
                encoding="utf-8",
            )
            probe_ok.write_text(
                '@echo off\r\necho %*>>"%THRIVELENS_FAKE_PROBE_LOG%"\r\nexit /b 0\r\n',
                encoding="utf-8",
            )
            probe_fail.write_text(
                '@echo off\r\necho %*>>"%THRIVELENS_FAKE_PROBE_LOG%"\r\nexit /b 7\r\n',
                encoding="utf-8",
            )
            environment = os.environ.copy()
            environment["THRIVELENS_FAKE_ADB_LOG"] = str(log)
            environment["THRIVELENS_FAKE_PROBE_LOG"] = str(probe_log)

            def run(probe: Path) -> subprocess.CompletedProcess[str]:
                return subprocess.run(
                    [
                        "pwsh",
                        "-NoProfile",
                        "-File",
                        str(VERIFY_WRAPPER),
                        "-DeviceSerial",
                        "fixture-device",
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
            missing_serial = subprocess.run(
                [
                    "pwsh",
                    "-NoProfile",
                    "-File",
                    str(VERIFY_WRAPPER),
                    "-DeviceSerial",
                    "",
                    "-AdbPath",
                    str(adb),
                    "-HeartbeatProbePath",
                    str(probe_ok),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
            self.assertNotEqual(missing_serial.returncode, 0)
            self.assertFalse(log.exists())
            self.assertFalse(probe_log.exists())

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
        release_tree = "\n".join(
            path.read_text(encoding="utf-8", errors="strict")
            for source_set in (
                ANDROID_ROOT / "app" / "src" / "main",
                ANDROID_ROOT / "app" / "src" / "release",
                MOBILE_ROOT / "lib",
                MOBILE_ROOT / "assets",
            )
            for path in source_set.rglob("*")
            if path.is_file()
            and path.suffix.lower() in {".xml", ".gradle", ".kts", ".properties", ".json", ".dart"}
        ).lower() + "\n" + (MOBILE_ROOT / "pubspec.yaml").read_text(encoding="utf-8").lower()
        self.assertNotIn("http://127.0.0.1:8000/api/v1", release_tree)
        self.assertNotIn("usescleartexttraffic=\"true\"", release_tree)
        safe_environment = os.environ.copy()
        safe_environment.pop("THRIVELENS_API_BASE_URL", None)
        safe_environment.pop("THRIVELENS_PRODUCTION_ENABLED", None)
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
            },
        )
        for variable, unsafe_value in (
            ("THRIVELENS_API_BASE_URL", "http://127.0.0.1:8000/api/v1"),
            ("THRIVELENS_PRODUCTION_ENABLED", "true"),
        ):
            with self.subTest(variable=variable):
                unsafe_environment = safe_environment.copy()
                unsafe_environment[variable] = unsafe_value
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
