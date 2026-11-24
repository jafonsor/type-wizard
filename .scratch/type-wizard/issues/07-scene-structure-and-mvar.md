Type: grilling
Status: resolved
Blocked by: 04, 06

# Scene data structure and the MVar handoff

## Question

Decide the module that builds the Scene data structure and calls the renderer interface, and the handoff between game logic and rendering.

- The Scene type: what it holds (entities with positions, Word display state per letter, Shot and Plus Sign animations, Camera, Streak Meter, Bonus, HUD values) and whether it holds absolute times or already-evaluated animation state.
- How the game logic produces a Scene and writes it to the `MVar`, and how the frame render takes it (read versus take, what happens when the logic is slower or faster than the frame rate).
- Who owns animation interpolation (the logic step or the render step) and the time source.
- The module boundary: the Scene builder depends on the game state and the renderer interface, and nothing depends back.
- How a Scene is checked headlessly.

## Answer

Resolved by grilling. The user delegated the handoff shape on the first question ("maybe it's better a behaviour, use whatever you think is best") and confirmed the rest.

**Pipeline.** `GameState` (owned by the FRP network as a `Dynamic GameState`, so game logic is behaviour-shaped and never sees the renderer) -> `buildScene` (pure) -> the renderer's `Scene` (06). The Scene is a per-frame product, not something game logic writes.

**Handoff.** The renderer's pull function runs outside Reflex and must return synchronously, so one **latest-value cell** bridges the two. It is written only by `performEvent_` on `updated gameState` and read only by the pull function. Semantics: the writer overwrites, the reader peeks (never takes, never blocks). The pull returns `Nothing` only before the first state exists. After that it returns `Just` a freshly built Scene on every frame, because the Scene depends on the frame time. A slow logic step means the same state is rebuilt with a newer time, so animations keep running. A fast one drops intermediate states. The cell's type (`MVar` used non-blockingly, `IORef` or `TVar`) is decided in the FRP network ticket; the semantics above are fixed here.

**Builder.** `buildScene :: Settings -> Frame -> GameState -> Scene`, pure. `Frame` is `Frame { viewport :: Viewport, time :: Double }` (seconds on the `performance.now` clock, the rAF timestamp). The renderer's `startRenderLoop` pull argument widens from `Viewport` to `Frame`. Logic ticks use the same clock.

**Animation.** Shots, Plus Signs, the Camera pan and the Camera ease-back live in `GameState` as start-time records: start time, duration (from the Round's settings snapshot) and endpoints. `buildScene` evaluates and eases them at `Frame.time`. The logic step only creates records and drops expired ones. Enemy and Player positions are plain state advanced by the step. The Scene holds no times, only evaluated positions, scales and colours. Word display state (typed count, Lock) is plain state; the builder maps it to per-letter `Colour`s.

**HUD.** The in-Round HUD (Lives, Round Points, Total Points, Streak, and WPM if shown live) is renderer `Text` in `sceneOverlay`. The Streak Meter and "+N" are world nodes. The Round Summary, start page and settings page are DOM. Placement, sizes and colours belong to the visual ticket.

**Modules.** `Game.State` (types, pure step) depends on settings and the word list, not on the renderer. `Game.Scene` (`buildScene`) depends on `Game.State`, settings and the renderer's public types. Only the wiring that calls `startRenderLoop` depends on `Game.Scene`. Nothing depends back.

**Headless check.** Tests call `buildScene` with a hand-made `GameState`, settings and `Frame`, and assert through small query helpers (for example "letters 1 to 3 of Enemy 2's Word are green and letter 4 red", "Camera centre halfway at the midpoint of a pan", "Plus Sign count equals Points"). No golden files, and no `flatten`, which 06 already covers.

**Left open.** The cell type and the tick source (08). The exact `GameState` fields are a spec-assembly detail. What the Scene shows during the Round Summary and in-flight animations at Round end goes to the pages and visual tickets.
