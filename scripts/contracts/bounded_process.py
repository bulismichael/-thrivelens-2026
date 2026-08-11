from __future__ import annotations

import ctypes
import os
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Sequence


_READ_CHUNK_BYTES = 65536
_POST_EXIT_DRAIN_SECONDS = 1.0
_TERMINATION_SECONDS = 0.75


class BoundedProcessError(RuntimeError):
    """A deliberately coarse failure from a bounded child process."""


@dataclass(frozen=True)
class BoundedProcessResult:
    stdout: bytes
    stderr: bytes
    returncode: int


class _OutputState:
    def __init__(self, maximum_bytes: int) -> None:
        self.maximum_bytes = maximum_bytes
        self.total_bytes = 0
        self.stdout = bytearray()
        self.stderr = bytearray()
        self.overflowed = False
        self.read_failed = False
        self.lock = threading.Lock()
        self.changed = threading.Event()

    def append(self, destination: bytearray, chunk: bytes) -> bool:
        with self.lock:
            remaining = max(self.maximum_bytes - self.total_bytes, 0)
            accepted = min(remaining, len(chunk))
            if accepted:
                destination.extend(chunk[:accepted])
                self.total_bytes += accepted
            if accepted != len(chunk):
                self.overflowed = True
            self.changed.set()
            return not self.overflowed

    def fail_read(self) -> None:
        with self.lock:
            self.read_failed = True
            self.changed.set()


def _read_stream(stream: BinaryIO, destination: bytearray, state: _OutputState) -> None:
    try:
        while True:
            chunk = stream.read(_READ_CHUNK_BYTES)
            if not chunk:
                return
            if not state.append(destination, chunk):
                return
    except (OSError, ValueError):
        state.fail_read()


if os.name == "nt":
    from ctypes import wintypes

    class _JobBasicLimitInformation(ctypes.Structure):
        _fields_ = [
            ("PerProcessUserTimeLimit", ctypes.c_longlong),
            ("PerJobUserTimeLimit", ctypes.c_longlong),
            ("LimitFlags", wintypes.DWORD),
            ("MinimumWorkingSetSize", ctypes.c_size_t),
            ("MaximumWorkingSetSize", ctypes.c_size_t),
            ("ActiveProcessLimit", wintypes.DWORD),
            ("Affinity", ctypes.c_size_t),
            ("PriorityClass", wintypes.DWORD),
            ("SchedulingClass", wintypes.DWORD),
        ]


    class _IoCounters(ctypes.Structure):
        _fields_ = [
            ("ReadOperationCount", ctypes.c_ulonglong),
            ("WriteOperationCount", ctypes.c_ulonglong),
            ("OtherOperationCount", ctypes.c_ulonglong),
            ("ReadTransferCount", ctypes.c_ulonglong),
            ("WriteTransferCount", ctypes.c_ulonglong),
            ("OtherTransferCount", ctypes.c_ulonglong),
        ]


    class _JobExtendedLimitInformation(ctypes.Structure):
        _fields_ = [
            ("BasicLimitInformation", _JobBasicLimitInformation),
            ("IoInfo", _IoCounters),
            ("ProcessMemoryLimit", ctypes.c_size_t),
            ("JobMemoryLimit", ctypes.c_size_t),
            ("PeakProcessMemoryUsed", ctypes.c_size_t),
            ("PeakJobMemoryUsed", ctypes.c_size_t),
        ]


    class _JobBasicAccountingInformation(ctypes.Structure):
        _fields_ = [
            ("TotalUserTime", ctypes.c_longlong),
            ("TotalKernelTime", ctypes.c_longlong),
            ("ThisPeriodTotalUserTime", ctypes.c_longlong),
            ("ThisPeriodTotalKernelTime", ctypes.c_longlong),
            ("TotalPageFaultCount", wintypes.DWORD),
            ("TotalProcesses", wintypes.DWORD),
            ("ActiveProcesses", wintypes.DWORD),
            ("TotalTerminatedProcesses", wintypes.DWORD),
        ]


    _KERNEL32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _KERNEL32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    _KERNEL32.CreateJobObjectW.restype = wintypes.HANDLE
    _KERNEL32.SetInformationJobObject.argtypes = [
        wintypes.HANDLE,
        ctypes.c_int,
        ctypes.c_void_p,
        wintypes.DWORD,
    ]
    _KERNEL32.SetInformationJobObject.restype = wintypes.BOOL
    _KERNEL32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    _KERNEL32.AssignProcessToJobObject.restype = wintypes.BOOL
    _KERNEL32.QueryInformationJobObject.argtypes = [
        wintypes.HANDLE,
        ctypes.c_int,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.c_void_p,
    ]
    _KERNEL32.QueryInformationJobObject.restype = wintypes.BOOL
    _KERNEL32.TerminateJobObject.argtypes = [wintypes.HANDLE, wintypes.UINT]
    _KERNEL32.TerminateJobObject.restype = wintypes.BOOL
    _KERNEL32.CloseHandle.argtypes = [wintypes.HANDLE]
    _KERNEL32.CloseHandle.restype = wintypes.BOOL


class _ProcessContainment:
    def __init__(self) -> None:
        self.process: subprocess.Popen[bytes] | None = None
        self.handle: int | None = None
        if os.name == "nt":
            handle = _KERNEL32.CreateJobObjectW(None, None)
            if not handle:
                raise BoundedProcessError("bounded process containment could not be created")
            self.handle = int(handle)
            information = _JobExtendedLimitInformation()
            information.BasicLimitInformation.LimitFlags = 0x00002000
            if not _KERNEL32.SetInformationJobObject(
                handle,
                9,
                ctypes.byref(information),
                ctypes.sizeof(information),
            ):
                self.close()
                raise BoundedProcessError("bounded process containment could not be configured")

    def start_options(self) -> dict[str, int | bool]:
        if os.name == "nt":
            return {"creationflags": subprocess.CREATE_NO_WINDOW}
        return {"start_new_session": True}

    def assign(self, process: subprocess.Popen[bytes]) -> None:
        self.process = process
        if os.name == "nt":
            if self.handle is None or not _KERNEL32.AssignProcessToJobObject(
                wintypes.HANDLE(self.handle),
                wintypes.HANDLE(process._handle),  # type: ignore[attr-defined]
            ):
                raise BoundedProcessError("bounded process containment assignment failed")

    def _active_processes(self) -> int:
        if os.name != "nt" or self.handle is None:
            return 0
        information = _JobBasicAccountingInformation()
        if not _KERNEL32.QueryInformationJobObject(
            wintypes.HANDLE(self.handle),
            1,
            ctypes.byref(information),
            ctypes.sizeof(information),
            None,
        ):
            raise BoundedProcessError("bounded process containment query failed")
        return int(information.ActiveProcesses)

    def terminate_and_close(self, timeout_seconds: float) -> bool:
        empty = False
        try:
            if os.name == "nt":
                if self.handle is None:
                    return False
                _KERNEL32.TerminateJobObject(wintypes.HANDLE(self.handle), 0xE0000001)
                deadline = time.monotonic() + timeout_seconds
                while time.monotonic() < deadline:
                    try:
                        if self._active_processes() == 0:
                            empty = True
                            break
                    except BoundedProcessError:
                        break
                    time.sleep(0.005)
                return empty

            process = self.process
            if process is None:
                return False
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                return True
            except OSError:
                return False
            deadline = time.monotonic() + timeout_seconds
            while time.monotonic() < deadline:
                try:
                    os.killpg(process.pid, 0)
                except ProcessLookupError:
                    return True
                except PermissionError:
                    return False
                time.sleep(0.005)
            return False
        finally:
            self.close()

    def close(self) -> None:
        if os.name == "nt" and self.handle is not None:
            _KERNEL32.CloseHandle(wintypes.HANDLE(self.handle))
            self.handle = None


def _stop_unreleased_supervisor(process: subprocess.Popen[bytes]) -> None:
    if process.stdin is not None:
        try:
            process.stdin.close()
        except OSError:
            pass
    try:
        process.wait(timeout=0.5)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        process.kill()
        process.wait(timeout=0.5)
    except (OSError, subprocess.TimeoutExpired):
        raise BoundedProcessError("blocked process supervisor could not be stopped") from None


def run_bounded_process(
    argv: Sequence[str],
    *,
    cwd: Path,
    maximum_output_bytes: int,
    timeout_seconds: float,
) -> BoundedProcessResult:
    if not argv or any(not isinstance(value, str) or "\0" in value for value in argv):
        raise ValueError("bounded process argv must contain only NUL-free strings")
    if maximum_output_bytes <= 0 or timeout_seconds <= 0:
        raise ValueError("bounded process limits must be positive")

    supervisor = Path(__file__).with_name("bounded_process_supervisor.py")
    containment = _ProcessContainment()
    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            [sys.executable, str(supervisor), "--", *argv],
            cwd=cwd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            shell=False,
            bufsize=0,
            **containment.start_options(),
        )
        try:
            containment.assign(process)
        except BaseException:
            _stop_unreleased_supervisor(process)
            raise

        if process.stdout is None or process.stderr is None or process.stdin is None:
            raise BoundedProcessError("bounded process pipes were not created")

        state = _OutputState(maximum_output_bytes)
        readers = [
            threading.Thread(
                target=_read_stream,
                args=(process.stdout, state.stdout, state),
                daemon=True,
            ),
            threading.Thread(
                target=_read_stream,
                args=(process.stderr, state.stderr, state),
                daemon=True,
            ),
        ]
        for reader in readers:
            reader.start()

        process.stdin.write(b"G")
        process.stdin.flush()
        process.stdin.close()

        started_at = time.monotonic()
        exited_at: float | None = None
        failure: str | None = None
        while True:
            with state.lock:
                overflowed = state.overflowed
                read_failed = state.read_failed
            if overflowed:
                failure = "pinned Android analyzer exceeded its output limit"
                break
            if read_failed:
                failure = "pinned Android analyzer output could not be read"
                break
            now = time.monotonic()
            returncode = process.poll()
            if returncode is not None and not any(reader.is_alive() for reader in readers):
                break
            if returncode is not None:
                if exited_at is None:
                    exited_at = now
                elif now - exited_at >= _POST_EXIT_DRAIN_SECONDS:
                    failure = "pinned Android analyzer output drain did not complete"
                    break
            if now - started_at >= timeout_seconds:
                failure = "pinned Android analyzer exceeded its timeout"
                break
            state.changed.wait(0.01)
            state.changed.clear()

        tree_gone = containment.terminate_and_close(_TERMINATION_SECONDS)
        containment = None  # type: ignore[assignment]
        try:
            process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            tree_gone = False

        drain_deadline = time.monotonic() + 0.5
        for reader in readers:
            reader.join(max(drain_deadline - time.monotonic(), 0.0))
        if any(reader.is_alive() for reader in readers):
            tree_gone = False
        process.stdout.close()
        process.stderr.close()

        if not tree_gone:
            raise BoundedProcessError("pinned Android analyzer process tree did not terminate safely")
        if failure is not None:
            raise BoundedProcessError(failure)
        if process.returncode is None:
            raise BoundedProcessError("pinned Android analyzer exit status is unavailable")
        with state.lock:
            return BoundedProcessResult(
                stdout=bytes(state.stdout),
                stderr=bytes(state.stderr),
                returncode=process.returncode,
            )
    finally:
        if containment is not None:
            containment.close()
        if process is not None:
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream is not None:
                    try:
                        stream.close()
                    except OSError:
                        pass
