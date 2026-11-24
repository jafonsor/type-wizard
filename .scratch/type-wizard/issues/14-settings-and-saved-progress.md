# 14: Settings and saved progress

**What to build:** The complete settings schema (spec section 11) with defaults, minimums and maximums, persisted, editable on the Settings page, plus the saved progress (Total Points, Streak, Bonus) shown on the Start page and resettable (spec sections 8 and 12).

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 13

**Status:** done

- [x] Every setting in spec section 11 exists with default, min and max; controls clamp while editing
- [x] Stored out-of-range values are clamped on load; missing or wrong-typed values fall back to the default; cross-field rules clamp the dependent field
- [x] Settings are stored as versioned JSON and written on every change; a version mismatch migrates or falls back to defaults
- [x] Each group has a reset button, plus Reset all, with no confirmation; saved progress is untouched by them
- [x] Saved progress is stored separately; the Start page shows Total Points, Streak and Bonus
- [x] Reset progress sits in its own section and needs a second click
- [x] Storage failure (blocked or private window) leaves the game working with defaults and in-memory state
- [x] Pure tests cover clamping, cross-field rules and codec round-trip

## Answer

Gates (AGENTS.md names none): `nix build .#haskell-nix --cores 4 -L` with no `warning` lines for the new modules; `nix build .#checks.aarch64-darwin.common-test --cores 4 -L` (56 cases, 0 failures); a headless-Chrome script against the exported site.

Criteria and how each was proved:

1. Every field of spec section 11 exists (21 numbers, 14 colours, in `Game.Settings.fields`) with default, min, max. Pure test: defaults inside bounds, field counts, spec defaults. Browser: 21 number and 14 colour inputs on the page; typing 99 into Starting Lives shows 10 in the box at once; typing 0.1 into Grace Period gives 0.5 on commit, and typing 0.8 is not cut short.
2. Pure tests: out-of-range stored value clamps, missing and wrong-typed values (string, bool, null, fractional in a whole field, invalid colour) fall back to the field default, `intervalEnd` and `lastTier` cross-field clamps (stored and edited). Browser: garbage and out-of-range stored settings load as default, clamp, default.
3. Pure tests: `version: 1` in the JSON, round trip, version 0, 2 and non-numeric give defaults, `migrateWith` walks steps (none exist yet). Browser: every edit is in `localStorage` immediately; a stored version 2 loads defaults; settings survive a reload.
4. Pure tests: each group reset touches only its group, all resets give defaults. Browser: Reset Rules, Reset Spawning, Reset Colours leave other groups alone, Reset all restores defaults with no confirmation and the stored save is unchanged.
5. `typewizard.save` is its own key and codec (`Game.Save`). Browser: the Start page shows values stored under that key after a reload.
6. Browser: "Reset progress" in its own "Saved progress" block; the first click only changes the label to "Really reset?" (storage unchanged); the second clears all three in storage and on Start; settings are untouched.
7. Browser: with `window.localStorage` replaced by a getter that throws `SecurityError` before load, the app renders, the Settings page shows defaults, edits and resets work in memory across page switches, and Reset progress does not crash. Not tested in a real private window.
8. `common-test` (HUnit): clamping, cross-field rules, Settings and Save round trips, garbage handling.

Decisions not in the spec:

- **Modules.** `Game.Settings` and `Game.Save` in `common` (pure, `aeson`, `scientific`); `Frontend.Storage` is the Haskell side of the seam and `static/src/js/storage.js` (`window.TypeWizardStorage`, try/catch around every access, loaded in the head) is the JS side. The storage functions are `JSM`, not bare `IO`, because the calls go through the JS context.
- **Field table.** `Game.Settings.fields` (key, label, group, and a `Num` or `Colour` spec with bounds as functions of the record, so the cross-field rules are bounds). Page, codec and resets are all driven by it. The table's order matters: a field comes after the one its bounds read.
- **JSON.** Flat object, one key per field (the field name, e.g. `startingLives`), plus `version`. Whole-number fields are stored as integers; a fractional number in one is wrong-typed and falls back to the default. Colours are `#rrggbb`, normalised to lower case; anything else is wrong-typed. A version other than 1 migrates through `migrations` (empty today) or gives the defaults.
- **Save.** `{version, totalPoints, streak, bonus}`. Negative, fractional, missing or wrong-typed fields become 0; a version mismatch gives the empty save. Bonus is stored as the spec says and is not reconciled with Streak on load: it depends on the group size in force when each group completed, and that is a setting that may have changed.
- **Colour fields** are `input type=color` (always `#rrggbb`).
- **Number controls** update the record on every parsable keystroke (so the stored value is always in range). A value above the maximum is rewritten in the box at once; one below the minimum is rewritten when the edit is committed (change event), so typing `0.8` with a minimum of 0.5 is not cut short at `0`. Changes from elsewhere (resets, cross-field clamps) are written into the boxes.
- **Wiring.** `pageSwitch` holds `Dynamic Settings` and `Dynamic Save` above the `dyn`; pages return `PageOut` (page request, settings edit, save edit). Storage is read once in `prerender` after postBuild (the exported page shows defaults until then) and written from `updated` of both Dynamics, so the load itself is written back normalised. Nothing writes the save yet except Reset progress; later tickets send `Save -> Save` edits the same way.
- **Test library.** HUnit (what `type-solution` uses; cached in the Nix set), plain `exitcode-stdio-1.0`. The test run is the flake check `common-test`.
