# 14: Settings and saved progress

**What to build:** The complete settings schema (spec section 11) with defaults, minimums and maximums, persisted, editable on the Settings page, plus the saved progress (Total Points, Streak, Bonus) shown on the Start page and resettable (spec sections 8 and 12).

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 13

**Status:** ready-for-agent

- [ ] Every setting in spec section 11 exists with default, min and max; controls clamp while editing
- [ ] Stored out-of-range values are clamped on load; missing or wrong-typed values fall back to the default; cross-field rules clamp the dependent field
- [ ] Settings are stored as versioned JSON and written on every change; a version mismatch migrates or falls back to defaults
- [ ] Each group has a reset button, plus Reset all, with no confirmation; saved progress is untouched by them
- [ ] Saved progress is stored separately; the Start page shows Total Points, Streak and Bonus
- [ ] Reset progress sits in its own section and needs a second click
- [ ] Storage failure (blocked or private window) leaves the game working with defaults and in-memory state
- [ ] Pure tests cover clamping, cross-field rules and codec round-trip
