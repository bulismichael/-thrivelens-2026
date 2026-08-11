# ThriveLens information architecture

## Mobile destinations after their journeys exist

| Destination | Responsibility | Key accessibility/clarity rule |
|---|---|---|
| Today | Daily orientation, one primary next action, plan context, evidence-backed insight, recent summary | No unrelated dashboard-card mosaic; question flow can begin here |
| Lens | Meal capture/review, manual entry, candidates, correction, portions, source/uncertainty | Semantic label `Lens, meal capture and review`; manual entry equally discoverable |
| Plan | Goals, weekly timeline, conflicts, rescheduling, reminders, quiet hours | Drag always has explicit keyboard/accessible alternative |
| Progress | Text-first trends for variety, completion, movement, routes, workouts | Every chart has summary/table; no ranking, shame, streak loss, or body comparison |
| Profile | Preferences, allergies, equipment/accessibility, consent/services, privacy, retention, export/deletion, evidence policy, support | High-risk privacy actions are explicit, confirmed, and understandable |

Compact ordinary-text screens use five labelled destinations; large text switches to a labelled drawer when labels would clip; tablet uses a labelled navigation rail. Selection uses shape, weight, label, semantics, and color rather than color alone. All targets are at least 48 logical pixels.

The human brand/usability decision may rename visible `Lens` to `Meal Lens` or clearer language. The route/destination responsibility remains stable.

## R0 information architecture

R0 opens directly to `System status`. It shows no inactive five-destination navigation and no placeholder wellness surface. In the eventual product, system status moves under `Profile > About and support > System status`.

R0 order:

1. Plain provisional `ThriveLens` text identity.
2. Trusted build-mode label from local configuration.
3. `System status` route title.
4. One dominant shaped/icon/text summary and consequence sentence.
5. Divider-separated `App service` and `Database` rows.
6. One `Try again`/`Check again` action.
7. `Last checked` freshness text.
8. Collapsed bounded build details.

No endpoint URL, host, database identifier, raw response, token, stack, correlation identifier, technical dashboard, hero, health imagery, or wellness disclaimer appears on this operational screen.

## Administration information architecture when R1 introduces it

Role-aware navigation groups work by decision, not by database table: evidence review/provenance, policy/effective versions, safety triage, audit explorer, feature changes with preview/confirmation, model/dataset cards and evaluations when implemented, support configuration, and system/provider status. Every write is server-authorized, confirmed, and audited. R0 creates no admin web.
