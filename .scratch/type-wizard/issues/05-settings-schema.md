Type: grilling
Status: resolved
Blocked by: 04

# Settings schema

## Question

Define every setting as a typed field with a default, a min and a max, grouped for the settings page: starting Lives, Grace Period, Enemies per Tier (50), first and last Tier, Streak group size (10), spawn curve parameters, spawn radius, Enemy speed, Camera pan duration and margin, Shot and Plus Sign animation durations, colour per Tier and the Shot colour ramp.

Decide:

- The final list and the grouping on the page, using the rules from the game-rules ticket.
- The reset-to-defaults behaviour (one button; whether per group).
- How a settings change takes effect: immediately, or only from the next Round.
- Validation and what happens with invalid values or a stored value outside min and max.
- How the schema lives in the FRP network (one record of Dynamics or one Dynamic of a record), and the persistence key and versioning in `localStorage`.


## Answer

All confirmed by the user in grilling.

**Fields (default; min–max).** Colour defaults and Word placement go to the visual ticket; the schema fixes their types.

- Rules: starting Lives 3 (1–10); Grace Period 2 s (0.5–10); Enemies per Tier 50 (10–200); first Tier 3 (3–8); last Tier 8 (first Tier–8); Streak group size 10 (2–50). The Shot ramp always spans 10 groups, so it follows the group size.
- Spawning: intervalStart 3.0 s (0.5–10); intervalEnd 1.0 s (0.2–intervalStart); spawn radius beyond the default view 1.0 (0–5); Enemy speed 1.0 units/s (0.2–5).
- Camera: pan duration 0.4 s (0.1–2); margin 0.15 of view (0–0.4); ease-back duration 0.6 s (0.1–2).
- Animation: Shot duration 0.25 s (0.05–1); Plus Sign duration 0.6 s (0.1–2); Plus Sign spread 0.3 (0–1).
- Colours: one colour per Tier 3 to 8; Shot ramp start (blue) and end (red).
- Numeric defaults are placeholders, tunable in the visual ticket.

**Reset.** One button per group plus "Reset all", no confirmation. Total Points, Streak and Bonus are saved state, not settings, and are untouched.

**Effect.** Snapshot at Round start. The settings page is unreachable during a Round, so no mid-Round change exists.

**Validation.** Controls clamp while editing. Stored out-of-range values are clamped on load. Missing or wrong-typed values fall back to the field default. Cross-field rules clamp the dependent field (intervalEnd <= intervalStart, last Tier >= first Tier). Nothing is rejected or shown as an error.

**FRP and persistence.** One `Dynamic Settings` (a single record), written whole on change; field widgets use projections. `localStorage` key `typewizard.settings` holds JSON with `version: 1`. A version mismatch migrates if a migration exists, else falls back to defaults. Total Points, Streak and Bonus live under a separate key `typewizard.save`.

## Amendment (from the dictionary pipeline ticket)

Spawning group gains `Word lookahead`: default 10, min 0 (off), max 50.
