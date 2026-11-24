# Type Wizard: specification

A top-down typing game in Haskell compiled to wasm (reflex-dom, Obelisk v2), rendered with WebGL. Terms in **bold** are defined in `GLOSSARY.md`; use them exactly. This document merges the resolved wayfinding tickets under `.scratch/type-wizard/issues/`; each section names its source ticket, which holds the reasoning.

Where two tickets disagreed, the later or more specific one won. Those calls are listed in [section 14](#14-reconciliations-and-assembly-defaults) so they can be overruled in one place.

## 1. Scope

In: a single-player endless typing game with a start page, a game page and a settings page, a Round Summary, persisted progress, and every tunable exposed as a setting.

Out: audio, touch and mobile input, server logic, accounts, leaderboards, multiplayer, non-English or custom word lists.

## 2. Stack and layout

- Obelisk v2, GHC wasm (flavour 9.12), laid out like `~/devs/type-solution`: `common`, `frontend`, a stub `backend`, static deploy. That project has no WebGL precedent and no wasm use of `file-embed`; both are new here (the embed is proven, section 10).
- Cabal packages: `common`, `frontend`, and a new `renderer` (section 5). `frontend` depends on `renderer` through its public interface only. Fallback if the Obelisk/nix build objects: a module directory in `frontend/src` with an explicit export list.
- Hosting: static deploy to a GitHub Pages sub-path.
- JS seam: a thin shim (as `Frontend/Js.hs` in `type-solution`) owning the GL context, the rAF loop, the glyph atlas, key capture and `localStorage`. Haskell never blocks on JS.

## 3. Module boundaries

```
Game.Settings   Settings record, defaults/min/max, clamp, JSON codec
Game.State      GameState, Input, Phase, pure `step`        (no renderer, no Reflex, no IO)
Game.Words      word list parsing, per-Tier shuffled bags
Game.Scene      pure `buildScene`                           (depends on State, Settings, renderer types)
Renderer.*      renderer package: public types + startRenderLoop
Frontend.*      Reflex wiring, pages, JS shim, persistence
```

Dependencies point downwards only: nothing in `Game.State` imports the renderer; only the wiring that calls `startRenderLoop` imports `Game.Scene`.

## 4. Game rules (ticket: game rules state machine)

### Typing state machine

A **Keystroke** is a physical a–z key-down during a running Round. Auto-repeat (`repeat`) is ignored; separate presses of one letter each count. Non-letter keys are ignored. Tab is not a Keystroke.

| State | Input | Result |
|---|---|---|
| Idle | letter matching the first letter of some Word | **Focus** the closest Enemy (smallest centre-to-centre distance to the Player at key press; tie goes to the earlier spawn). Correct keystroke, k = 1. |
| Idle | letter matching no Word | Nothing. Not a Keystroke, not a **Typo**. |
| Focused | correct next letter | k + 1. At k = Word length: **Kill**, state Idle. |
| Focused | wrong letter | **Typo**: Streak, Bonus and Streak Meter clear at once. State Locked. Counts as a wrong keystroke. |
| Locked | the expected letter | state Focused, k + 1. |
| Locked | any other letter | Not a new Typo (Streak is already 0). Counts as a wrong keystroke. Stays Locked. |
| Focused or Locked | Tab | Focus and Lock clear, the Word resets to k = 0. The Enemy keeps moving. No cost to Streak or Accuracy. |
| Idle | Tab | Nothing. |

Closest Enemy wins when several Words match a first key. No two Words on screen are equal.

### Scoring

- A Kill increments the Streak first, then **Points** = 1 + Bonus, with Bonus = floor(Streak / group size) from the new Streak. The 10th consecutive Kill already earns 2. No cap.
- On a Kill that completes a group, the Streak Meter fills, the Bonus rises, and the meter clears.
- **Accuracy** = correct / (correct + wrong) keystrokes; 100% when there are none.
- **WPM** = (correct characters / 5) / minutes, from the first Keystroke of the Round to Round end.
- **Longest Streak** counts only Kills in the current Round, from 0 at Round start (carried-in 7 plus 5 Kills: Streak 12, Longest Streak 5).
- The Streak is app-wide persisted state; it survives Rounds and death, and is cleared only by a Typo.

### Spawning and Tiers

- A **Tier** is the Word length (3 to 8; first and last Tier are settings). The Tier of new Enemies advances after `enemiesPerTier` (50) Enemies of the current Tier have **spawned**, not killed.
- Within a Tier the spawn interval shrinks linearly from `intervalStart` (Enemy 1) to `intervalEnd` (last Enemy of the Tier). The same two values apply to every Tier; the ramp resets at each Tier.
- At the last Tier, spawning continues with the interval held at `intervalEnd`. There is no victory condition.
- Enemy speed is one constant for all Enemies. Difficulty comes from Word length and spawn rate only.
- Spawn position: a random angle (from the seeded generator) at a fixed radius from the Player, equal to the default view's half-diagonal plus `spawnRadius`. The radius is relative to the Player, not the Camera.

### Hit, Grace Period, Lives, Round end

- An Enemy moves toward the Player and stops at contact distance. It stays until killed and can still be Focused and typed.
- A **Hit** happens when an Enemy touches the Player with no **Grace Period** active: Lives − 1 and a Grace Period of `gracePeriod` seconds starts. During Grace nothing happens. When it ends, any Enemy still touching Hits at once, so a parked Enemy costs one Life every Grace Period. A Hit never affects the Streak.
- Lives reaching 0 ends the **Round**: spawning, movement and input stop; Focus and Lock drop; Enemies on screen are discarded with no Points. The Round's Points are added to Total Points and the **Round Summary** is shown.
- Round start: first Tier, full Lives, empty field, spawn counters 0, no Focus, no Grace. Carried in: Streak (with Bonus and meter), Total Points, Settings.

### Round Summary rows (in order)

Points (this Round), Total Points, WPM, Accuracy, Kills, Longest Streak, Streak (current, carried out).

## 5. Renderer (ticket: renderer interface)

A separate small 2D module that mimics react-three-fiber: a declarative node tree, a pure flatten, one packed buffer per frame, and a JS executor owning GL. It follows `~/devs/flor-do-mar`'s render layer (ADR-0003 scene graph, ADR-0007 one browser task per frame, ADR-0012 frame clock) as a design, not a code copy.

Differences from flor-do-mar: orthographic 2D camera, no lighting, no stroke or ring primitives, no geometry upload cache (shapes are fixed in the JS executor), a packed `Float32Array` over wasm memory instead of JSON, and a text primitive.

### Public interface (everything else is hidden)

```haskell
data Scene  = Scene { sceneCamera :: Camera, sceneWorld :: [Node], sceneOverlay :: [Node] }
data Camera = Camera { cameraCentre :: V2, cameraWorldHeight :: Float }
data Node
  = Group Transform [Node]
  | Square Transform Colour
  | Triangle Transform Colour
  | DotGrid { spacing, radius :: Float, colour :: Colour }
  | Text Transform Anchor Float [(Char, Colour)]   -- glyph height in world units
data Anchor = AnchorLeft | AnchorCentre | AnchorRight
data Transform = Transform { position :: V2, rotation :: Float, scale :: V2 }
data Colour = Colour Float Float Float Float       -- straight RGBA 0..1
data Viewport = Viewport { width, height, aspect :: Float }
data Frame    = Frame { viewport :: Viewport, time :: Double }  -- rAF timestamp, seconds

initRenderer    :: JSVal -> JSM (Either Text Renderer)   -- receives the canvas Reflex created
getViewport     :: Renderer -> JSM Viewport
startRenderLoop :: Renderer -> (Frame -> IO (Maybe Scene)) -> JSM ()
```

### Rules

- No z and no depth test. Tree order is draw order (later on top); alpha blending on. `sceneWorld` draws first, then `sceneOverlay`. `DotGrid` draws where it sits in the tree, so the builder puts it first.
- The Camera is a centre plus a fixed visible world height (a setting, default 20); width follows the aspect ratio.
- `sceneOverlay` is screen-fixed, in world-height units, origin at the viewport centre, unaffected by the Camera.
- A Plus Sign is a `Group` of two `Square`s. The dot grid is one node with spacing, radius and colour; its extent and offset come from the Camera.
- Text: one font, one line, printable ASCII, from a single canvas-2D monospace atlas built once after `document.fonts.ready`, drawn as instanced quads. Horizontal anchoring only, baseline-centred vertically. No wrapping. Per-letter colour is plain RGBA; the renderer knows nothing about typed, locked or default letter states.
- Colour: settings store display colours; the scene builder converts to `Colour`; the renderer treats values as opaque.
- Lifecycle: Reflex creates the canvas. `initRenderer` creates the GL context, sizes the backing store from CSS size times `devicePixelRatio`, and observes resizes. If WebGL is unavailable it returns `Left` and the page shows an error. No context-loss recovery in v1.
- Frame loop: the JS shim owns rAF and calls Haskell once per frame. The pull function returns the latest Scene (`Nothing` keeps the last frame). The loop flattens it, packs the instance buffer, and makes **one** unsafe JSFFI call with a pointer and an instance count. A failing frame is reported through `console.error` and the next is attempted; a killed thread is rethrown. The loop stops by itself when the canvas is no longer connected (`isConnected`, checked once per frame); there is no stop function.
- Hidden: flatten, instance layout and packing, atlas, shaders, the FFI call, canvas sizing, DPR, resize observation.

## 6. Scene, handoff and builder (ticket: scene structure and handoff)

**Pipeline.** `GameState` (owned by the network as `Dynamic GameState`) → `buildScene` (pure) → the renderer's `Scene`. The Scene is a per-frame product; game logic never writes one.

```haskell
buildScene :: Settings -> Frame -> GameState -> Scene
```

**Handoff cell.** `IORef (Maybe GameState)` plus the Round's Settings snapshot. This **deliberately departs from the original brief's `MVar`**: the runtime is single-threaded, so there is no race, and the only hazard is a blocking `takeMVar`/`readMVar` in a synchronous callback. `IORef` cannot block and gives the required semantics: the writer overwrites, the reader peeks. Written only by `performEvent_` on `updated gameState`; read only by the render pull (`readIORef`).

The pull returns `Nothing` only before the first state exists, and afterwards a freshly built Scene on every frame (the Scene depends on frame time). A slow logic step rebuilds the same state at a newer time, so animations keep running; a fast one drops intermediate states.

**Animation.** Shots, Plus Signs, the Camera pan and the Camera ease-back live in `GameState` as start-time records (start time, duration from the Round's settings snapshot, endpoints). `buildScene` evaluates and eases them at `Frame.time`. The step only creates records and drops expired ones. Enemy and Player positions are plain state advanced by the step. The Scene contains no times, only evaluated positions, scales and colours. Word display state (typed count, Lock) is plain state; the builder maps it to per-letter colours.

## 7. FRP network (ticket: FRP network architecture)

**Tick.** The JS shim owns rAF. Each frame it calls the render pull and also fires one `Event t Double` tick (the rAF timestamp) through `newTriggerEvent`. The step gets `dt = now − previous`, clamped to `maxTickDt`. A hidden tab stops rAF, so the Round freezes and resumes without a jump.

**One pure step.**

```haskell
data Input = Key Char | Tab | Tick Double | Start Seed
step :: Settings -> Words -> Input -> GameState -> GameState
```

The network merges the key, tab, tick and start Events into one `Event Input` and folds it with `foldDyn`. `GameState` carries `Phase = Idle | Running | Over`, the Round's Settings snapshot, the Word bags, and a splitmix generator seeded from the clock at `Start`. The step draws Word choice and spawn angle from the generator, so with a fixed seed it is deterministic with no IO and no Reflex. The exact `GameState` and `Input` fields are an implementation detail.

**Keys.** The JS shim listens to `keydown` on `window`, calls `preventDefault` for Tab in JS, drops `repeat` and non-letter keys, and fires one Event per Keystroke through `newTriggerEvent`. It listens only while the game page's canvas is attached, so the other pages' keys are untouched. No `wrapDomEvent` (no dependence on jsaddle-wasm's sync path).

**Where state lives.**
- Above the page switch: `Dynamic Settings` (one record), `Dynamic Save` (Total Points, Streak, Bonus), the persistence `performEvent_`s, and `Dynamic Page`.
- Game page: `Dynamic GameState`, the merged `Event Input`, the render-loop start, the cell write.
- Out of the game page: `Event RoundEnded RoundResult` (Round Points, Kills, Longest Streak, WPM, Accuracy, final Streak) from the `Running → Over` transition. The app root adds Round Points to Total Points and saves.

**Lifecycle.** Entering the game page fires `Start seed`, which snapshots current Settings into `GameState` and resets per section 4. The game page reads the Streak from `Dynamic Save` at `Start` and writes it back on each change. `Over` freezes input and spawning and shows the Round Summary; "Play again" fires `Start` again.

## 8. Pages and flow (ticket: pages and Round flow)

**Routing.** No URL routing. `FrontendRoute` keeps one constructor. The current page is a `Dynamic Page` (`Start | Game | Settings`) held above the page switch; `routeLink` is not used. One exported `index.html`; no deep links and no browser Back between pages. The shell around the switch stays route-independent, so hydration is unaffected.

**Canvas.** Created inside the game page, fresh on each visit. Detaching it stops the render loop and the key listener, so no teardown code is written. Start and Settings are plain DOM with no canvas and no GL context.

**Start page.** "Play" and "Settings" buttons; shows Total Points, Streak and Bonus.

**Settings page.** Reached from Start only; "Back" returns to Start. Its own "Saved progress" section holds "Reset progress" (clears Total Points, Streak, Bonus; needs a second click, "Really reset?").

**Game page.** A small "Menu" control and the Escape key both go straight to Start. Leaving **abandons** the Round with no confirm dialog: the Streak is already persisted per Kill or Typo, and the only loss is the unbanked Round Points. Abandoning shows no Round Summary and banks nothing.

**Round Summary.** A DOM panel over the frozen game canvas when `Phase = Over`; not a separate page. Buttons: "Play again" (Enter does the same) and "Back to start". Letters are ignored while it shows.

**Blur.** Window `blur` freezes the Round (the tick is dropped so `dt` is zero) and shows "Paused, click or press any key to resume". `focus` followed by a click or key press resumes. There is no manual pause key.

**HUD** (renderer overlay text and squares, screen-fixed):
- Top-left: the Lives row (section 9). Top-right: Points this Round and Total Points. Bottom-centre: "Streak N". Bottom-left: small "Esc: menu".
- No live WPM.
- The Bonus "+N" and the Streak Meter are world nodes next to the Player.

## 9. Visual and animation spec (ticket: visual and animation spec)

World units assume an orthographic camera with a fixed world height of 20. Every value below is a setting with a default, a min and a max (section 11).

**Palette** (every Tier colour ≥ 4.5:1 on the background)

| Role | Colour |
|---|---|
| Background | `#0e1117` |
| Dot grid | `#2a3140` |
| Player | `#f5f5f5` |
| Tier 3 / 4 / 5 | `#5ec8e5` / `#6fd68a` / `#d6e06a` |
| Tier 6 / 7 / 8 | `#f2b45a` / `#ee7f5c` / `#e0577f` |
| Letter default / typed / Lock-expected | `#e6e6e6` / `#6fe08a` / `#ff5c5c` |

**Sizes and layout.** Player a 1.2 square, Enemy a 1.0 square. The Word is centred 1.0 below the Enemy centre, monospace atlas, 0.9 cap height. Dot grid: 2-unit spacing, 0.08 dots, anchored to the world (it scrolls with Camera pans).

**Shot.** A triangle 0.5 long pointing along travel, from the Player centre to the killed Enemy's position, 0.12 s ease-out. The Enemy is removed and Plus Signs spawn on arrival. Colour: 11 stops (one per group of Streak), linear RGB from `#4aa3ff` at Streak 0 to `#ff3b3b` at 10 groups (100 by default) and beyond. The ramp always spans 10 groups, so it follows the group size.

**Plus Signs.** One per Point (1 + Bonus), 0.5 units, in the Shot colour at Kill time. Start offset random within the spread radius (0.6, seeded from `GameState`). 0.1 s hold, then fly to the Player over 0.5 s with quadratic ease-in, each delayed a random 0 to 0.15 s. Scale to 0.3× and fade over the last 0.15 s; removed on reaching the Player. At most 30 signs are drawn per Kill; Points are unaffected.

**Camera.**
- Target: the Focused Enemy's position, moved only if it lies outside the default view, by the smallest shift that brings it inside a 2-unit inset. The Player stays at least 3 units inside every screen edge.
- Exponential smoothing with a 0.25 s time constant, for both the pan and the return.
- Fixed while the Word is typed; eases back to the Player on Kill or Tab.

**Streak Meter and Bonus label.** A 2 × 0.25 bar, 1.6 above the Player, dim track, fill in the Shot colour = (Streak mod group size) / group size, growing over 0.1 s per Kill. At a full group: flash white 0.15 s, empty over 0.25 s, "+N" label pops 1.4× → 1× over 0.2 s. The label is hidden at Bonus 0. On a Typo the bar empties and the label fades over 0.2 s.

**Hit feedback.** The Player blinks (full / 25% opacity every 0.1 s) for the whole Grace Period. A full-screen red overlay at 30% opacity decays over 0.3 s. A parked Enemy re-Hitting repeats both.

**Lives.** 0.4-unit white squares in a row at the HUD top-left; lost Lives are dim `#2a3140` squares (the renderer has no outlines).

## 10. Words (tickets: dictionary pipeline, file-embed spike)

- **Source:** SCOWL v2, US spelling, abbreviations excluded, size 35 (about 19k words), filtered to `[a-z]{3,8}`. SCOWL `offensive-*`/`vulgar-*` tags are dropped, then the LDNOOBW English list and a project-owned `exclude` file (`god`, `hell`, `damn`, …) are applied. No frequency weighting; fairness comes from the size cutoff.
- **Pipeline:** an offline script `tools/make-words.sh` writes a committed `words.txt` (one word per line, sorted by length), with SCOWL's `Copyright` text and a `SOURCES.md` beside it. The build needs no network.
- **Embedding (proven by the spike):** `file-embed` as a ByteString, about 150 KB raw, about 60 KB gzipped, parsed at start. It costs about +164 KB in `frontend.wasm` (+69 KB brotli). Three build rules, each learned from a failed build:
  1. The file must be **tracked by git** and must **not** live under `frontend/data/` (gitignored). Use `frontend/words/words.txt`.
  2. The cabal file needs `extra-source-files: words/words.txt`.
  3. Use `makeRelativeToProject "words/words.txt" >>= embedFile` in a `TemplateHaskell` module, and put `file-embed` and `bytestring` in the library's main `build-depends`, outside the `!(javascript || wasm32)` conditional.
- **Selection:** one shuffled bag per Tier over its length bucket, held in `GameState` and shuffled with the seeded splitmix. Words already on screen are skipped. An empty bag is reshuffled with a no-recent-repeat guard (this covers endless Tier 8).
- **First letters:** best-effort distinctness. A draw whose first letter matches an on-screen Word is replaced by the next bag Word within `wordLookahead` (default 10, 0 = off, max 50); otherwise it is accepted. Closest-Enemy-wins remains the tiebreaker.
- **Determinism:** the seed is a `GameState` field, clock-derived at Round start and fixed in tests; not a setting, not persisted. The word list is a parameter of `step`, so tests inject a tiny list.

## 11. Settings (ticket: settings schema, amended by the dictionary and visual tickets)

Format: default (min–max). Seconds unless stated.

**Rules:** starting Lives 3 (1–10); Grace Period 2 (0.5–10); Enemies per Tier 50 (10–200); first Tier 3 (3–8); last Tier 8 (first Tier–8); Streak group size 10 (2–50).

**Spawning:** `intervalStart` 3.0 (0.5–10); `intervalEnd` 1.0 (0.2–`intervalStart`); `spawnRadius` beyond the default view 1.0 (0–5); Enemy speed 1.0 units/s (0.2–5); `wordLookahead` 10 (0–50).

**Camera:** world height 20 (8–60); time constant 0.25 (0.05–2); inset 2 units (0–6); Player margin 3 units (1–8).

**Animation:** Shot duration 0.12 (0.05–1); Plus Sign fly duration 0.5 (0.1–2); Plus Sign hold 0.1 (0–1); Plus Sign spread radius 0.6 units (0–2); Plus Sign draw cap 30 (1–200).

**Timing:** `maxTickDt` 0.1 (0.02–0.5).

**Colours:** one per Tier 3 to 8; Player; background; dot grid; letter default, typed, Lock-expected; Shot ramp start and end. Defaults in section 9.

Behaviour:
- **Reset:** one button per group plus "Reset all", no confirmation. Total Points, Streak and Bonus are saved state, not settings, and are untouched.
- **Effect:** a snapshot at Round start. The settings page is unreachable during a Round, so no mid-Round change exists.
- **Validation:** controls clamp while editing; stored out-of-range values are clamped on load; missing or wrong-typed values fall back to the field default. Cross-field rules clamp the dependent field (`intervalEnd ≤ intervalStart`, last Tier ≥ first Tier). Nothing is rejected or shown as an error.
- **FRP and persistence:** one `Dynamic Settings` record, written whole on change; field widgets use projections.

## 12. Persistence

- `localStorage` key `typewizard.settings`: JSON with `version: 1`. A version mismatch migrates if a migration exists, otherwise falls back to defaults.
- `localStorage` key `typewizard.save`: Total Points, Streak, Bonus.
- Interface, behind the JS shim: `loadSave :: IO Save`, `storeSave :: Save -> IO ()`, and the same pair for settings. Settings are written on every change. The save is written whenever the Streak changes (each Kill or Typo) and when `RoundEnded` banks Total Points.
- Every `localStorage` access tolerates failure (private windows, blocked storage): the game plays with defaults and in-memory state.

## 13. Testing

- **`step`** is pure and takes explicit `Settings`, `Words`, `Input` and a seeded `GameState`. Headless tests fold a list of `Input`s and assert on states: Typo clears Streak, Tab resets the Word, Locked wrong keys count against Accuracy, the 10th Kill pays 2, Grace Period re-Hit, spawn ramp per Tier, Tier advance on spawns, determinism for a fixed seed, no duplicate Words on screen.
- **`buildScene`** is tested with a hand-made `GameState`, `Settings` and `Frame`, asserting through small query helpers ("letters 1 to 3 of Enemy 2's Word are typed-coloured and letter 4 is Lock-coloured", "Camera centre is halfway at the midpoint of a pan", "Plus Sign count equals Points"). No golden files.
- **Renderer pure layer** (following flor-do-mar's `RenderLayerTest.hs`): transform composition and node order in flatten, the camera matrix, and the packed buffer (instance count, byte layout, text to glyph instances). `flatten` and the encoder are exposed from an internal module for tests.
- **Not tested automatically:** the JS executor, the GL output and the Reflex wiring. They are checked by eye in the running app. No headless-GL tooling.

## 14. Reconciliations and assembly defaults

Earlier tickets disagreed or left a gap. The choices below are this spec's; overrule any of them here.

1. **Camera parameters.** The settings ticket listed a pan duration (0.4 s), an ease-back duration (0.6 s) and a margin (0.15 of the view). The visual ticket, later and more specific, fixed one exponential time constant (0.25 s) for both directions, a 2-unit inset and a 3-unit Player margin. The visual values win and replace the three older fields in section 11.
2. **Lives display.** The pages ticket showed "Lives N" as text; the visual ticket drew Lives as squares. The squares win; the HUD has no "Lives N" text.
3. **Shot duration.** The settings default was 0.25 s; the visual ticket specified 0.12 s. 0.12 s wins. Plus Sign duration 0.6 s is kept as 0.1 s hold + 0.5 s fly.
4. **Plus Sign spread.** The settings field was a 0–1 factor (0.3); the visual ticket gave a 0.6-unit radius. Section 11 uses the radius in units.
5. **World height** was left unassigned by the settings ticket; it is a Camera setting, default 20.
6. **Round end animations (new decision).** Enemies are discarded at once; Shots and Plus Signs already in flight finish playing behind the Round Summary, since they are start-time records the builder keeps evaluating. The rules ticket deferred this.
7. **Blur and animations (new decision).** Blur freezes the Round logic (`dt` = 0), not the builder's evaluation time, so in-flight animations still finish while the "Paused" overlay shows. Acceptable because there is no gameplay state change during that time.
8. **Streak group size** is a setting, so the Meter, Bonus and Shot ramp are defined in groups, with 10 as the default.
9. **Spawn radius** is measured from the Player to the default view's half-diagonal plus `spawnRadius`; "default view" means the Camera centred on the Player.

## 15. Open items for implementation

These were left in the fog on purpose; none changes a decision above.

- **Build, dev loop and deploy:** copy the Obelisk v2 and wasm setup from `type-solution`; the static GitHub Pages deploy and its sub-path base. A bootstrap task is likely the first implementation ticket.
- **JS boundary cost:** measured in ticket 15 (headless Chrome, Apple M1 Max, release wasm build, `?bench`). A trivial `unsafe` JS FFI call from Haskell costs about 0.17 us (100,000 in 17 ms); a JS call into a Haskell `wrapper sync` callback about 1.3 us (100,000 in 130 to 138 ms); queued jsaddle calls about 2.2 us each (1,000 in 2.2 ms, results not awaited, so not a round trip). The whole per-frame renderer callback (pull, flatten of about 270 instances, pack, the one draw call and the GL work) is 0.63 ms per frame at 60 fps, 4% of the frame. The one-call-per-frame design is cheap; the numbers and method are in the ticket's Answer and `README.md`.
- **Browser shortcuts other than Tab:** key capture handles Tab; any key press with Ctrl, Cmd or Alt is ignored (not a Keystroke, not a Typo) and left to the browser. Checked in ticket 23: plain `/` and `'` also get `preventDefault` (Firefox quick find; Chrome has none, and Firefox itself was not available to check). Other keys are left alone.
- **JS-side checks:** the renderer's JS executor has no automated test; the manual browser checklist (resize, DPR change, canvas detach stops the loop, WebGL-unavailable message) is in `README.md` ("Renderer") and was run in ticket 15 and again, scripted, in ticket 23.
- **Browser read-back of the embed:** the spike proved the embedded bytes are in the wasm; ticket 23 read it back in the running page (Start page `Words: N`, every spawned Word in `words.txt`, the file's bytes inside the loaded `.wasm`). The embedded `words.txt` is still the 400-word placeholder (see `frontend/words/SOURCES.md`).
- **Numeric defaults (spawn interval, speed):** measured, not tuned (ticket 23: nobody has played it). A scripted bot on the current defaults is recorded in that ticket's Answer. The values stay as in section 11 until a human tunes them.

## 16. Suggested slicing

Each slice is independently testable and leaves the app building.

1. **Scaffold and build:** Obelisk layout from `type-solution`, `renderer` package stub, `Game.*` modules empty, `words.txt` embed per the three rules, static deploy to a sub-path. Page switch with three empty pages.
2. **Settings and persistence:** `Settings` record with defaults, min, max, clamp; JSON codec and versioning; the settings page with reset buttons; `localStorage` wrapper that tolerates failure.
3. **Renderer:** public types, pure flatten and encoder with tests, JS executor, `initRenderer`, `startRenderLoop`, glyph atlas. Demo scene with a square, a dot grid and text. Measure the per-call cost.
4. **Game logic core:** `GameState`, `step` for spawning, movement, Tiers and Word bags with tests (no typing yet).
5. **Typing and scoring:** the state machine, Typo, Tab, Kill, Streak, Bonus, Points, Accuracy, WPM, with tests.
6. **Hit, Lives, Round end:** Grace Period, re-Hit, `Over`, `RoundEnded`, Total Points banking.
7. **Scene builder:** `buildScene` for Player, Enemies, Words, dot grid and HUD, with query-helper tests.
8. **Animation:** Shot, Plus Signs, Streak Meter and "+N", Hit feedback, Camera pan and ease-back, in that order, each with `buildScene` tests.
9. **Wiring:** merged `Event Input`, `foldDyn step`, the `IORef` cell, JS tick and key shim, blur freeze, page flow, Menu/Esc, Round Summary panel, Start page stats.
10. **Polish and tuning:** the browser checklist, shortcut handling, default tuning of the numeric defaults flagged as placeholders (spawn interval, speed), accessibility pass on contrast.
