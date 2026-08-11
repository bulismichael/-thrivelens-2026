# ThriveLens product charter

Status: active delivery authority subordinate to the root orchestrator prompt
Current release: R0 Foundation heartbeat

## Mission

ThriveLens is a mobile-first general-wellness and health-education product that gives adults three kinds of clarity:

- Visual clarity: meal candidates remain uncertain suggestions until the user confirms or corrects them.
- Evidence clarity: wellness information is grounded in approved sources, cited, verified, and able to abstain.
- Progress clarity: plans and trends are calm, useful, and free of shame, public ranking, punitive streak loss, and body comparison.

The integrated pilot candidate will include a polished Flutter application, a role-aware administration web application, a FastAPI/PostgreSQL backend, transparent manual and assisted meal workflows, safe plans, movement features, optional gated intelligence, privacy controls, no-paid-key demo operation, and truthful operating evidence.

## Intended-use boundary

ThriveLens is not a diagnostic, prescribing, treatment, emergency-response, or clinical decision-support system. It does not interpret clinical records, recommend prescription changes, infer hidden conditions, claim cures, represent image-derived portions as exact, or optimize minors for weight loss, calorie deficits, fasting, or body composition.

Production-facing functionality is adult-only by default. Under-18 onboarding remains hard-disabled behind a feature flag until named humans approve jurisdiction, guardian/consent rules, content policy, and domain safeguards. Development fixtures will still prove minor protections.

Jurisdiction-specific urgent-support content remains disabled until a named human approves the jurisdiction configuration. The product must not invent local services.

## Product principles

1. Manual completion remains available when a model, provider, camera, network, or permission fails.
2. Observation, suggestion, user confirmation, deterministic calculation, and execution are separate states.
3. Demo, test, sandbox, and real-provider modes are visibly and operationally distinct.
4. Privacy is a data-flow constraint: collect the minimum, inventory before persistence, and keep sensitive content out of ordinary logs.
5. Learned capabilities advance through measured evaluation and reversible feature flags, not claims or demos.
6. Accessibility, uncertainty, failure, offline, loading, and deletion are primary product states.
7. Engagement time is not the primary success metric.

## Pilot-candidate outcomes

A code-complete pilot candidate must demonstrate the core adult journeys end to end against real demo persistence, retain permanent manual fallbacks, pass the active automatic gates, expose no unresolved critical security finding, and keep every human-required approval visibly pending until recorded by its named approver.

Code completion never implies clinical, legal, privacy, language, physical-device, dataset, pilot, app-store, or production approval.

## Current delivery constraint

R0 proves only one real vertical path:

`Flutter system status -> generated Dart client -> FastAPI -> real PostgreSQL readiness`

R0 creates no identity, wellness, meal, route, pose, model, evidence, or admin-web workflow and persists no user data.
