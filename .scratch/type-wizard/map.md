# Map: Type Wizard

## Destination

A decision-complete spec at `.scratch/type-wizard/spec.md`: game rules, settings, module boundaries (renderer, scene, game logic, FRP network), pages and flow, and the visual and animation parameters. It should be ready to slice into implementation tickets. No game code is written during wayfinding, and there are no prototypes.

## Notes

- Domain vocabulary is in `GLOSSARY.md` at the repo root. Use its terms exactly, and consult the `domain-modeling` skill when terms change.
- Stack: Haskell compiled to wasm (reflex-dom, Obelisk v2), laid out like `~/devs/type-solution`. That project is a static deploy with a stub `backend/` and no WebGL precedent. Its JS interop pattern is a thin seam (`frontend/src/Frontend/Js.hs`) that exposes text, key events and JSON to Reflex. This server only serves the frontend and has no logic.
- Pages: start page, game page, settings page (reached from the start page). The settings live in the FRP network as Dynamics.
- Rendering: WebGL through a module that mimics react-three-fiber. A separate module (`buildScene`) builds the Scene from the game state each frame and the renderer draws it. A latest-value cell bridges the FRP network and the frame loop (see the scene ticket).
- Standing preferences: every tunable (speeds, spawn curve, Tier size, Lives, Grace Period, camera and animation timings, colours) is a setting with a default, a min and a max. There are no prototype tickets.
- Persisted in `localStorage` behind a small save and load interface: Total Points, Streak, Bonus, settings.
- Words: a bundled SCOWL size-35 list filtered to `[a-z]{3,8}` with a profanity filter. No duplicate Words on screen. Closest Enemy to the Player wins when several Words match a first key.

### Settled while charting

- Scoring: Points per Kill = 1 + Bonus, with Bonus = floor(Streak / 10) and no cap. The "+N" next to the Player is the current Bonus. The Streak Meter shows progress through the current 10.
- Streak is cleared only by a typo. A key press with no Focus and no matching Enemy is **not** a typo. Tab is not a keystroke.
- Hit: the Enemy stays, a Grace Period of 2 s follows, and the Streak is unaffected.
- Tier: advances after 50 Enemies of the current Tier have **spawned**, not killed. Spawn rate rises gradually within each set of 50, using the same curve for every Tier. Difficulty comes from longer Words.
- Camera: pans only for the Focused Enemy, never lets the Player leave the screen, stays fixed while that Word is typed, and eases back when Focus ends (kill or tab). Spawns are placed at a fixed radius just beyond the default view, relative to the Player.
- WPM = (correct characters / 5) / minutes, from first keystroke to Round end. Accuracy = correct keystrokes / all keystrokes. Longest Streak counts only Kills made in this Round.
- Shot colour is blue at Streak 0 and steps toward red every 10 Kills of Streak, reaching red at Streak 100 and staying red.
- Research findings are written to `.scratch/type-wizard/research/<name>.md`. The repo is not under git, so there is no throwaway branch.

## Decisions so far

<!-- one line per resolved ticket: gist + link -->

- [Game rules and typing state machine](issues/04-game-rules-state-machine.md): Idle/Focused/Locked machine, keystroke and Accuracy definition, per-Tier linear spawn ramp that resets, Tier 8 endless, Streak increments before Points, parked Enemies re-Hit every Grace Period, Longest Streak counts from 0 each Round.
- [Settings schema](issues/05-settings-schema.md): Fields with default/min/max in five groups (rules, spawning, camera, animation, colours), per-group and global reset, snapshot at Round start, clamp-on-load validation, one `Dynamic Settings` record under versioned key `typewizard.settings`, separate `typewizard.save`.
- [Renderer: the react-three-fiber-like interface](issues/06-renderer-r3f-interface.md): separate `renderer` cabal package; flor-do-mar's design as a 2D module (node tree, pure flatten, one packed-buffer FFI call per frame, JS owns GL and a monospace glyph atlas); Square/Triangle/DotGrid/Text, world plus overlay layers, orthographic camera with fixed world height, pull-based loop that stops when the canvas detaches, pure-layer tests only.
- [Scene data structure and the handoff](issues/07-scene-structure-and-mvar.md): network owns `Dynamic GameState`; a pure `buildScene Settings Frame GameState` runs in the render pull every frame; one latest-value cell (peek, never blocks) bridges; builder owns all animation interpolation; renderer pull takes `Frame {viewport, time}`; HUD is overlay text; headless tests on `buildScene`.
- [FRP network architecture](issues/08-frp-network-architecture.md): `IORef` cell (deliberately not `MVar`), JS-owned rAF fires one tick per frame with clamped dt, one pure `step Settings Input GameState` folded with `foldDyn` and a seeded splitmix in state, JS shim captures keys (Tab `preventDefault` in JS), app-wide Settings/Save above `subRoute_`, `RoundEnded` Event banks Points, leaving the game page abandons the Round.

- [Pages and Round flow](issues/09-pages-and-round-flow.md): GitHub Pages sub-path with no URL routing (a `Dynamic Page`, one `index.html`), canvas created per game-page visit, Menu/Esc leaves with no confirm, Round Summary as a DOM panel with seven rows and Play again / Back, window blur auto-freezes, save written on Streak change and Round end, "Reset progress" with confirm on the settings page, HUD as overlay text.

- [Dictionary pipeline and word selection](issues/10-dictionary-pipeline.md): SCOWL v2 size 35 (US, no frequency weighting) filtered to `[a-z]{3,8}` with SCOWL tags + LDNOOBW + project exclude list; offline script commits `words.txt`; `file-embed` with static-fetch fallback; shuffled bag per Tier with on-screen skip and best-effort first-letter distinctness (`Word lookahead` setting, default 10); seed in `GameState`, word list injected into `step`.

- [Visual and animation spec](issues/11-visual-and-animation-spec.md): Cold-to-hot Tier palette on `#0e1117`, 1.2/1.0 unit squares, 0.12 s Shot with 11-stop blue→red ramp, Plus Signs with seeded spread, stagger and 30-sign draw cap, 0.25 s exponential Camera with 3-unit Player margin, Streak Meter bar with "+N" pop, Grace Period blink, red hit flash, dim-square Lives.

- [Spike: file-embed under the wasm build](issues/12-task-spike-file-embed-wasm.md): works. Needs a git-tracked file outside `data/`, an `extra-source-files` entry, and `makeRelativeToProject`; +164 KB wasm (+69 KB brotli). Browser read-back and JS call cost unmeasured; static-fetch fallback not needed.

Research tickets 01 and 03 have findings (status `researched`) and stay open until the grilling ticket that consumes them resolves. Ticket 02 was consumed by the pages ticket and is now resolved:

- [WebGL, rAF and MVar from wasm](issues/01-research-wasm-webgl-interop.md): a JS shim owns the GL context, the rAF loop and the glyph atlas. Don't block on an `MVar` in a callback. Per-call cost is unmeasured. ([findings](research/01-wasm-webgl-interop.md))
- [Obelisk multi-page routing](issues/02-research-obelisk-multipage-routing.md): `subRoute_` works, but sub-path static hosting needs a routing choice; the pages ticket chose no URL routing. ([findings](research/02-obelisk-multipage-routing.md))
- [Word list source](issues/03-research-word-list-source.md): SCOWL v2 plus a profanity pass is recommended. Embedding with `file-embed` on wasm is untested. ([findings](research/03-word-list-source.md))

## Not yet specified

Nothing. The spec is assembled at [spec.md](spec.md). The leftover items (build and deploy setup, JS boundary cost, browser shortcuts, JS-side checks) are listed in its section 15 as implementation work, not decisions.

## Out of scope

- Audio and sound effects.
- Touch and mobile input.
- Server-side logic, accounts, leaderboards and multiplayer.
- Non-English dictionaries or custom word lists.
