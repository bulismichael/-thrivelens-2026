# Scope and non-goals

## Product scope by capability

- Adult identity, consent, privacy-aware profile, preferences, allergies, accessibility, equipment, schedule, notification, and quiet-hour controls.
- Evidence approval and a provider-neutral assistant pipeline with risk classification, retrieval, claim verification, citations, safety validation, and abstention.
- Permanent manual meal composition, user-selected portions, versioned food-composition provenance, and deterministic nutrition summaries.
- Optional meal-image quality and candidate assistance that cannot affect nutrition before confirmation.
- Safe goal categories and deterministic weekly plans with explicit constraint conflicts.
- Activities, workouts, privacy-preserving routes, approved nearby places, and optional fixture/device-evaluated pose support.
- Calm progress summaries plus export and deletion.
- Role-aware administration for implemented evidence, policy, evaluation, safety, audit, model, dataset, provider, support, and feature-flag workflows.
- No-paid-key demo mode and separately verified external-provider modes.

## Global non-goals

- Diagnosis, triage, treatment, prescribing, clinical-record interpretation, emergency response, or cure/prevention claims.
- Hidden-condition inference from messages, meals, pose, routes, wearables, or images.
- Exact image-derived portions, nutrients, or calories.
- Restrictive-eating coaching, appearance-based goals, shame, public ranking, body comparison, or punitive exercise/streaks.
- Production minor onboarding before named human approval.
- Invisible model/provider changes, unapproved evidence, unconsented training, advertising profiles, or sale of health/location data.
- Engagement-time optimization as the main product objective.

## R0 included

- Repository preservation, control plane, agent pool, pinned/reversible resource policy, and release evidence.
- Minimal FastAPI modular monolith with structured errors and privacy-safe logs.
- Real PostgreSQL cluster, baseline migration metadata, separate migration/runtime roles, and current-head readiness.
- Liveness, readiness, mobile system status, and version contracts.
- Generated Dart REST client.
- Initial Flutter design system and one polished system-status surface with success, degraded, unreachable, timeout, malformed, offline, retry, light/dark, text-scale, and reduced-motion states, automatically exercised as a phone viewport in installed Chrome.
- Sequential Windows commands, a minimal PostgreSQL Compose contract for compatible CI/developer hosts, CI gates, and an 18 GB aggregate resource ceiling.

## R0 explicitly excluded

- Accounts, OpenID Connect, onboarding, consent records, profiles, roles, user tables, or user data.
- Evidence corpus, assistant, urgent-support content, meals, nutrition, goals, plans, activities, progress, export, deletion, or administration web.
- Images, object storage, routes, maps, nearby places, PostGIS, pose, wearables, offline sync, or notifications.
- Model gateways, model/provider interfaces, checkpoints, datasets, vector search, Redis, workers, workflow engines, model registries, Kubernetes, Terraform, paid providers, or production hosting.
- iOS claims, the broader Android physical-device matrix, app-store signing, human approvals, and later-release scaffolding. R0 still requires an Android debug build and the real heartbeat on either an emulator/capable runner or an attached Android device; Chrome phone-viewport proof is automatic interim evidence, not a replacement.

Later release code may not be introduced merely because it appears in the final product scope. Its use case, data, threat, contract, fallback, and task must first become active.
