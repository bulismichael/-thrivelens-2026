from __future__ import annotations

import ctypes
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from expected_red import test_android_heartbeat_acceptance as acceptance


def _process_is_running(process_id: int) -> bool:
    if os.name == "nt":
        from ctypes import wintypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel32.OpenProcess.restype = wintypes.HANDLE
        kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        kernel32.WaitForSingleObject.restype = wintypes.DWORD
        kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel32.CloseHandle.restype = wintypes.BOOL
        handle = kernel32.OpenProcess(0x00100000, False, process_id)
        if not handle:
            return False
        try:
            return kernel32.WaitForSingleObject(handle, 0) == 0x00000102
        finally:
            kernel32.CloseHandle(handle)

    try:
        os.kill(process_id, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


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

    def test_analyzer_aggregate_output_cap_terminates_the_entire_tree(self) -> None:
        with tempfile.TemporaryDirectory(prefix="thrivelens-r0-analyzer-cap-") as temporary:
            root = Path(temporary)
            fixture = root / "over-cap-analyzer.py"
            process_record = root / "processes.json"
            fixture.write_text(
                """
import json
import os
import subprocess
import sys
import time
from pathlib import Path

child = subprocess.Popen(
    [sys.executable, "-c", "import time; time.sleep(8)"],
    stdout=sys.stdout,
    stderr=sys.stderr,
)
Path(sys.argv[1]).write_text(
    json.dumps({"parent": os.getpid(), "child": child.pid}),
    encoding="utf-8",
)
chunk = b"X" * 65536
for _ in range(20):
    sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()
for _ in range(20):
    sys.stderr.buffer.write(chunk)
    sys.stderr.buffer.flush()
time.sleep(8)
""".strip(),
                encoding="utf-8",
            )
            started_at = time.monotonic()
            with self.assertRaisesRegex(AssertionError, "output limit"):
                acceptance._run_pinned_analyzer(
                    Path(sys.executable),
                    [str(fixture), str(process_record)],
                )
            self.assertLess(time.monotonic() - started_at, 5.0)
            process_ids = json.loads(process_record.read_text(encoding="utf-8"))
            deadline = time.monotonic() + 1.0
            while time.monotonic() < deadline and any(
                _process_is_running(process_id) for process_id in process_ids.values()
            ):
                time.sleep(0.01)
            self.assertFalse(
                any(_process_is_running(process_id) for process_id in process_ids.values()),
                "bounded analyzer runner left a fixture process alive",
            )


if __name__ == "__main__":
    unittest.main()
