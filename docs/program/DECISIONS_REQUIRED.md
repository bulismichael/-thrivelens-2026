# Human decisions required

No entry is approved unless a named human records approval in `HUMAN_APPROVALS.md` with date and evidence. Safe defaults keep independent engineering moving but do not grant production authority.

| ID | Decision | Risk while missing | Safest reversible development default | Blocks | Status |
|---|---|---|---|---|---|
| TL-D-001 | First pilot jurisdiction | Wrong emergency, privacy, consent, or language assumptions | Leave jurisdiction unset; disable jurisdiction-specific urgent support | Pilot configuration and production enablement | PENDING |
| TL-D-002 | Adult-only policy and any future minor policy | Unsafe or unlawful minor processing | Adult-only flag hard-on; under-18 production onboarding hard-off; test safeguards only | Production onboarding policy | PENDING |
| TL-D-003 | Named nutrition reviewer | Unsafe food/portion/plan content | Keep R1 nutrition development labelled synthetic/general and not domain-reviewed | Nutrition domain state and pilot | PENDING |
| TL-D-004 | Named exercise reviewer and R3 exercise selection | Unsafe exercise definitions or pose feedback | No production exercise/pose promotion; choose no exercises yet | Exercise/pose domain state | PENDING |
| TL-D-005 | Named privacy/legal reviewer | Unapproved data basis, retention, transfer, or deletion behavior | Persist no user data in R0; later production paths remain disabled | Production data processing and pilot | PENDING |
| TL-D-006 | Named Sesotho reviewer | Incorrect health-critical translation | No production Sesotho health-critical content | LANGUAGE_REVIEWED and production Sesotho | PENDING |
| TL-D-007 | Brand, palette, type, icon, and Lens terminology | Public identity may be inaccessible or culturally unsuitable | Use replaceable Quiet Aperture tokens, platform type, and plain text wordmark | Public brand approval | PENDING |
| TL-D-008 | Approved evidence sources and reviewers | Unsupported or outdated wellness claims | Synthetic/approved-development corpus only; abstain without approved evidence | Production grounded answers | PENDING |
| TL-D-009 | Production retention and backup matrix | Silent over-retention or premature deletion | Synthetic/disposable local data; no production start | Production storage, logs, backup, deletion | PENDING |
| TL-D-010 | Hosting provider, region, budget, and network boundary | Cost, residency, availability, and security mismatch | Local demo only; no deployment or spend | Reference production deployment | PENDING |
| TL-D-011 | External provider/model data handling | Provider retention/training mismatch | Deterministic fakes and manual fallbacks; no paid keys | Real-provider production configuration | PENDING |
| TL-D-012 | Model and dataset licences | Unlicensed artifacts or incompatible intended use | No model/dataset download in ordinary bootstrap; mark research pending | Real-model evaluation/promotion | PENDING |
| TL-D-013 | Physical-device matrix | Unmeasured camera, thermal, battery, route, or pose behavior | Widget/browser/build evidence only; device states pending | PHYSICAL_DEVICE_VERIFIED | PENDING |
| TL-D-014 | Android/iOS store accounts and signing | Cannot ship trusted store artifacts | Local/debug builds; no store submission | App-store release | PENDING |
| TL-D-015 | Production credentials and secret management | Unsafe demo secrets or unavailable integrations | Production mode rejects demo/default values; no production configuration | Production verification | PENDING |
| TL-D-016 | Pilot population, monitoring, and support ownership | Unbounded or unsupported pilot | No pilot enrollment; prepare R6 scripts only | PILOT_READY and launch | PENDING |
| TL-D-017 | Security risk acceptance | Residual risks lack accountable owner | Resolve automatic criticals; keep human acceptance pending | Pilot/production authorization | PENDING |

## Near-term manual intervention

R0 can continue through contracts and installation-free tests. The following may require the user when reached:

1. Accept Android SDK licence terms after exact packages and projected size are shown.
2. Close memory-heavy applications before Flutter/Android installation or builds; current free RAM has repeatedly fallen below 1 GB.
3. Provide a physical Android device with USB debugging, or enable supported virtualization and approve emulator installation, for device-only evidence.
4. Approve any privileged firewall, driver, BIOS/firmware, or system-package change if it becomes necessary. R0 defaults avoid these changes.

No paid key, deployment, public repository, or production credential is required for R0.
