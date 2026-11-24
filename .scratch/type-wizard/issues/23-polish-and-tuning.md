# 23: Polish and tuning

**What to build:** The game is checked in a real browser and tuned (spec section 15).

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 20, 21, 22

**Status:** ready-for-agent

- [x] The manual browser checklist passes: resize, device pixel ratio change, canvas detach stops the loop, WebGL-unavailable message
- [x] Key presses with Ctrl, Cmd or Alt are ignored and not counted; other browser shortcuts such as quick find are checked and the result recorded
- [ ] Numeric defaults flagged as placeholders (spawn interval, speed) are tuned by play and updated in the settings and spec (MEASURED, VALUES LEFT FOR THE HUMAN TO TUNE: not ticked; nobody has played the game, so no value was changed)
- [x] A contrast pass confirms every colour on the dark background
- [x] The embedded word list is read back in the running page

## Answer

Status left at `ready-for-agent`: criterion 3 asks for values tuned by play, which nobody has done; it is recorded as measured, values left for the human to tune. The other four criteria hold.

Scripts (headless Chrome over CDP against the built page, 1200x800 or the sizes named, served from `scratchpad/site23`): `t23-browser.mjs` (modes `render`, `nowebgl-override`, `nowebgl-flag`, `keys`, `words`), `t23-lib.mjs`, `t23-bot.mjs`, `t23-contrast.mjs`, and the pure bot `t23sim/Bot.hs`. `t23-loop.sh` runs the five modes in order; three full runs are `t23run-1.txt`, `t23run-2.txt`, `t23run-3.txt`: 92 PASS, 0 FAIL each. No pixel-count thresholds and no sub-300 ms windows: pixel checks are single-pixel samples (or the max of a 5x5 window for the 0.08-unit dots), everything else reads the `?hook` state and `TypeWizardRenderer.stats`/`TypeWizardKeys.stats`.

### 1. Manual browser checklist (mode `render`, `nowebgl-*`)

- **Resize and DPR.** Six sizes in one Round: 800x600 at DPR 1, 1000x500 at 2, 640x480 at 1, 640x480 at 3 (DPR change alone), 1280x400 at 1, 400x800 at 2. Each: `canvas.width/height` = CSS size x DPR, the hook's `aspect` follows, the screenshot is device pixels, the Player is white 1.2 world units wide (white 4 px inside the edge, background 4 px outside, at the size's own pixels per unit), the dot grid keeps its 2-unit spacing (a dot at +2 units, none at (+1,+1)), the Round stays `Running`, `errors` 0.
- **Canvas detach stops the loop.** Menu: the canvas is gone, `stopped` = 1, `frames` and `draws` frozen over 1.5 s, the key shim detached (`active` 0), a letter on the Start page is not counted; a fresh Play gives `created` 2, `started` 2 and frames advance; the second Menu gives `stopped` 2 and frozen frames. Resizing on the Settings page is harmless.
- **WebGL unavailable.** Both ways (a `getContext` override before load, and Chrome `--disable-gpu --disable-3d-apis`): `getContext('webgl2')` is really null, the Game page shows `WebGL is not available in this browser, so the game cannot be drawn.` laid out on screen (800x552), no loop started (`started` 0, `frames` 0), no key shim attached, Menu still works.
- Console: no errors; only the dev server's `favicon.ico` 404 is logged.

### 2. Modifier keys and browser shortcuts (mode `keys`)

The rule lives in `static/src/js/keys.js` (`if (e.ctrlKey || e.metaKey || e.altKey) return;` before anything is reported), so the proof is a browser check, not a Haskell test. With the first letter of the closest Enemy's Word: Ctrl, Cmd, Alt, Ctrl+Alt, Ctrl+Shift, Cmd+Shift (each with and without `text`) give no Focus, no correct or wrong Keystroke, no Typo, `TypeWizardKeys.stats.sent` unchanged. Shift+letter is a normal Keystroke (positive control). While Focused (k = 1): modifier + a wrong letter is not a Typo, not a wrong Keystroke, not Locked; modifier + the correct next letter does not advance; Ctrl, Cmd or Alt + Tab does not reset the Word (and their default is not prevented). Controls: the same wrong letter without a modifier is a Typo (typos +1, wrong +1, Locked); plain Tab resets the Word with its default prevented. Mutation: with the modifier line deleted from the served `keys.js` the mode fails 16 checks (K1 to K9, K11, K12, K14), restored it passes.

Other browser shortcuts, result recorded: Ctrl+F, Ctrl+L, Cmd+K, Ctrl+/, Alt+', F3, F5, Backspace, Space are not prevented and change nothing in the game (F3, F5, Backspace, Space count as `events`, not Keystrokes). Plain `/` and `'` were **not** handled before this ticket: no `preventDefault`, so Firefox's quick find would have opened and taken the following letters out of the page. Chrome has no such shortcut, so it only shows that the event is not cancelled. Fix in `keys.js`: plain `/` and `'` get `preventDefault` and are still reported as `Other` (not Keystrokes, no Typo, no Lock; K10, K11, K14). Firefox itself was not available, so the Firefox behaviour is by its documented behaviour, not observed.

### 3. Numeric placeholders: measured, values left for the human to tune

Placeholders (ticket 05: "Numeric defaults are placeholders, tunable in the visual ticket"; spec section 16 item 10 names spawn interval and speed). All unchanged:

| Setting | Value | Settings (`Game.Settings.defaultSettings`) | Spec |
|---|---|---|---|
| `intervalStart` | 3.0 s (0.5 to 10) | `common/src/Game/Settings.hs` line 101 | section 11 "Spawning" |
| `intervalEnd` | 1.0 s (0.2 to `intervalStart`) | line 102 | section 11 |
| `enemySpeed` | 1.0 units/s (0.2 to 5) | line 104 | section 11 |
| `spawnRadius` | 1.0 (0 to 5) | line 103 | section 11, section 14 item 9 |
| `enemiesPerTier` | 50 | Settings.hs | section 4, 11 |
| `gracePeriod` / `startingLives` | 2 s / 3 | Settings.hs | section 11 |

Scripted bot (never mistypes; always attacks the closest Enemy; one key every 1/cps; one extra key interval of pause between Words; 60 Ticks/s; default settings; the embedded 400-word list; `t23sim/Bot.hs`, pure `step`, no browser). The outcome was identical for all 10 seeds because the bot clears one Enemy at a time, so only the Tier's Word lengths and the spawn timing matter:

| Typist | Round length | Kills | Lives lost | Tier at end | Spawned | Round Points | First Life lost |
|---|---|---|---|---|---|---|---|
| 4 chars/s | 606.6 s (10.1 min) | 287 | 3 (the Round ended) | 8 | 306 | 4291 | 602.6 s (Tier 8) |
| 8 chars/s | 718.3 s (12.0 min) | 397 | 3 (the Round ended) | 8 | 418 | 8119 | 714.3 s (Tier 8) |

Kills by time (4 cps): 56 at 120 s (Tier 4), 114 at 240 s, 172 at 360 s, 232 at 480 s, 284 at 600 s; (8 cps): 56, 114, 173, 234, 298. Reading: with these defaults a perfect typist loses no Life until Tier 8 (at 4 cps the 8-letter Words take 2.25 s plus a pause against a 1 s spawn interval, at 8 cps 1 s plus a pause, so the queue grows there); the first 10 minutes are easy. Whether that is too easy is a product question for the human (the numbers do not say what is fun).

Cross-check in the real page (`t23-bot.mjs`, default settings, `?hook`, 90 s of Round time each, keys through CDP): 4 cps gave 40 Kills of 41 spawned, 8 cps 41 of 41, no Life lost, accuracy 100 (the simulation at 90 s predicts about 41 to 42), so the pure model and the page agree.

### 4. Contrast pass (`t23-contrast.mjs`, WCAG 2.x relative luminance, against `#0e1117`)

| Foreground | Colour | Ratio | Need | Result |
|---|---|---|---|---|
| Tier 3 / 4 / 5 | `#5ec8e5` / `#6fd68a` / `#d6e06a` | 9.78 / 10.49 / 13.26 | 4.5 | ok |
| Tier 6 / 7 / 8 | `#f2b45a` / `#ee7f5c` / `#e0577f` | 10.31 / 7.04 / 5.25 | 4.5 | ok |
| Word letter default (also HUD Points, Total, Streak) | `#e6e6e6` | 15.14 | 4.5 | ok |
| Word letter typed | `#6fe08a` | 11.43 | 4.5 | ok |
| Word letter Lock-expected | `#ff5c5c` | 6.24 | 4.5 | ok |
| HUD hint "Esc: menu" | `#7d8590` | 5.07 | 4.5 | ok |
| Player | `#f5f5f5` | 17.33 | 3 | ok |
| Lives kept, Meter flash | `#ffffff` | 18.90 | 3 | ok |
| Shot / Plus Sign / meter fill ramp, stops 0 to 10 | `#4aa3ff` ... `#ff3b3b` | 7.18, 6.49, 5.87, 5.41, 5.03, 4.82, 4.71, 4.69, 4.80, 5.01, 5.35 | 3 | ok (min 4.69 at stop 7) |
| Summary text / row labels on the panel | `#e6e6e6` / `#a8aeb8` | 15.14 / 8.47 | 4.5 | ok |
| Paused text (worst case: overlay over a white frame) | `#e6e6e6` | 6.81 | 4.5 | ok |
| Renderer error text on its `#0e1117` box | `#ff8a8a` | 8.33 | 4.5 | ok |
| Start and Settings pages | UA defaults (`color-scheme: light dark`, no colours set) | 18.73 on `#121212` (OS dark), 21 on white (OS light) | 4.5 | ok; the pages follow the OS scheme, they are not on `#0e1117` |
| Player in the Grace blink (25% alpha) | `#484a4f` effective | 2.13 | 3 | below, by spec (open question) |
| Lost Lives, Streak Meter track | `#2a3140` | 1.45 | 3 | below, by spec (open question) |
| Dot grid, Summary border | `#2a3140` | 1.45 | none (decorative) | exempt |
| Hit flash (red 30% over the background) | tint, not content | 1.31 | none | exempt |

Every Tier colour passes 4.5:1 as section 9 requires. No colour was changed. Open product questions (not clear colour tweaks, because the spec fixes both on purpose): (a) the blink's 25% opacity frame, a transient state indicator that is by design dim; (b) lost Lives and the meter track in the dot-grid grey `#2a3140` at 1.45:1; the information is not lost (kept Lives are 18.9:1 and the Streak is also in the HUD as text), but a low-vision player will hardly see the empty slots or the empty track. Raising them (for example to `#5a6578`, 3.2:1) is a one-constant change in `Game.Scene` (`trackColour`) if the human wants it; they share the dot-grid default today.

### 5. The embedded word list read back in the running page (mode `words`)

On the Start page of the running app `Words: 400` equals the line count of `frontend/words/words.txt`. A Round on a fast-spawn seed through all six Tiers (`firstTier` 3, `lastTier` 8, 10 per Tier, 60 spawns) read through the hook: 60 distinct Words, every one a line of `words.txt`, each of the length of its Tier, no duplicate on screen at any time. The whole `words.txt` byte string is found inside the `.wasm` the page loaded (`ghcjs/frontend.wasm`, 6,835,938 bytes, file at offset 5,592,269); a copy with one byte changed is not found (control).

### Bugs found and fixed

1. **Plain `/` and `'` were not neutralised** (Firefox quick find would steal the letters). Fixed in `keys.js` as above.
2. No renderer, resize, DPR, detach or WebGL-fallback bug was found; the first run's one failure was my own dot-grid threshold being too tight at 1280x400 (a 1.6 px dot reads 28, not 30), not a game fault.

Harness note: CDP's synthesised Alt+Tab / Cmd+Tab move DOM focus to the Menu button (a real OS or browser consumes those chords), after which Space activates Menu and leaves the page. That is the page's normal button behaviour, not a bug; the check blurs the active element after those chords.

### Not done, open, or contradicting the spec

- **The embedded word list is still the 400-word made-up placeholder** (`frontend/words/SOURCES.md`). Ticket 10 is `resolved` but its output (SCOWL-derived `words.txt`, `tools/make-words.sh`) is not in the repo, and the Start page and the checks above prove the plumbing, not the content. No new feature was added here to build it.
- **Numeric defaults are not tuned** (see 3). The spec says "tuned by play"; this ticket could not play.
- Spec section 4 says a Keystroke is a physical a-z key-down; `keys.js` reads `event.key`, so a non-QWERTY layout types by its letters. Not changed.
- Firefox quick find, Safari and real touch or multi-monitor DPR changes were not observed (only Chrome headless; the DPR change is `Emulation.setDeviceMetricsOverride`).
- Whether the lost-Life and meter-track contrast and the Grace blink dim are acceptable is the human's call (4).

### Gates

AGENTS.md names none. `nix build .#haskell-nix --cores 4 -L` and `--rebuild`, and `nix build .#checks.aarch64-darwin.common-test .#checks.aarch64-darwin.renderer-test --cores 4 --rebuild -L --no-link`: `nix build .#haskell-nix --cores 4 -L` ok, then again with `--rebuild` ok: 0 `warning: [GHC` in both logs (this ticket changed no Haskell source, only `keys.js`, so GHC did not recompile; the last full compile was ticket 22's, also clean); `common-test` 355 cases and `renderer-test` 36 cases, 0 errors, 0 failures, with `--rebuild`. Browser scripts: three full runs, 92 PASS and 0 FAIL each.
