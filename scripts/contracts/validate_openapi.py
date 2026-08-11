from __future__ import annotations

import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from scripts.contracts.contract_validation import (  # noqa: E402
    ContractValidationError,
    validate_all,
)


def main() -> int:
    try:
        route_count, fixture_count = validate_all()
    except ContractValidationError as exc:
        print(f"TL-R0-002 contract validation FAILED: {exc}", file=sys.stderr)
        return 1
    print(
        "TL-R0-002 contract validation PASS: "
        f"{route_count} effective routes, {fixture_count} closed fixtures, 2 expected-red owners"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
