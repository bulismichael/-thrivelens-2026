# Performance and resource budgets

All targets are provisional until measured on a recorded environment. A target is not a result.

| Concern | Provisional target | R0 measurement plan | Current result |
|---|---:|---|---|
| Minimum Android baseline | Android 10+, 4 GB memory | Human-selected physical device protocol | PENDING |
| Mobile cold start | <=3 seconds | Ten cold starts on selected reference device | PENDING |
| Ordinary interaction | Device refresh rate; no persistent jank | Flutter frame profile for system status and later flows | PENDING |
| Non-AI API p95 | <=500 ms | Fixed request count/concurrency against real local PostgreSQL, confidence interval recorded | PENDING |
| Assistant first useful content | <=4 seconds healthy provider | R1+ provider test | NOT APPLICABLE R0 |
| Assistant complete answer | <=20 seconds | R1+ provider test | NOT APPLICABLE R0 |
| Meal quality feedback | <=1 second on-device or <=3 seconds server-side | R2 evaluation | NOT APPLICABLE R0 |
| Meal candidate result | <=12 seconds server-side | R2 evaluation | NOT APPLICABLE R0 |
| Pose processing | >=15 FPS; 20 target | R3 physical-device protocol | NOT APPLICABLE R0 |
| Offline route recovery | No lost accepted point after process restart | R3 deterministic recovery test | NOT APPLICABLE R0 |
| Tier 1 CI | <10 minutes | Timed sequential offline report | PENDING |
| Tier 2 integration | <30 minutes | Timed PostgreSQL/client/Flutter report | PENDING |

## Host/resource budget

- User hard ceiling: aggregate ThriveLens-attributable logical footprint must remain strictly below 18 GB.
- Engineering target: <=13.5 GB, preserving at least 4.5 GB headroom.
- Warning: 75% (13.5 GB). All installs/builds hard-stop at 85% (15.3 GB) until a reviewed configuration decision changes the budget. Absolute cap failure: `>=18 GB`.
- Aggregate roots: repository plus the configured `%LOCALAPPDATA%\ThriveLens` root containing toolchains, caches, worktrees, and local database data. Any later WSL data path must be added before use.
- No multi-gigabyte model checkpoint in bootstrap or ordinary CI.
- Local phases are sequential: tests; database/integration; database stopped; Flutter analysis/build; runtime proof. Do not run emulator, database, Flutter build, and web build concurrently.
- Current host: 7.87 GB RAM with observed free memory below 1 GB. Installation and Android build preflight must define and enforce a safer free-memory floor before execution.

Every performance report records commit, tool/data version, machine/device, OS, network, database/runtime, request/load shape, warm-up, p50/p95/p99, confidence interval method, failures, duration, peak memory where available, artifact sizes, and aggregate footprint.

Targets change only through an entry in `docs/architecture/DECISION_LOG.md` with measured evidence and rollback impact.
