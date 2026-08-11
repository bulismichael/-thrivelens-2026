# ThriveLens delivery contract

This repository is governed by `ThriveLens_GPT-5.6_Sol_Multi-Agent_Orchestrator_Prompt.md`. Be precise, preserve granular context, explore advanced ideas only when they support the active release, and never widen scope away from the current vertical slice.

## Product boundary

- ThriveLens is general wellness and health education, not diagnosis, treatment, prescribing, emergency response, or clinical decision support.
- Production-facing behavior is adult-only by default. Minor onboarding remains disabled until humans approve jurisdiction, consent, and content policy.
- Keep user confirmation between image/model suggestions and nutrition calculations.
- Preserve manual fallbacks for meals, evidence answers, plans, routes, and providers.
- Never invent legal, clinical, nutrition, exercise, language, dataset, device, provider, or security approval.
- Demo, test, sandbox, and real-provider modes must remain visibly distinct.

## Resume order

Read before changing code:

1. `docs/program/PROJECT_STATE.md`
2. `docs/program/TASK_GRAPH.yaml`
3. `docs/program/FEATURE_REGISTRY.yaml`
4. `docs/program/DECISIONS_REQUIRED.md`
5. The active release brief and relevant decisions
6. The tests and frozen contracts for the next `READY` task

If a control file does not exist yet, the active task is Wave 1 control-plane synthesis. Do not invent later-release state.

## Delivery protocol

- Work only from an atomic task card with explicit owned and forbidden paths.
- Freeze use cases, domain results, OpenAPI schemas, error codes, authorization, and idempotency before parallel frontend/backend work.
- Use failing tests first for deterministic policy, authorization, privacy, calculation, sync, API, and UI state logic.
- Use evaluation-driven development for learned systems; never substitute public claims for ThriveLens evaluation.
- One write-heavy task per branch/worktree. The integration branch owns shared contracts, lockfiles, migration heads, and integration.
- Preserve user changes. Never force-push, rewrite shared history, auto-deploy, spend money, or delete remote resources.
- Review order: implementer, quality, security/privacy when applicable, UX when user-facing, integration, then cross-module tests.
- Advance feature/provider states only when their recorded evidence exists.

## Resource ceiling

- The complete ThriveLens delivery footprint added for this project must remain below 18 GB.
- Run `pwsh -File scripts/check_resource_budget.ps1` before and after dependency installation or large builds.
- Do not download model checkpoints during ordinary bootstrap or CI.
- Prefer deterministic fixtures, portable/minimal services, bounded caches, and sequential local builds on this 8 GB host.
- Do not run an Android emulator, database, Flutter build, and web build concurrently on this host.
- Stop before an install/build projected to breach the cap; report the measured size and the smallest alternative.
- Keep attributable SDKs, caches, task worktrees, and local data under the aggregate-counted `%LOCALAPPDATA%\ThriveLens` root because the synced repository path contains spaces.

## Quality and privacy

- Never log messages, images, tokens, exact routes, secrets, or raw pose frames.
- Synthetic test/demo data must be labelled and disposable.
- Add every persisted field to `docs/privacy/DATA_INVENTORY.md` before implementation.
- Block unsafe demo configuration in production mode.
- Treat critical security findings and failing safety tests as integration blockers.
- Use generated API clients as transport source of truth.

## Status handoff

After every meaningful integration block update `PROJECT_STATE.md`, `TASK_GRAPH.yaml`, `FEATURE_REGISTRY.yaml`, evidence paths, risks, and the stable checkpoint. Return the concise `THRIVELENS DELIVERY STATUS` format from the execution brief.
