# ThriveLens design system

Status: provisional engineering system; human brand approval pending

## Visual thesis

`Quiet Aperture`: a warm, luminous editorial field with decisive mineral-ink typography and one restrained focus ring moving from uncertainty to clarity. It feels calm, premium, science-aware, inclusive, and non-clinical through composition, spacing, and contrast rather than glass, gradients, card density, or stock imagery.

## Content plan

1. Identity and truthful mode.
2. One dominant current state or next action.
3. Plain divider-separated evidence/support rows.
4. One primary action, freshness, then progressive detail.

## Interaction thesis

- A 160 ms state transition changes the aperture glyph and summary together without moving focus.
- Supporting rows resolve in logical order with a subtle bounded stagger; reduced motion updates immediately.
- Retry preserves geometry, disables duplicate action, fences older responses, and replaces existing content with checking state.

## Provisional semantic tokens

Exact values must pass automated contrast tests and can change without altering semantic names.

| Role | Light | Dark | Use |
|---|---|---|---|
| canvas | `#F6F4EF` | `#0F1715` | Primary field |
| surface | `#FFFFFF` | `#17221F` | Necessary raised/interactive surface only |
| ink | `#17211F` | `#F3F0E8` | Primary text |
| ink-muted | `#52615D` | `#B8C1BC` | Secondary text after contrast verification |
| action | `#006C5F` | `#62D5C2` | One primary accent |
| on-action | `#FFFFFF` | `#10201D` | Action content |
| success | `#226B45` | `#78D89B` | With icon, shape, and text |
| warning | `#8A4B00` | `#F0B86B` | With icon, shape, and text |
| error | `#A23A32` | `#FF9A90` | With icon, shape, and text |
| unknown | `#5F5B77` | `#C9C2E8` | With icon, shape, and text |
| divider | `#D5DAD6` | `#34433E` | Structure, never sole state signal |

Do not use decorative gradients behind routine application UI. Blur/transparency must never sit behind text. A lens motif is one solid concentric/partial focus ring around the dominant state or active capture region and is excluded from semantics.

## Type, spacing, shape, elevation

- Platform/system type in R0; at most two approved families later.
- Scale: display 32/38, title 24/30, body 16/24, label 14/20 logical pixels/line heights.
- Four-point base; primary spacing 8, 12, 16, 24, 32, 48.
- Phone horizontal inset about 24; bounded readable tablet width; start-aligned scrollable content.
- Moderate radii only when the shape is interactive; no decorative pill soup.
- Minimal elevation. Whitespace, rules, crop, scale, and hierarchy carry structure.
- Icons are purposeful, paired with text for state, and use consistent optical size/stroke. No ECG, cross, or clinical-monitor motifs.

## Motion and haptics

- Standard state motion 140-180 ms, restrained easing, no bounce, parallax, shimmer, continuous pulse, or ornamental loop.
- Reduced-motion mode eliminates transitions and uses static `Checking` copy/glyph.
- R0 has no haptic flourish. Later haptics confirm direct user actions, never health judgment, warning severity, or engagement pressure.

## R0 state copy

| State | Summary | App service | Database | Action |
|---|---|---|---|---|
| Checking | `Checking ThriveLens` - `Checking the app service and database.` | `Checking` | `Waiting` | `Checking...` disabled |
| Ready | `Development services are ready` - `The app service and database checks passed.` | `Online` | `Ready` | `Check again` |
| Database not ready | `Database readiness could not be confirmed` - `The app service is online, but its database check did not pass.` | `Online` | `Not ready` - `The database is not ready for this build.` | `Try again` |
| Database unknown | `Database status is unknown` - `The database check did not finish.` | `Online` | `Unknown` | `Try again` |
| Service error | `The service needs attention` - `ThriveLens could not complete the check.` | `Error` | `Not checked` | `Try again` |
| Unreachable | `Can't reach ThriveLens` - `The app could not contact the service.` | `Not reached` | `Not checked` | `Try again` |
| Confirmed offline | `Your device is offline` - `Reconnect, then try again.` | `Not checked` | `Not checked` | `Try again` |
| Timeout | `The check took too long` - `The current status is unknown.` | `No response` | `Not checked` | `Try again` |
| Invalid response | `Status unavailable` - `ThriveLens returned a response the app could not use.` | `Unknown` | `Unknown` | `Try again` |

Only affirmative current service and database evidence produces ready. A timeout/missing result is unknown, not down. Offline copy requires explicit device-connectivity evidence. Version failure is non-blocking. Raw transport errors never render.

## Accessibility gates

- WCAG 2.2 AA minimum: 4.5:1 ordinary text; 3:1 large text and UI/focus. Aim 7:1 for primary body text.
- Test 100%, 130%, and 200% text plus about 30% pseudo-localized expansion; no clipping at 320 logical-pixel width.
- Minimum 48x48 targets and visible unobscured focus.
- Focus/semantic order: title, summary, app row, database row, retry, build details.
- One coherent semantic node per status row; one polite live announcement for the final summary.
- Enter/Space activate controls; status never relies on color; decorative aperture excluded from semantics.
- Light, dark, high-contrast assertions, reduced motion, keyboard, and screen-reader checks are release gates.

## Data visualisation and feedback rules

Charts use semantic tokens, direct labels, patterns/shape where needed, text summaries and accessible tables. Axes/ranges are honest; trends never shame or imply diagnosis. Confidence components state source, range, method, assumptions, limitations, and manual override. Loading, empty, offline, permission-denied, unavailable, conflict, and error are designed states rather than generic snackbars.
