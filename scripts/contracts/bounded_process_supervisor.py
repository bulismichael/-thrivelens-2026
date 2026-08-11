from __future__ import annotations

import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 4 or sys.argv[1] != "--":
        return 125
    release = sys.stdin.buffer.read(1)
    if release != b"G":
        return 125
    target = sys.argv[2:]
    try:
        process = subprocess.Popen(target, shell=False)
    except OSError:
        return 126
    return process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
