from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from expected_red import test_android_heartbeat_acceptance as acceptance


class ReleaseAnalyzerContractTests(unittest.TestCase):
    def test_fake_wrapper_children_are_deterministic_python_processes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-fake-tool-") as temporary:
            root = Path(temporary)
            adb, probe_ok, probe_fail = acceptance._build_fake_android_tools(root)
            adb_log = root / "adb.log"
            probe_log = root / "probe.log"
            environment = os.environ.copy()
            environment["THRIVELENS_FAKE_ADB_LOG"] = str(adb_log)
            environment["THRIVELENS_FAKE_PROBE_LOG"] = str(probe_log)
            adb_result = subprocess.run(
                [
                    sys.executable,
                    str(adb),
                    "-s",
                    "fixture-device",
                    "reverse",
                    "tcp:8000",
                    "tcp:8000",
                ],
                env=environment,
                timeout=10,
                check=False,
            )
            probe_result = subprocess.run(
                [sys.executable, str(probe_ok), "--mode", "debug"],
                env=environment,
                timeout=10,
                check=False,
            )
            failed_probe_result = subprocess.run(
                [sys.executable, str(probe_fail), "--mode", "debug"],
                env=environment,
                timeout=10,
                check=False,
            )
            self.assertEqual(adb_result.returncode, 0)
            self.assertEqual(probe_result.returncode, 0)
            self.assertEqual(failed_probe_result.returncode, 7)
            self.assertEqual(
                adb_log.read_text(encoding="utf-8").strip(),
                "-s fixture-device reverse tcp:8000 tcp:8000",
            )

    def test_pinned_analyzer_record_is_closed_and_digest_bound(self) -> None:
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-analyzer-") as temporary:
            root = Path(temporary)
            analyzer = root / "aapt2.exe"
            analyzer.write_bytes(b"synthetic-pinned-analyzer")
            manifest = root / "mobile.json"
            record = {
                "path": str(analyzer),
                "sha256": hashlib.sha256(analyzer.read_bytes()).hexdigest(),
                "version": "35.0.0",
            }
            manifest.write_text(json.dumps({"android": {"aapt2": record}}), encoding="utf-8")
            with patch.object(acceptance, "MOBILE_TOOLCHAIN", manifest):
                self.assertEqual(acceptance._pinned_aapt2_path("fixture marker"), analyzer)

                record["unexpected"] = True
                manifest.write_text(
                    json.dumps({"android": {"aapt2": record}}), encoding="utf-8"
                )
                with self.assertRaises(AssertionError):
                    acceptance._pinned_aapt2_path("fixture marker")

                record.pop("unexpected")
                record["sha256"] = "0" * 64
                manifest.write_text(
                    json.dumps({"android": {"aapt2": record}}), encoding="utf-8"
                )
                with self.assertRaises(AssertionError):
                    acceptance._pinned_aapt2_path("fixture marker")

    def test_analyzer_invocation_is_direct_bounded_and_nonzero_fails(self) -> None:
        output = acceptance._run_pinned_analyzer(
            Path(sys.executable),
            ["-c", "print('synthetic analyzer output')"],
        )
        self.assertEqual(output.strip(), "synthetic analyzer output")
        with self.assertRaises(AssertionError):
            acceptance._run_pinned_analyzer(
                Path(sys.executable),
                ["-c", "raise SystemExit(7)"],
            )


if __name__ == "__main__":
    unittest.main()
