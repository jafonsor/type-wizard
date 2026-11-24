Type: grilling
Status: resolved
Blocked by: 01, 04, 07

# FRP network architecture

## Question

Decide how the game logic sits inside the Reflex network.

- Research constraint: the wasm runtime is single-threaded, so there is no data race on an `MVar`, but blocking on one inside a synchronous callback is the hazard. Decide whether the handoff stays an `MVar` (non-blocking use only, per the user's brief) or becomes an `IORef`/`TVar`, and say so explicitly in the spec.
- The tick source (rAF or a fixed-step timer) and how the game step relates to frame rendering.
- Whether the game logic is a pure step function folded with `foldDyn` over keys and ticks, or distributed across the network. Where spawning randomness comes from and how it stays testable.
- The Events and Dynamics that cross module boundaries: key presses, ticks, settings, Round end, persisted totals.
- Where the Scene is written to the `MVar` (a `performEvent_` on each tick).
- How a Round starts and ends in the network, and how app-wide state survives page switches.
- How the pure step is tested without Reflex.

## Answer

Resolved by grilling; the user took the recommended option on every question.

**Cell.** An `IORef (Maybe GameState)` (plus the Round's `Settings` snapshot), not an `MVar`. This deliberately departs from the original brief's `MVar`, and the spec must say so. Reason: the runtime is single-threaded, so there is no race, and the only hazard is a blocking `takeMVar`/`readMVar` in a synchronous callback; `IORef` cannot block and gives the semantics fixed in the scene ticket (overwrite, peek). Written only by `performEvent_` on `updated gameState`; read only by the render pull (`readIORef`).

**Tick.** The JS shim owns rAF. Each frame it calls the render pull (which builds the Scene from the cell) and also fires one `Event t Double` tick carrying the rAF timestamp through `newTriggerEvent`. The step receives `dt = now - previous`, clamped to a setting (`maxTickDt`, add to the settings schema; suggested default 0.1 s). A hidden tab stops rAF, so the Round freezes and resumes without a jump. There is no explicit pause feature. Animations are start-time records evaluated at `Frame.time` (scene ticket), so they do not depend on the clamp.

**Logic shape.** One pure step: `step :: Settings -> Input -> GameState -> GameState` with `Input = Key Char | Tab | Tick Double | Start Seed`. The network merges the key, tab, tick and start Events into one `Event Input` and folds it with `foldDyn step`. Not distributed across Dynamics. `GameState` carries a `Phase` (`Idle | Running | Over`), the Round's Settings snapshot and a splitmix generator. The generator is seeded once from the clock at `Start`; tests pass a fixed seed, so spawning is deterministic with no IO and no Reflex. The step draws Word choice (no duplicates on screen, from the dictionary ticket) and spawn angle from the generator.

**Keys.** The JS shim listens to `keydown` on `window`, calls `preventDefault` for Tab in JS, drops `repeat` and non-letter keys, and fires one Event per Keystroke (`Char c` or `Tab`) through `newTriggerEvent`. It listens only while the game page's canvas is attached, so keys on the start and settings pages are untouched. No `wrapDomEvent`, so no dependence on jsaddle-wasm's sync path.

**Events and Dynamics crossing boundaries.**
- Above the page router (`subRoute_`): `Dynamic Settings` (settings ticket), `Dynamic Save` (Total Points, Streak/Bonus, persisted behind the load/save interface), and the persistence `performEvent_`s.
- Game page: owns `Dynamic GameState`, the merged `Event Input`, the render-loop start/stop, and the cell write.
- Out of the game page: `Event RoundEnded RoundResult` (Round Points, Kills, Longest Streak, WPM, Accuracy, final Streak), derived from the `Running -> Over` transition; the app root adds Round Points to Total Points and saves.

**Round lifecycle.** Entering the game page fires `Start seed`, which snapshots current Settings into `GameState` and resets per the rules ticket (carried: Streak, Total Points, Settings). `Over` freezes input and spawning and shows the Round Summary; "play again" fires `Start` again. The Streak is app-wide state: the game page reads it from `Dynamic Save` at `Start`, and writes it back on each change.
Leaving the game page mid-Round **abandons** it: the render loop stops with the canvas, no Round Points are banked and no Round Summary is shown. Streak stays at whatever it reached through Kills and Typos made before leaving, since it is persisted state, not Round state. (Pages ticket: confirm leaving is guarded or cheap enough that no confirm dialog is needed.)

**Testing.** `step` is pure with explicit `Settings`, `Input` and a seeded `GameState`, so headless tests fold a list of `Input`s and assert on the final or intermediate states (typo clears Streak, tab resets the Word, Grace Period re-Hit, spawn ramp per Tier, determinism for a fixed seed). No Reflex in any of them. A thin wiring layer (merge Events, `foldDyn step`, cell write) stays untested except by the running app.

**Left open.** The exact `GameState` and `Input` types are a spec-assembly detail. `maxTickDt` goes into the settings schema at assembly. The leave-mid-Round guard and the Round-end screen go to the pages ticket.
