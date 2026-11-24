# 15: Renderer and an empty game page

**What to build:** A separate `renderer` package with the public interface in spec section 5, and a Game page that draws a canvas showing a Player square, a dot grid and overlay text, so the renderer is proven before any game logic exists.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 13

**Status:** done

- [x] The renderer package exposes only the public types and initRenderer, getViewport and startRenderLoop
- [x] Pure tests cover transform composition, node order in flatten, the camera matrix and the packed buffer layout including text to glyph instances
- [x] The Game page shows the Player, the dot grid and overlay text, scales with the window and device pixel ratio, and redraws on resize
- [x] One JS call is made per frame; the loop stops by itself when the canvas leaves the document and restarts on a fresh visit
- [x] If WebGL is unavailable the page shows an error instead of a blank canvas
- [x] The JS boundary cost per call is measured and recorded in the ticket
- [x] A short manual browser checklist for the JS executor is written

## Answer

Done. Mechanisms, one per criterion (browser checks drive the built page, exported with `tools/export-site.sh` and served at `http://localhost:8765/type-wizard/`, in headless Chrome over the DevTools Protocol; screenshots were also read by eye):

1. **Interface.** `renderer/src/Renderer.hs` has an explicit export list: `Scene`, `Camera`, `Node`, `Anchor`, `Transform`, `Colour`, `V2`, `Viewport`, `Frame` (all `(..)`), `Renderer` (abstract), `initRenderer`, `getViewport`, `startRenderLoop`. `frontend` imports `Renderer` only. `V2` is the one addition; the spec uses it without defining it. flatten, packing, the FFI and the JS are in `Renderer.Internal` (exposed for tests only, not imported by the game) and `Renderer.Js` (not exposed).
2. **Pure tests.** `nix build .#checks.aarch64-darwin.renderer-test`: 36 cases, 0 failures (HUnit, `renderer/test/Main.hs`): transform composition (nested, rotated, non-uniform scale, three levels), node order (siblings, groups, world before overlay, DotGrid in tree position), the camera matrix (centre, height, aspect, exact column-major values, pan, overlay, degenerate inputs), dot grid extent and cap, text (anchors, spaces, glyph indices, transforms, colours) and the packed buffer (header, count, field order, instance order, little-endian bytes read back from memory). `common-test` still passes (56 cases).
3. **Game page.** Pixel evidence from `Page.captureScreenshot` decoded in the page: at 800x600, DPR 1 the Player is `#f5f5f5` at the centre and 36 px wide (1.2 units at 30 px per unit), the background is `#0e1117`, dots (`#2a3140`) sit 2 units right of and above the Player and not 1 unit away, 1169 light pixels sit in the title area and 407 in the `Esc: menu` area, none top-right. `Emulation.setDeviceMetricsOverride`: 1000x500 at DPR 2 gives a 2000x1000 backing store and a 60 px Player; 640x480 at DPR 1 gives a 640x480 store and a 28 px Player; DPR 3 at the same CSS size gives 1920x1440. The Menu button hit-tests above the canvas. Screenshots: `game-800x600.png`, `game-1000x500-dpr2.png`, `game-640x480.png` under the session scratchpad.
4. **One call per frame, stop and restart.** `TypeWizardRenderer.stats.frames` and `.draws` over one second: 60 and 60 (the draw is the only call Haskell makes into JS per frame; `draws == frames` within 1). Clicking Menu removed the canvas; `stopped` went to 1 and `frames` stayed frozen (482 and 482 over 1.5 s). Play again: `created` 2, `started` 2, frames advance, the page draws; Menu again: `stopped` 2, frames frozen.
5. **WebGL unavailable.** Two ways, both in a fresh page: `HTMLCanvasElement.prototype.getContext` returning null for `webgl*` (`Page.addScriptToEvaluateOnNewDocument`), and Chrome started with `--disable-gpu --disable-3d-apis` (which gives no WebGL at all on this machine). Both show `p[data-error=renderer]` with "WebGL is not available in this browser, so the game cannot be drawn.", laid out over the window, no loop started (`started` 0), Menu still works.
6. **Per-call cost** (headless Chrome 158.0.8127.88 on an Apple M1 Max, Metal, release wasm build, `?bench`, two runs):
   - 100,000 trivial `unsafe` JS FFI calls from Haskell: 16.7 and 17.4 ms, about **0.17 us per call**.
   - 100,000 calls from JS into a Haskell `wrapper sync` callback (the direction the frame callback takes): 137.8 and 131.7 ms, about **1.3 us per call**.
   - 1,000 jsaddle calls (`jsg "performance" # "now"`, results not awaited): 2.2 ms, about 2.2 us each. This is only the cost of queueing a command; a jsaddle call that needs its answer is a full JSON round trip and was not measured. The renderer uses jsaddle only for `create` and `viewport`, once per canvas.
   - The per-frame renderer callback (pull, flatten of about 270 instances, pack, the draw call, GL work included): **0.63 ms per frame** on average over 240 frames at 60 fps (4% of a 16.7 ms frame); the JS side of the draw call (buffer upload and draw) is 0.06 ms of that.
   So one call per frame is cheap on this toolchain; the cost that matters is Haskell work per frame, not the boundary. Spec section 15 is updated.
7. **Checklist.** `README.md`, section "Renderer", "Browser checklist". The run above covers items 1 to 6 of it (resize, DPR change, detach stops the loop, WebGL-unavailable message, no console errors; the only logged item was a `favicon.ico` 404 from the static server). Not run by hand: dragging a window between real displays and browser zoom (the DPR override stands in for them).

Gates: `nix build .#haskell-nix --cores 4 -L` (wasm and native) built with no `warning: [GHC` lines for any module; `renderer-test` and `common-test` green. AGENTS.md names no gates; these are recorded in `README.md`.

Decisions not in the spec or tickets:

- **Package wiring.** `renderer` is a normal cabal package in `cabal.project` (no nix change beyond the check): the Obelisk/nix build accepted it, so the fallback was not used. The flake check is `checks.<system>.renderer-test` (`hsPkgs.renderer.checks.renderer-test`). `frontend` and `renderer` need `ghc-experimental` on wasm for `GHC.Wasm.Prim.JSVal` (it is in the compiler's global package set). `Renderer.Internal` is exposed and documented as test-only; a hidden sublibrary was not used.
- **Buffer passing.** Per spec: a pointer and an instance count over wasm memory, through the JS FFI, not jsaddle. Because jsaddle's `function` callbacks are asynchronous (JSON, a later task), the per-frame callback is a `wrapper sync` export, so JS runs the frame in its own rAF task and the draw happens in the same task. The pull function therefore runs inside a synchronous callback: it must not block (an `IORef`, as spec 6 says). A frame error message crosses as UTF-8 bytes in memory, because a `JSString` argument to a `foreign import javascript` fails to compile here (`HsJSString` is undeclared in the C stub).
- **Buffer layout.** 18-float header (world matrix, overlay matrix; column-major 3x3) then 13 floats per instance: `kind glyph space a b c d tx ty r g b a`. The overlay uses the Camera's world height and a centre of (0,0); both matrices are uniforms and `space` picks one, so there is one draw call for world and overlay.
- **Shapes.** WebGL 2 only (instancing and derivatives without extensions); no WebGL 2 gives `Left`. One unit quad; a Triangle's apex is the middle of the right edge (rotation 0 points along +x); a dot is an anti-aliased circle in the shader.
- **Text.** A glyph cell is 0.6 wide by 1 tall in units of the text height; the line is centred vertically on the position (not on a baseline). Space draws nothing; characters outside printable ASCII draw as `?`. The atlas is 16x6 cells of 36x60 px, mipmapped. The builder should choose the height argument as the em height: the 0.9 "cap height" of spec section 9 is roughly 0.7 of the em, so about 1.25 for a 0.9 cap height.
- **Viewport** is the canvas CSS size in pixels (width, height, width/height).
- **DotGrid** ignores the transforms of the groups around it and covers the visible area of its space (the world follows the Camera centre, the overlay is centred on the origin). A grid that would need more than 50,000 dots draws none.
- **No clear colour in a Scene.** The background is the first node in `sceneWorld`, a `Square` larger than the view; the GL clear is transparent. The scene builder (a later ticket) has to cover the view as the Camera pans.
- **`Nothing` from the pull** redraws the last scene at the current viewport (so a resize does not blank the canvas); before any scene exists nothing is drawn.
- **Canvas attach.** Reflex builds the canvas detached and attaches it a moment later, so "stop when `isConnected` is false" would have stopped the loop before it began (the first run did exactly that). A canvas now gets 120 frames to arrive; after it has been seen connected, the first disconnected frame stops the loop.
- **Game page.** `Frontend.Game.gameCanvas` builds the canvas inside `prerender_`, starts the renderer on post-build, and shows the error from `initRenderer`. The world height is read from the Settings once, as the page opens. The demo scene (`demoScene`) is a pure function in that module with the spec's colours as constants; it is not `buildScene`. The page's `section` is fixed at the top-left over a full-window canvas, and the demo title sits to the right of the Menu control so they do not overlap. `Esc: menu` is displayed only; the key is handled in a later ticket.
- **Bench.** `Frontend.Bench`, run only with `?bench` in the page URL after the renderer has started (read through jsaddle), plus timing in `renderer.js` under the same flag. Nothing runs without it.
- The `stats` counters on `window.TypeWizardRenderer` are always on (cheap); they are the test hook.
- Spec section 5 says `Frame`'s `time` is in seconds: the callback divides the rAF timestamp by 1000.
