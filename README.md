# Type Wizard

A top-down typing game in Haskell compiled to wasm (reflex-dom, Obelisk v2). The plan is `.scratch/type-wizard/spec.md`; terms are in `GLOSSARY.md`.

## Layout

- `common`: shared code (`Common.Route`) and the pure game modules (`Game.Settings`, `Game.Save`, `Game.Words`, `Game.State`, `Game.Layout`, `Game.Scene`, `Game.Summary`, `Game.Debug`), with a test-suite (`StateTests` for spawning, `TypingTests` for the typing table, `ScoringTests`, `HitTests` for Hits, Lives, Round end, banking and blur, `SceneTests`, `AnimationTests`, `CameraTests`, `FeedbackTests` for the Hit and Streak feedback). `Game.Scene` imports the renderer's types, so `common` depends on `renderer`; `Game.State` and `Game.Words` do not.
- `renderer`: the 2D renderer library (`Renderer` is the whole interface; `Renderer.Internal` is the pure layer, exposed for its tests), with a test-suite. Its JS executor is `static/src/js/renderer.js`.
- `frontend`: the browser app (`Frontend`, `Frontend.Page`, `Frontend.Game`, `Frontend.Storage`, `Frontend.Words`, `Frontend.Bench`). `frontend/wasm` and `frontend/js` are Obelisk wrapper packages that cross-compile it.
- `backend`: a stub that serves the page and its files. No game logic.
- `static/src`: static files (CSS) served as is. `static/generated` is Obelisk's generated package; cabal rewrites `static/generated/src/Obelisk/Generated/Static.hs`, so revert it, never commit changes to it.
- `config`: Obelisk config.
- `frontend/words/words.txt`: the embedded word list (currently a placeholder, see `frontend/words/SOURCES.md`).
- `deps/obelisk`: git submodule (fork `jafonsor/obelisk`, same commit as `type-solution`). `deps/nix-haskell`, `deps/nixpkgs` and `deps/reflex-dom` are symlinks into it.

## Setup

```
git clone --recurse-submodules <repo>
# or, in an existing clone:
git submodule update --init --recursive --depth 1
```

The dev shell is the flake's default (`direnv allow` with nix-direnv, or `nix develop --accept-flake-config`).

## Run

Nix flake builds only see git-tracked files. After adding a file, run `git add -N <file>` before building.

```
nix build .#haskell-nix --cores 4 -L    # wasm frontend plus the server; result/ is the output
cd result && ./backend                   # serves http://localhost:8000
```

Use `--cores 4`: all cores can run the machine out of memory.

In the dev shell, `ob-run` (or `cabal build`) works for quick native iteration; the wasm build is the one that counts.

## Tests

The pure tests (`common/test` and `renderer/test`, HUnit) run as flake checks (`common-test` covers settings, save, words, `step` (spawning, the typing table, scoring, Hits and Round end) and `buildScene`; `renderer-test` the renderer's pure layer):

```
nix build .#checks.aarch64-darwin.common-test --cores 4 -L    # use your own system in place of aarch64-darwin
nix build .#checks.aarch64-darwin.renderer-test --cores 4 -L
```

Each prints `Cases: N  Tried: N  Errors: 0  Failures: 0`. New test files need `git add -N` first, like any file. Browser behaviour (the Reflex wiring, the JS seam) has no automated test; it is checked by driving the built page in headless Chrome.

## Gates

AGENTS.md names no gates; the ones used for each ticket are:

1. `git add -N <new files>`, then `nix build .#haskell-nix --cores 4 -L` (wasm and native). Read `nix log` for `warning: [GHC` lines from our modules: the cabal files carry `-Wall` and `-Werror` flags for the important warnings, and the policy is none.
2. `nix build .#checks.<system>.common-test --cores 4` and `.renderer-test`.
3. Browser behaviour is driven in headless Chrome against the built page (see "Renderer" below).

## Renderer

`renderer/` is a cabal library listed in `cabal.project` beside `common` and `frontend`. The interface is spec section 5 (`Renderer`): `Scene`, `Camera`, `Node`, `Anchor`, `Transform`, `Colour`, `V2`, `Viewport`, `Frame`, `initRenderer`, `getViewport`, `startRenderLoop`. `V2` is the only addition (the spec uses it without defining it). `frontend` imports `Renderer` only; `Renderer.Internal` (flatten, camera matrix, packing) is exposed for the tests and is not to be imported by the game.

How a frame works:

- JS owns requestAnimationFrame (`static/src/js/renderer.js`, `window.TypeWizardRenderer`). Once per frame it calls a Haskell callback, which is a `wrapper sync` JS FFI export, so it runs inside JS's rAF task. The callback gets the rAF time (seconds) and the canvas CSS size, runs the pull function (`Frame -> IO (Maybe Scene)`; `Nothing` keeps the last scene, redrawn at the current size), flattens, packs, and makes one `unsafe` JS FFI call `draw(handle, memory, ptr, count)`. JS builds a `Float32Array` over wasm memory at call time (never cached: memory growth detaches it) and issues the single `drawArraysInstanced`. This path does not use jsaddle: jsaddle's JSON round trips are used only for `create` and `viewport`, once per canvas.
- The packed buffer is an 18-float header (world matrix then overlay matrix, column-major 3x3) and 13 floats per instance (`kind glyph space a b c d tx ty r g b a`); the layout is in the `Renderer.Internal` header and mirrored at the top of `renderer.js`. A square, triangle, dot (dot grid) or glyph (text) is one instance of one unit quad; the shader picks the shape.
- No clear colour exists in a `Scene`, so the background is the first world node (a large `Square`).
- The glyph atlas is one canvas-2D monospace font, printable ASCII `!` to `~`, built after `document.fonts.ready`. Text is invisible for the first moments until it is built. A glyph cell is 0.6 wide and 1 tall in units of the text height argument and is centred vertically on the text position.
- The canvas backing store is CSS size times `devicePixelRatio`, read each frame (the CSS size comes from a `ResizeObserver`; the ratio is read directly because it can change with no size change).
- The loop stops itself when `canvas.isConnected` is false (checked once per frame). Reflex attaches a new canvas a moment after building it, so a canvas gets up to 120 frames to arrive. Leaving the page removes the canvas; entering again builds a new canvas and a new loop.
- If WebGL 2 is unavailable `initRenderer` returns `Left` and the game page shows the message (`p.game-error[data-error=renderer]`).
- On the native build (server-side render) the FFI half is compiled out; the renderer is never started there.
- `window.TypeWizardRenderer.stats` counts `created`, `started`, `stopped`, `frames` and `draws` for tests.

### Browser checklist (the JS executor has no automated test)

Serve the built page (see "Deploy") and open the Game page (Play). Check:

1. A dark window with a white square in the middle and a dot grid; from the first Enemy on (see "Game network") coloured squares with Words arrive; the Menu button is clickable. (The ticket 15 demo text is gone.)
2. Resize the window: the square stays centred and 1.2 world units wide (a 20-unit world height is the window height), the dots keep their 2-unit spacing, nothing stretches or stays blurry.
3. Change the device pixel ratio (drag the window between screens, or browser zoom, or DevTools device toolbar DPR): the picture stays sharp and the same size in CSS pixels. `canvas.width` is CSS width times `devicePixelRatio`.
4. Click Menu: `TypeWizardRenderer.stats.stopped` becomes 1 and `frames` stops growing. Play again: `started` is 2 and `frames` grows.
5. WebGL unavailable (start Chrome with `--disable-gpu`, or run `HTMLCanvasElement.prototype.getContext = () => null` before load): the Game page shows `WebGL is not available in this browser...` and no blank canvas; Menu still works.
6. DevTools console: no errors while it runs.

Results of the run for ticket 15 are in `.scratch/type-wizard/issues/15-renderer-and-empty-game-page.md`. The scripted version used a Chrome DevTools Protocol client (resize with `Emulation.setDeviceMetricsOverride`, pixels from `Page.captureScreenshot`).

## Game network

`Frontend.Game.gameCanvas` (per visit to the Game page): the render pull, run by JS's rAF once per frame, fires one `Tick` (the Frame time) and, when the viewport aspect changed, an `Aspect`; entering the page fires `Start seed save` (seed from `Date.now()` and `performance.now()`, and the app's current `Save`, see "Scoring"). `mergeWith` joins the inputs into one event, `foldDyn` runs `Game.State.step` over them with the current Settings (read at `Start`, snapshotted in `GameState.roundSettings`), and `performEvent_` on `updated gameState` is the only writer of an `IORef (Maybe GameState)`. The pull peeks that cell (`Nothing` before the first state, then a fresh `buildScene` every frame). Never an `MVar`.

`step` so far: Start, Tick (spawn along the per-Tier ramp, move, park at 1.1), Aspect, and typing (`Key c`, `Tab`; see "Typing"). Words: one shuffled bag per Tier (`Game.Words`); a spawn is deferred when every Word of the Tier's length is on screen.

Dev hook: open the Game page with `?hook` (for example `http://localhost:8765/type-wizard/?hook`) and read `window.TypeWizardGame.state()` for a JSON summary of the state (phase, tier, spawned counts, Enemies with word, tier, x, y, distance, and for typing: `focus` (`{enemy, k}` or `null`), `locked`, `correct`, `wrong`, `typos`, `kills`, `accuracy` in percent, `wpm`; for scoring: `streak`, `bonus`, `roundPoints`, `longestStreak`, `meter` (0 to under 1), `totalPoints` (as carried in from the Save), `groupCompletedAt` (Round time of the latest group-completing Kill, or `null`); for Hits and Round end: `lives`, `graceActive`, `graceRemaining` (seconds, or `null`), `paused`, `windowFocused`, `roundTime`, and `roundResult` (`null` until Over, then `{points, totalPoints, wpm, accuracy, kills, longestStreak, streak}`)). Without `?hook` nothing is written. To make a quick run set `localStorage['typewizard.settings']` (for example `{"version":1,"intervalStart":0.6,"intervalEnd":0.6,"enemySpeed":5,"enemiesPerTier":10,"lastTier":4}`) before the page loads.

### Typing

Spec section 4's table is `Game.State.step`'s `Key` and `Tab` rows, tested row by row in `common/test/TypingTests.hs`. The state holds `focus :: Focus` (`NoFocus`, `Focused enemyId k`, `Locked enemyId k`) and counters `correctKeys`, `wrongKeys` (Focused Typos plus wrong letters while Locked), `typos`, `kills`, `roundTime` (sum of the clamped Tick steps) and `firstKeyAt`. `accuracy` is a percentage (100 with no Keystrokes); `wpm` is (correct characters / 5) over the minutes of `roundTime` from the first Keystroke (correct or wrong) to now, and 0 before any time has passed. A Typo calls `onTypo` and a Kill `onKill`, where scoring happens (see "Scoring"). Only a-z `Key`s count; keys are ignored unless Phase is Running. The closest Enemy is chosen by distance compared to a millionth of a unit (parked Enemies are equal up to rounding, so that is a tie that goes to the earlier spawn).

The key shim is `static/src/js/keys.js` (`window.TypeWizardKeys.attach(canvas, callback)`, loaded in the page head; `Frontend.Game` calls it with a jsaddle `function` that fires one message (a letter, `Tab`, `Enter`, ...) through `newTriggerEvent`). It listens to `keydown` on `window` (capture phase) only while the canvas is connected and removes itself when it is not (checked on each key and once per frame), so Start and Settings keys, Tab navigation included, are untouched. It calls `preventDefault` for Tab itself, ignores `event.repeat`, and reports `a-z` / `A-Z` as lowercase. A key with Ctrl, Meta or Alt is ignored and left to the browser (so Ctrl+Tab, Ctrl+C, Ctrl+F and the like still work, and none is a Keystroke or a Typo); Shift is fine. Plain `/` and `'` also get `preventDefault` (Firefox opens quick find on them and the find bar would take the letters that follow; they stay non-Keystrokes). Other keys (F-keys, Backspace, Space) are left alone and are not Keystrokes. The browser check is `scratchpad/t23-browser.mjs keys` of ticket 23 (see its Answer). `TypeWizardKeys.stats` (`attached`, `detached`, `sent`, `active`) is for the browser check. Enter, Escape, `Other`, `blur`, `focus` and `mousedown` are reported too (see "Hits, Lives, Round end, Summary and blur"), and `stats.events` counts them.

### Scoring

`Game.State`: a Kill increments `streak` first, then pays `1 + floor(streak / group size)` into `roundPoints` (group size is the Round's snapshot of `streakGroupSize`; no cap). A Typo sets `streak` to 0 at once; Tab and wrong letters while Locked never touch it (a Locked wrong letter is not a Typo). `streakBonus st = streak / group size` and `meterFill st = (streak mod group size) / group size` are derived, so a Typo clears them with the Streak. `runKills` (consecutive Kills this Round, cleared by a Typo) feeds `longestStreak = max run`, which counts from 0 at Round start whatever Streak was carried in (carried 7 plus 5 Kills: Streak 12, Longest Streak 5). `groupCompletedAt` is the `roundTime` of the latest Kill that completed a group (cleared by a Typo): the meter then reads 0 (full-then-clears is that moment; the animation, ticket 22, reads the record).

`Start seed save` takes the whole saved progress: the Streak (Bonus and meter follow from it; the saved Bonus is ignored and re-derived with the group size in force) and the Total Points (`totalPoints` in the state, for the HUD; banking them is the Round-end ticket's). `Frontend.Game.gameCanvas` receives the app's `Dynamic Save` and reads it at `Start`; it returns an `Event (Save -> Save)` (`progressSave`: Streak and the derived Bonus, Total Points untouched) fired by every new state in which a Kill or a Typo just happened, and the Game page hands that to the page switch's `saveEdit`, so it reaches `typewizard.save` in the same propagation (a Typo shows `streak: 0` in `localStorage` at once). If the group size setting changes between sessions, the stored Bonus stays as written until the next Kill or Typo; the Round never trusts it.

`Game.Scene` (the meter below is the rest view; its animations and the Hit feedback are in "Hit and Streak feedback"): right after the Player comes one `Group` at the Player holding the meter (a 2 x 0.25 track `#2a3140` centred 1.6 above, and a fill of `(streak mod group) / group` of the width, left aligned, in `shotColour`; no fill node at 0) and the "+N" label (left edge 1.4 right of the Player, bar height, 0.8 high, `AnchorLeft`, in the same colour; absent at Bonus 0). The overlay (world-height units, origin at the screen centre) holds "Points N" and "Total N" right-anchored at the top-right, and "Streak N" centred at the bottom, in the letter default colour; top-left (Lives) and bottom-left (Esc hint) are empty for ticket 19. `shotColour :: Settings -> Int -> Colour` (argument: the Streak) is the 11-stop ramp: stop = `min 10 (streak / group size)`, each channel linearly interpolated between the settings' `shotStartColour` and `shotEndColour` (display values, not linear light), so it spans 10 groups whatever the group size. Ticket 20 reuses it for the Shot.

### Hits, Lives, Round end, Summary and blur

`Game.State`: after the Enemies move in a Tick, an Enemy within `contactDistance` (+1e-6 for rounding) of the Player with no Grace Period active is a Hit: `lives - 1` and `graceStart = Just roundTime`. Several touching Enemies are still one Hit per moment. Grace is active while `roundTime < graceStart + gracePeriod`; the first Tick at or after that clears it and, if an Enemy still touches, the next Hit comes at once with its Grace starting at the scheduled end of the last one (so a parked Enemy costs a Life every Grace Period with no drift). A Hit never touches the Streak, and Enemies are not removed by touching. Lives come from the Round's `startingLives` snapshot; the Grace clock is Round time (the clamped Tick sum), so blur and hidden tabs never count.

At 0 Lives `endRound` makes the Phase `Over`: Focus and Lock drop, Enemies are discarded with no Points, `totalPoints` becomes carried-in plus Round Points (the banked value), and `roundResult :: Maybe RoundResult` (`resPoints`, `resTotalPoints`, `resWpm`, `resAccuracy`, `resKills`, `resLongestStreak`, `resStreak`) is set. Over ignores every input but `Start` and `Aspect`, so counters, `roundTime` and so WPM and Accuracy are final. `roundEnded old new` is `Just result` only for a Running to Over pair, and `bankRound result save` adds `resPoints` to the saved Total Points: `Frontend.Game` emits `goRoundEnded` from `roundEnded` over `current gameState` and `updated gameState`, and `Frontend.Page` (the app root) turns it into a `Save` edit (`bankRound`) that the existing persistence `performEvent_` stores to `typewizard.save`. A state re-emitted while Over is not a transition, so a Round banks once. Abandoning (Menu, Escape) never reaches Over and banks nothing.

The Round Summary is a DOM panel (`div.round-summary[data-summary]`, in `Frontend.Game`) shown while `roundResult` is set: a table whose rows are `tr[data-row=points|total|wpm|accuracy|kills|longest|streak]` in that order (`Game.Summary.summaryRows`; WPM and Accuracy to one decimal, Accuracy with `%`), then "Play again" and "Back to start". "Play again" and Enter (only while Over) fire `Start` with a fresh seed and the current `Dynamic Save` (so the Streak and banked Total Points carry); "Back to start", Escape and the Menu control go to the Start page. The key shim also reports `Enter` (not when a button or link has the focus), `Escape` and `Other` (any other key), and listens to the window's `blur`, `focus` and `mousedown` (reported as `Blur`, `Focus`, `Click`), all only while the canvas is attached.

Blur: `Blur` sets `paused` (Running only) and clears `windowFocused`; a paused `Tick` only moves `lastTime` (dt 0, so nothing moves, spawns or advances Grace, and there is no jump when it resumes), and `Focus` sets `windowFocused` again. While paused, the first `Key` (any key), `Tab` or `Click` after `Focus` clears `paused` and is swallowed (it is not a Keystroke); before `Focus` they do nothing. A DOM overlay `div.paused-overlay[data-paused]` reads "Paused, click or press any key to resume". Blur freezes the Round logic only: `buildScene` still gets the frame time (spec section 14, item 7). Blur while Over or Idle does nothing.

HUD: `Game.Scene` draws the Lives row at the overlay's top-left (one 0.4 square per starting Life, 0.2 apart, white while kept, `#2a3140` once lost), and "Esc: menu" (0.6 high, `#7d8590`, left-anchored) bottom-left. The DOM Menu control moved to the top-centre so the top-left corner is free for the Lives.

### Shot and Plus Signs

One `KillAnim` record per Kill is appended to `GameState.killAnims` (`Game.State`): `kaStart`, the Player centre (`kaFrom`), the Enemy's position at the Kill (`kaTo`), its Tier, `kaStreak`, `kaPoints`, the three durations (`shotDuration`, `plusHold`, `plusFlyDuration`, taken from the Round's snapshot) and `kaSigns`, one `PlusSign {psOffset, psDelay}` per Point up to `plusDrawCap` (the cap limits records drawn, never Points). The step only appends a record at a Kill and drops expired ones on a Tick; `Game.Scene.killNodes` evaluates and eases them at `Frame.time`, so the Scene holds only positions, scales and colours.

- **Time base.** Records and the builder use the rAF timestamp in seconds: a record starts at `lastTime` (the previous Tick's raw timestamp; 0 before any Tick), so a Kill, which comes from a key event, starts up to one frame early. `roundTime` (the clamped clock) is not used. A record expires on the first Tick whose timestamp reaches its end (`killAnimEnd`: the last sign's arrival, hold, delay and fly), in every Phase: a paused (blurred) Round still expires, because Ticks still arrive, and the builder's clock never pauses (spec section 14 item 7). `Start` clears the records.
- **Round end.** `endRound` keeps `killAnims`. In `Over` a Tick only expires records (it does not even move `lastTime`), so the Plus Signs finish behind the Summary and the rest of the state stays frozen.
- **Streak value.** The Shot and the Plus Signs use `shotColour cfg kaStreak` with `kaStreak` the Streak after the Kill (the Kill increments it first), as the meter does: carried Streak 9 and a Kill gives Streak 10 (stop 1) and 2 Points.
- **Shot.** A `Triangle` 0.5 by 0.3 (apex along +x at rotation 0) whose centre goes from the Player to the Enemy position with quadratic ease-out (`1 - (1 - p)^2`), rotated by `atan2` of the travel, for `shotDuration`. At arrival it is no longer drawn.
- **Dying Enemy.** The logic removes the Enemy at the Kill (Focus and typing never see a Shot in flight). The spec says the Enemy is removed on arrival, so the builder draws a Tier-coloured 1.0 square at the recorded position, without its Word, until the Shot arrives. Draw order after the live Enemies: dying squares, Shots, Plus Signs.
- **Plus Signs.** At arrival (`kaStart + shotDuration`) each sign appears at the Enemy position plus its offset (uniform in the disc of `plusSpreadRadius`), holds `plusHold`, flies after its delay (uniform in 0 to 0.15 s) to the Player over `plusFlyDuration` with `p^2`, and over the last 0.15 s shrinks to 0.3x and fades (alpha 1 to 0). It is a `Group` of two overlapping `Square`s (a 0.5 by 0.1 bar and a 0.1 by 0.5 bar). Constants that are not settings are in `Game.Layout` (`plusMaxDelay`, `plusShrinkTime`, `plusShrinkScale`, ...). The random parameters come from `GameState.animRng`, a generator derived from the Round's seed (`seed xor` a constant) and separate from `rng`, so animations never change the Words or spawn angles of a seed.
- **Hook** (`?hook`) gained `lastTime`, `killAnims` (records held), `shots` and `plusSigns` (in flight and on show at `lastTime`; frozen in `Over`, where `lastTime` stops), and `anims` (start, end, endpoints, Streak, Points, signs).
- **Tests:** `common/test/AnimationTests.hs` (records, Shot positions and colours, Plus Sign timing, cap, expiry, Round end). Browser check: seed `typewizard.settings` with slow animations (`shotDuration` 1, `plusHold` 1, `plusFlyDuration` 2, `plusSpreadRadius` 2) and `typewizard.save` with a Streak of 7, open `?hook`, and compare screenshots with the hook counts.

### Camera

`GameState.camera` is a `CameraAnim` record (`Game.State`): `caStart` (the Tick clock), `caFrom` (the start centre), `caTarget` and `caTau` (a snapshot of `cameraTimeConstant`). `Game.Scene.buildScene` puts `cameraCentreAt frame.time st.camera` as `sceneCamera`, with `centre(t) = target + (from - target) * exp (-(t - start) / tau)` (before the start it is `from`; a `tau` of 0 or less is the target). The dot grid is a world node, so the renderer anchors it to that centre (it scrolls with a pan, in whole spacings); the background square follows the Camera; the Player, Enemies, Words, Streak Meter, "+N", Shots and Plus Signs are in world coordinates; the HUD is overlay and never moves. The step never changes the Camera on a Tick.

- **When a record is made.** `step` wraps the rules (`stepRules`) and, when the Focused Enemy's id differs from before the input (Focus starts, Kill, Tab, Round end), computes the new target and makes a new record only if it differs from `caTarget`. Typing more letters, a Typo (Lock), Ticks and a moving Enemy change nothing. The new record starts at `lastTime` from `cameraCentreAt lastTime` of the old one, so a retarget in the middle of a pan or a return is continuous with the last frame drawn. Like Kill records it starts up to one frame early (a key event falls between two frames; 0 before any Tick).
- **Target (`cameraTarget cfg aspect player enemyPos`).** The default view is the Camera centred on the Player: half-height `worldHeight / 2`, half-width that times the aspect. An Enemy inside it (edges inclusive) leaves the target on the Player: no pan, even when it sits in the 2-unit inset zone. Outside it, each axis is shifted by `sign d * max 0 (|d| - (half - cameraInset))` (so an axis already inside the inset is not shifted, even when the other axis is outside; this is the literal smallest shift onto the inset rectangle), then clamped per axis to `max 0 (half - playerMargin)` so the Player (the origin) stays at least `playerMargin` inside every edge. The Settings field is `playerMargin` (the ticket says "cameraPlayerMargin").
- **Held target.** The target is computed once, from the Enemy's position at the moment of Focus, and held while the Word is typed (Focused, Locked, more letters). The Enemy only moves toward the Player, and both lie inside the held visible rectangle, which is convex, so it stays on screen; it is never chased. A Kill, a Tab or Round end (`endRound` drops Focus, so Over eases back behind the Summary; the builder's clock does not stop, but `lastTime` and so the hook's `camera.centre` freeze in Over) retargets to the Player with the same time constant. `Start` resets the Camera to rest on the Player (no easing; a "Play again" from a not yet converged Over Camera jumps, usually imperceptibly as the return takes a few time constants). `Aspect` while Focused does not retarget.
- **Spec tension (margin vs inset), reported.** The spec asks for a 2-unit inset and a 3-unit Player margin. They conflict when the Enemy is far: with the default height 20 and a 16:9 view the vertical clamp is 7 units, so an Enemy spawning straight above (ring radius is about 21) cannot be brought on screen by the pan alone (it still approaches). The Player margin wins by the ticket's instruction and the spec's "the Player stays at least 3 units inside every screen edge". With a margin larger than the half-view the Camera cannot move on that axis.
- **Spawn ring.** `spawnOne` reads only the Player position and `spawnRingRadius`, never the Camera (spec section 14 item 9); a test spawns with a panned Camera and compares with a game that never Focused.
- **Hook** (`?hook`) gained `camera`: `start`, `from`, `target`, `tau`, and `centre` (evaluated at `lastTime`).
- **Tests:** `common/test/CameraTests.hs`. Browser check: seed `typewizard.settings` with `cameraTimeConstant: 1`, slow Enemies (`enemySpeed: 0.5`), `gracePeriod: 10`, `intervalStart: 5`, open `?hook`, type the first letter of an Enemy outside the view and compare the hook's record with screenshots (Player and dot pixels move, the HUD does not); `scratchpad/check21.mjs` of the ticket run did exactly this in headless Chrome.

### Hit and Streak feedback

Two more start-time records in `GameState`, on the Camera's and the Kill records' clock (`lastTime`, the raw rAF timestamp; the step only creates and expires them, `buildScene` evaluates them at `Frame.time`; the Round-time `graceStart` and `groupCompletedAt` stay as they were because `roundTime` is a clamped, different clock). All durations and the 30% / 25% / 1.4x values are constants in `Game.Layout` (`blinkPeriod`, `blinkDimAlpha`, `hitFlashAlpha`, `hitFlashTime`, `meterGrowTime`, `meterFlashTime`, `meterEmptyTime`, `labelPopTime`, `labelPopScale`, `typoFadeTime`), not settings. Every ramp is linear.

- **Hit** (`hitAt :: Maybe Double`). Set to `lastTime` by every Hit (the Tick that noticed it, so a re-Hit at the scheduled Grace end is up to one frame late; the Hit that ends the Round sets it too). `playerAlphaAt st t`: full opacity for `blinkPeriod`, 25% for `blinkPeriod`, ... counting from the Hit (full first), only while `graceActive st`, else 1. So the blink lasts the whole Grace Period, restarts on every re-Hit, stops when Grace ends and never shows in `Over` (Round end clears Grace). While paused Grace is frozen, so the blink goes on. `hitFlashAt st t`: 0.30 at the Hit, linear to 0 at +0.3 s, 0 before and after. It is drawn as one screen-fixed red `Square` at the end of `sceneOverlay` (on top of the HUD), centre (0,0), `worldHeight * aspect + 2` by `worldHeight + 2` so it always covers the view, only while its alpha is above 0. A re-Hit (parked Enemy every Grace Period, or any Hit during an old flash) restarts from 0.30 because `hitAt` is replaced. In `Over` the blink is gone and the flash finishes behind the Summary. `expire` drops `hitAt` once Grace is over and the flash has run out.
- **Meter** (`meterAnim :: Maybe MeterAnim`: `maStart`, `maKind` (`MeterGrow | MeterComplete | MeterTypo`), `maFrom` (a `MeterView`: fill, white flag, Streak for the colour, label bonus/scale/alpha as shown at the event), `maStreak` (Streak after the event)). One record, replaced by the latest Kill or Typo; `meterViewAt st t` evaluates it, or the static view of the Streak when there is none (so with no record the scene is what ticket 18 drew). Grow: the fill goes from the fill shown at the Kill to `(Streak mod group) / group` over 0.1 s. Complete (the Kill that completes a group): the bar is FULL and white for 0.15 s, then empties linearly over 0.25 s in the Streak's `shotColour`; the "+N" label scales 1.4x to 1x over 0.2 s (scale on the `Text` transform, about its left anchor); no label at Bonus 0. Typo: the fill shown falls to 0 and the label's alpha to 0 over 0.2 s, keeping the pre-Typo colour, text and scale; the state's Streak is 0 at once and a Typo with nothing on show makes no record. `expire` drops the record when it ends (the rest view equals its final frame).
- **Back-to-back rule.** A new event starts from the view displayed at `lastTime` (evaluated from the old record), so the display is continuous: Kill after Kill grows from the shown fill; a Kill or Typo during a completion's flash or emptying starts from the shown fill (the white drops); a Typo fades the label from its shown scale and alpha; a Kill during the pop finishes the pop at its own speed (the record then lasts as long as the pop needs). A Kill is evaluated from the Tick clock, so, as for the Shot, it starts up to one frame early.
- **Over.** Records survive `endRound` and finish behind the Summary; `Start` clears them.
- **Hook** (`?hook`) gained `hitAt` and `feedback`, all evaluated at `lastTime`: `playerAlpha`, `flashAlpha`, `meterFill`, `meterWhite`, `labelBonus`, `labelScale`, `labelAlpha` (the last three `null` without a label) and `meterAnim` (`{kind, start, end}` or `null`).
- **Tests:** `common/test/FeedbackTests.hs` (blink, flash, re-Hit, Grow, Complete, Typo, back-to-back, expiry, Over, purity). Browser check: `scratchpad/check22.mjs` of the ticket run (headless Chrome, 1200x800). It seeds `typewizard.settings` (Hit: `enemySpeed` 5, `intervalStart` 6, `gracePeriod` 2, `startingLives` 10; Meter: `enemySpeed` 0.5, `gracePeriod` 10) and `typewizard.save` (Streak 9 for a completion, 14 for a Grow then a Typo), and records every frame from inside the page: it wraps `WebGL2RenderingContext.prototype.drawArraysInstanced` and, right after the game's own draw, reads the hook state and pixels with `readPixels` (Player centre, a background pixel, the meter row, the label rectangle). That gives per-frame evidence for the 0.1 to 0.3 s animations without any timing window.

### Measuring the JS boundary (dev only)

Open the Game page with `?bench` in the URL (for example `http://localhost:8765/type-wizard/?bench`; the page is a single page, so the query is only read, not routed). After a few seconds read `window.TypeWizardBench` (100,000 JS FFI calls from Haskell, 100,000 JS-to-Haskell `wrapper sync` calls, 1,000 jsaddle calls, in milliseconds) and, from `TypeWizardRenderer.stats`, `callbackMs / frames` (the whole per-frame Haskell callback: pull, flatten, pack and the draw call) and `drawMs / frames` (the JS side of the draw call). Without `?bench` no timing is done. The code is `Frontend.Bench` and the `bench` flag in `renderer.js`.

## Settings and saved progress

`Game.Settings` is the `Settings` record plus a field table (default, min, max, group); the Settings page, the JSON codec, the clamp and the group resets all run from that table. The stored form is flat JSON under `localStorage` key `typewizard.settings` with `version: 1`. Saved progress (`Game.Save`: Total Points, Streak, Bonus) is `typewizard.save`, separate. `Frontend.Page` holds `Dynamic Settings` and `Dynamic Save` above the page switch, loads them once in the browser and writes them back on every change. `static/src/js/storage.js` wraps every `localStorage` access in try/catch; with storage blocked the game uses defaults and in-memory state. To add a setting: add the record field, its default, and one line in `fields`; no other code changes.

## Pages

`Frontend.Page` holds a `Dynamic Page` (`Start | Game | Settings`) above the page switch. There is no URL routing: `FrontendRoute` has one constructor, there is one exported `index.html`, and the address bar never changes. Each page is a `<section data-page="start|game|settings">` with an `<h1>` title. The Game page's section is pinned to the top over a full-window canvas (`Frontend.Game`), with the Menu control top-centre.

## Word list

`frontend/words/words.txt` is embedded with `file-embed`. Three rules, each learned from a failed build (spec section 10):

1. The file is tracked by git and is not under `frontend/data/` (gitignored).
2. `frontend/frontend.cabal` has `extra-source-files: words/words.txt`.
3. `Frontend.Words` uses `makeRelativeToProject "words/words.txt" >>= embedFile`, and `file-embed` and `bytestring` are in the library's main `build-depends`.

The Start page shows `Words: N`, the line count of the embedded file.

## Deploy (GitHub Pages sub-path)

The site is served from `https://<owner>.github.io/<repo>/`. `.github/workflows/deploy.yml` (on push to `main`, or manually) runs `nix build -L`, then:

```
tools/export-site.sh result site "/<repo>/"
```

which runs the built backend once, saves its page as `site/index.html`, copies the asset folders out of the Nix store as plain files (`site/static`, `site/ghcjs`), and rewrites two things so the page works under the sub-path: `<base href="/">` becomes `<base href="/<repo>/">`, and the absolute `"/ghcjs/` links become relative `"ghcjs/`. The script fails if Obelisk stops emitting those strings. The workflow passes the repository name as the base, so nothing is hard-coded. `site/` is then pushed to the `gh-pages` branch.

The router needs no change: any path that matches no route decodes to the one frontend route, so `/<repo>/` loads the app.

Enable it once in the repository settings: Pages, source "Deploy from a branch", branch `gh-pages`. Pushing, enabling Pages and workflow runs are the owner's.

Check a deploy locally by serving the exported folder from a sub-directory:

```
tools/export-site.sh result site /type-wizard/
mkdir -p /tmp/pages && rm -rf /tmp/pages/type-wizard && cp -R site /tmp/pages/type-wizard
python3 -m http.server 8765 --directory /tmp/pages
# open http://localhost:8765/type-wizard/
```
