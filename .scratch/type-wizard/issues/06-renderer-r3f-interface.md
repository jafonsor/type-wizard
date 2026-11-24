Type: grilling
Status: resolved
Blocked by: 01

# Renderer: the react-three-fiber-like interface

## Question

Decide the module that mimics react-three-fiber for WebGL, using the findings from the wasm interop research.

- What "mimics react-three-fiber" means in Haskell: a declarative tree of elements (mesh, group, camera) that is reconciled against the retained GPU state, versus an immediate draw list. What is the smallest set of primitives the game needs: square, triangle, dot grid, text, plus the sign.
- Where the line sits between Haskell and JS: which parts are Haskell data and which part is the JS shim that owns the `WebGLRenderingContext`.
- How text is drawn (glyph atlas, canvas 2D texture, SDF), and how per-letter colour (green, red, default) is expressed.
- How the camera and the resize and device-pixel-ratio handling are exposed.
- The public interface of the module, written as types, and what is deliberately hidden (a deep module).
- How the renderer is checked without a browser.

## Answer

Resolved by grilling, using the render layer in `~/devs/flor-do-mar` (ADR-0003 scene graph, ADR-0007 one browser task per frame, ADR-0012 frame clock, `RenderLayerTest.hs`) as precedent and the findings in `research/01-wasm-webgl-interop.md`.

**Architecture.** Reuse flor-do-mar's design as a new, small, 2D module, not a copy of its code: named-free declarative node tree, pure flatten, one packed buffer per frame, a JS executor that owns GL. Differences from flor-do-mar: orthographic 2D camera, no lighting, no stroke or ring primitives, no geometry upload cache (shapes are fixed and live in the JS executor), a packed `Float32Array` over wasm memory instead of JSON (jsaddle-wasm is in-process), and a text primitive (flor-do-mar has none).

**Package.** A separate cabal library `renderer/`, listed in `cabal.project` beside `common` and `frontend`; `frontend` depends on it through the public interface only. Fallback if the Obelisk/nix build objects: a module directory under `frontend/src` with an explicit export list.

**Public interface** (everything else is hidden):

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
data Colour = Colour Float Float Float Float        -- straight RGBA 0..1, no colour-space handling
data Viewport = Viewport { width, height, aspect :: Float }
data Frame    = Frame { viewport :: Viewport, time :: Double }  -- time: rAF timestamp, seconds (amended by the scene ticket)

initRenderer    :: JSVal -> JSM (Either Text Renderer)          -- receives the canvas Reflex created
getViewport     :: Renderer -> JSM Viewport
startRenderLoop :: Renderer -> (Frame -> IO (Maybe Scene)) -> JSM ()
```

`startRenderLoop` takes the viewport as an argument to the pull function, so the viewport is read once per frame inside the frame call and the spawn-radius and camera logic never read the DOM on their own. `getViewport` stays for one-off reads.

**Rules.**
- No z and no depth test. Tree order is draw order (later on top), alpha blending on. `sceneWorld` draws first, then `sceneOverlay`. A `DotGrid` draws where it sits in the tree, so the scene builder puts it first.
- The camera is a centre plus a fixed visible world height; width follows the aspect ratio. The world height is a setting (camera group of the settings schema).
- `sceneOverlay` is screen-fixed, in world-height units, origin at the viewport centre, unaffected by the camera. The renderer always offers it. Whether the HUD (Lives, Points, Streak, WPM) uses it or DOM text is left to the scene-structure and visual-spec tickets. The Streak Meter and the "+N" sit next to the Player, so they are world nodes.
- The plus sign is a `Group` of two `Square`s. The dot grid is one node: spacing, radius and colour, with its extent and offset from the camera.
- Text: one font, one line, printable ASCII from a single canvas-2D monospace atlas built once after `document.fonts.ready`, drawn as instanced quads. Anchoring is horizontal only, baseline-centred vertically. No wrapping, no font choice. Per-letter colour is per-character RGBA; the renderer knows nothing about typed, locked or default letter states.
- Colour: settings store display colours, the scene builder converts to `Colour`; the renderer treats values as opaque.
- Lifecycle: Reflex creates the canvas; `initRenderer` creates the GL context, sizes the backing store from CSS size times `devicePixelRatio` and observes resizes itself. If WebGL is unavailable it returns `Left`, and the page shows an error. No context-loss recovery in v1.
- Frame loop: the JS shim owns rAF and calls Haskell once per frame. Each frame the pull function returns the latest Scene (or `Nothing`, which keeps the last frame); the loop flattens it, packs the instance buffer and makes **one** unsafe JSFFI call with a pointer and an instance count. A failing frame is reported through `console.error` and the next frame is attempted; a killed thread is rethrown. The loop stops by itself when the canvas is no longer connected to the document (`isConnected` checked once per frame); there is no stop function.
- How the handoff behind the pull function works (`MVar`, `IORef`, `TVar`) is not decided here; it belongs to the FRP network ticket. The renderer only assumes a non-blocking `IO (Maybe Scene)`.

**Hidden:** flatten, instance buffer layout and packing, atlas, shaders, the FFI call, canvas sizing and DPR, resize observation.

**Checking without a browser:** tests cover the pure layer only, following `RenderLayerTest.hs`: transform composition and node order in flatten, the camera matrix, and the packed buffer (instance count, byte layout, text to glyph instances). `flatten` and the encoder are exposed for tests from an internal module. The JS executor and the GL output are checked by eye in the browser; no headless-GL tooling.

**Left open for later tickets:** Scene type and handoff (07), tick source and network (08), HUD in overlay vs DOM and all colours, sizes and spacings (11), and the per-call cost of the JS boundary (a spike, still in the map's fog).
