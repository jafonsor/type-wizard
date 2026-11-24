# Research 01: WebGL, rAF loop and MVar from GHC wasm + reflex-dom

Ticket: `.scratch/type-wizard/issues/01-research-wasm-webgl-interop.md`
Date: 2026-11-24. Target: GHC wasm 9.12 (as in `~/devs/type-solution/prototype-reflex-wasm`), reflex-dom with jsaddle-wasm.

Source labels: [GHC-UG] GHC User's Guide, wasm chapter (https://ghc.gitlab.haskell.org/ghc/doc/users_guide/wasm.html); [jsaddle-wasm] `prototype-reflex-wasm/vendor/jsaddle-wasm` (0.1.2.1, patched); [jsffi.js] `prototype-reflex-wasm/dist/ghc_wasm_jsffi.js` (generated glue); [reflex-dom] reflex-dom-core source in the nix store copy of Obelisk's `deps/reflex-dom` (`.../reflex-dom-core/src/Reflex/Dom/{Main,Builder/Immediate}.hs`; the prototype pins submodule rev 7193774e, I did not diff the two); [Reflex] Hackage `reflex-0.9.3.3` `Reflex.TriggerEvent.Base`; [MDN] developer.mozilla.org; [TS] `~/devs/type-solution`.

Statements marked **(inference)** are not stated by a primary source; they are my reading of it and should be confirmed by the prototype step.

## Summary of decisions the facts support

1. A reflex-dom app on wasm does not run on raw JSFFI. Every DOM call goes through **jsaddle-wasm**, which serialises commands as JSON batches. That is fine for UI, wrong for a 60 fps WebGL loop. Do WebGL through either (a) a thin JS shim, called through jsaddle's `jsg`/`#` as `Frontend/Js.hs` does, with one call per frame carrying a buffer, or (b) direct `foreign import javascript` calls. Both can coexist in the same wasm module.
2. The runtime is single-threaded; Haskell green threads still exist. A rAF callback and the Reflex network share one OS thread, so there is no data race, only scheduling order.
3. Drive rAF from JS (shim owns the loop), call into Haskell once per frame; Haskell state flows in through `newTriggerEvent`.
4. Global keydown: use `wrapDomEvent` on `window`/`document` for the event; `preventDefault` must happen synchronously, which jsaddle-wasm supports via its sync callback path.
5. Text: canvas-2D-rendered glyph atlas uploaded with `texImage2D`. SDF is an optional upgrade, not needed for a fixed-size monospace typing display.

## 1. Calling WebGL from wasm: JSFFI vs a JS shim

### The JSFFI route [GHC-UG]
- Syntax: `foreign import javascript unsafe "<snippet>" f :: ...`; arguments are `$1`, `$2`, ...; the snippet is an expression or a body using `return`, and has access to `__exports` (including `memory`) and JS globals.
- `unsafe` imports are synchronous and block the whole runtime; a JS throw crashes the runtime. `safe`/`interruptible`/unannotated imports are async (snippet runs as an async function, result is a thunk that must be forced; only the calling Haskell thread suspends).
- Marshalable types: `Bool` (0/1), `Char` (code point), `Int`/`Word` (32-bit on wasm32), `IntN`/`WordN`, `Ptr`/`FunPtr`/`StablePtr`, `Float`/`Double`. `Int64`/`Word64` become JS `bigint`. `ByteArray#`/`MutableByteArray#` are allowed only as import arguments (JS gets a pointer into the payload). `JSVal` (from `GHC.Wasm.Prim`) is an opaque JS reference; `freeJSVal` releases eagerly, otherwise the GC does after Haskell GC.
- The user guide does not document ByteString, typed arrays or string marshaling beyond `JSString`. Those are done by hand over linear memory, as jsaddle-wasm does: `Ptr` + length passed to `new Uint8Array(__exports.memory.buffer, ptr, len)`, with `TextEncoder.encodeInto` / `TextDecoder.decode` for strings [jsaddle-wasm `Internal.hs` lines 137-153; same snippets visible in [jsffi.js] lines 95-96].
- Consequence for WebGL: a `Float32Array` view over wasm memory (`new Float32Array(__exports.memory.buffer, ptr, n)`) can be passed straight to `gl.bufferData`/`bufferSubData` (MDN says `bufferData` accepts a TypedArray or DataView and copies it into the store [MDN bufferData]). So a vertex buffer can be built in a Haskell-owned `Ptr Float` (e.g. `mallocForeignPtrBytes` / `Foreign.Marshal`) and uploaded with one JSFFI call, no per-element crossing. Caveat: memory can grow, which detaches `memory.buffer`; always construct the view at call time inside the snippet, never cache it **(inference from the WebAssembly.Memory contract, not from the GHC docs)**.
- Callbacks: `"wrapper"` exports a Haskell closure as a JS function (async), `"wrapper sync"` as a synchronous one; `"dynamic"` calls a JS function held as `JSVal` [GHC-UG]. Exports: `foreign export javascript "name" f`, async by default, `"name sync"` for synchronous [GHC-UG]. Link flags `-no-hs-main -optl-mexec-model=reactor -optl-Wl,--export=hs_start` are already in the prototype's `frontend.cabal`.
- Cost per call: the user guide gives no numbers, only that synchronous imports have lower overhead than async ones [GHC-UG]. Each JSFFI import is a plain wasm-to-JS call (the glue in [jsffi.js] is a table of arrow functions), so it is cheap compared to the jsaddle route; no benchmark was found in primary sources. **Open item: measure** (see Open questions).

### The jsaddle route (what reflex-dom actually uses)
- reflex-dom runs `JSM`. `jsaddle-wasm` implements `JSM` by encoding commands (`NewAsyncCallback`, `NewArray`, `StartSyncBlock`, ...) as JSON, sending them across the boundary via `TextDecoder`, interpreting them in JS and sending JSON results back [jsaddle-wasm `Internal.hs` `run`/`runHelper`; interpreter visible in [jsffi.js] lines 101-390]. Its README lists "Performance/benchmarking (not clear that this is actually a bottleneck)", "Use a serialization format more efficient than JSON" and "Patch jsaddle to not go through commands, by using the Wasm JS FFI" as future work, i.e. the authors confirm the current path is JSON-per-batch.
- Consequence: per-call cost through `jsg`/`#` is a JSON round trip per batch. Calling `gl.*` this way many times per frame is the thing to avoid. Passing a large array through jsaddle means JSON-encoding it (no typed-array support in the command protocol; arrays are rebuilt with `NewArray` from values **(inference from the protocol cases)**).
- The same batch runner has a rAF dependency: non-sync batches are processed inside `requestAnimationFrame(processBatch)` unless `initialSyncDepth` is non-zero [jsffi.js] lines 380-386. So jsaddle's own DOM updates are frame-aligned; the patched `initialSyncDepth` declaration in `vendor/jsaddle-wasm-initialSyncDepth.patch` is needed to build.

### The thin shim route (`Frontend/Js.hs`) [TS]
- `Frontend/Js.hs` talks to `window.TypeSolution` (a JS module in `static/editor`) through `jsg ("TypeSolution") # "method" $ args`, and receives callbacks via `function \_ _ args -> ...`. Reflex sees only coarse events: document text, Escape, key presses with timestamps, worker replies. All per-keystroke detail stays in JS.
- Mapping to this project: a `Renderer` JS module that owns the canvas, the GL context, shaders and the rAF loop, exposing a few coarse entry points (`init(canvas)`, `setScene(...)`, `setText(...)`, `pushEvent(...)`) fits this pattern exactly and keeps `gl.*` calls out of wasm entirely.

### Comparison for the renderer decision
| | Direct JSFFI | Shim via jsaddle (`Frontend/Js.hs` style) | Shim via JSFFI |
|---|---|---|---|
| per-call cost | one wasm/JS call | JSON batch round trip | one wasm/JS call |
| buffers | pass `Ptr`+len, view in JS | must JSON-encode | pass `Ptr`+len |
| strings | encodeInto/decode by hand | automatic | by hand |
| code in Haskell | big FFI surface for GL | small | small |
| precedent here | jsaddle-wasm internals | `type-solution` | none yet |

Recommendation: shim owns GL and rAF; use jsaddle `#` for low-frequency calls (init, resize) and a JSFFI `Ptr`/length import only if per-frame data (vertex buffer, game state) must cross.

## 2. Driving requestAnimationFrame, and Reflex

- rAF is one-shot: the callback must re-request itself, and receives a `DOMHighResTimeStamp` (use it for timing; computing progress otherwise "runs faster on high refresh-rate screens"). Callbacks are generally paused in background tabs [MDN requestAnimationFrame]. Use `cancelAnimationFrame` with `null` as the "no request" sentinel (MDN).
- Reflex's way in from outside the network: `newTriggerEvent :: m (Event t a, a -> IO ())`. The returned callback does not fire the event; it does `writeChan events [EventTriggerRef ref :=> TriggerInvocation a cb]` on the calling thread and returns [Reflex `Reflex.TriggerEvent.Base`]. A separate thread (`processAsyncEvents`, started with `forkIO ... forever readChan` in [reflex-dom `Main.hs` line 334-336]) drains the Chan and fires the network. Each call is its own one-element list; the page shows no batching, so one rAF = one trigger = one network propagation (good).
- `performEvent_`/`performEvent` run `Performable m` actions in response to events; `performEventAsync` is built on `newTriggerEvent` + `performEvent_` [Hackage reflex PerformEvent.Class].
- reflex-dom itself uses `DOM.inAnimationFrame'` to apply DOM changes, inside `runDomRenderHookT` [reflex-dom `Immediate.hs` lines 360-374], so DOM mutations are already coalesced per frame.
- Two viable designs:
  1. **JS-owned loop (recommended).** The shim runs `requestAnimationFrame(step)` itself and, per frame, calls a Haskell callback (`function ...` in jsaddle, or a `wrapper` closure) that does `liftIO (fireTick t)`. Reflex gets `eTick :: Event t Double`. Haskell state read by the renderer travels the other way: the renderer calls into the shim with the new scene when Reflex decides, not every frame (or the shim holds the last scene and re-draws it each frame).
  2. **Haskell-owned loop.** Keep a `JSVal` closure that re-requests itself. More code, more crossings, no benefit.
- Single trigger per frame carries latency of one Chan hop plus a Haskell thread switch **(inference)**: the callback only enqueues, the draining thread fires the network later in the same event-loop turn or the next (`scheduleWork = setImmediate(rts_schedulerLoop)` in [jsffi.js] line 94). A scene computed by FRP may therefore reach the renderer one frame late; acceptable for a typing game, but do not rely on same-frame delivery.
- Alternative that avoids even that: the JS shim keeps the latest scene in a JS variable written by Reflex's `performEvent_` and read directly in `step`. No Haskell callback per frame is then needed, except for a time tick if FRP needs one.

## 3. Threading, MVar, forkIO

- [GHC-UG] states the runtime is single-threaded "at the moment"; safe C calls are therefore no better than unsafe ones apart from re-entrancy. While one thread waits on an async import, other Haskell threads run and GC can run. `throwTo` cannot cancel the Promise. A thread cannot force an async-import thunk inside a function exported via C FFI (`WouldBlockException`).
- The guide does not mention `forkIO`, `MVar` or `-threaded` at all. What the evidence shows: the Haskell side uses a green-thread scheduler (`rts_schedulerLoop`, kicked from JS via `setImmediate` [jsffi.js] line 94), and reflex-dom already depends on `forkIO`, `Chan` and (in jsaddle-wasm) `TQueue` working: `processAsyncEvents` uses `forkIO`, and `jsaddle-wasm` blocks a Haskell thread on `atomically (readTQueue ...)` inside an async JS wrapper [Internal.hs lines 73-75; reflex-dom `Main.hs`]. The prototype runs and passes click/input/`dyn_` tests in Chrome (prototype README), so `forkIO` + `Chan` + STM blocking work on this toolchain.
- Note `common/common.cabal` in `type-solution` links with `-threaded -N`, but that applies to the native backend build only; do not copy it to the wasm target.
- MVar hazard analysis **(inference)**: everything (Reflex network, jsaddle callbacks, the rAF callback's Haskell side) runs as green threads on one OS thread. There is no parallel access, so no torn reads. Real hazards:
  - Blocking `takeMVar` in a thread that a synchronous callback (`"wrapper sync"`) or sync export is running on cannot yield to the writer: with `unsafe`/sync entry the runtime is blocked and the guide forbids re-entering blocking operations (`WouldBlockException` is the documented analogue for async thunks). Use `tryReadMVar`/`readIORef`/`atomicModifyIORef'` (or `TVar` with `readTVarIO`) in anything on the rAF/sync path. Never `takeMVar`/`readMVar` there.
  - Ordering, not races: the rAF-driven reader sees whatever the Reflex drain thread wrote last; between `fire` and propagation there is up to one scheduler hop of staleness.
  - An exception in a green thread started by `forkIO` is printed to stderr and the thread dies silently; the Reflex drain thread dying would freeze the UI with no JS error.
- Recommendation: share renderer state through an `IORef` (or `TVar` read with `readTVarIO`), written from `performEvent_`, read from the frame callback. `MVar` offers nothing extra here.

## 4. Global keyboard events in reflex-dom

- Element-scoped: `elementConfig_eventSpec` with `addEventSpecFlags` and `EventFlags { _eventFlags_propagation :: Propagation, _eventFlags_preventDefault :: Bool }` (`preventDefault`/`stopPropagation` values exist) [Hackage reflex-dom-core 0.8.1.4, `Reflex.Dom.Builder.Class`]. The flag is applied in the event handler before the Haskell value is queued: `when (_eventFlags_preventDefault flags) $ DOM.preventDefault` [reflex-dom `Immediate.hs` lines 585-591]. `defaultDomEventHandler` yields `getKeyEvent :: Word` for `Keydown` (key code only) [Immediate.hs lines 2292-2298, 2641].
- That only works for events on an element that has focus. For global capture, use `wrapDomEvent`/`wrapDomEventMaybe` from `Reflex.Dom.Builder.Immediate`:
  `wrapDomEvent :: (TriggerEvent t m, MonadJSM m) => e -> (e -> EventM e event () -> JSM (JSM ())) -> EventM e event a -> m (Event t a)` [Immediate.hs line 2600]. Pass `window`/`document` (from ghcjs-dom) and `(`on` Events.keyDown)`; inside the `EventM` block read `key` (`getKey`) and `repeat` (`getRepeat`) from ghcjs-dom's `KeyboardEvent` and call `preventDefault`. Because it returns a `Maybe`-able handler (`wrapDomEventMaybe`) you can filter inside (e.g. ignore Tab only when the game is active).
- `preventDefault` correctness: the event handler is a JS function that must call `event.preventDefault()` before returning. Under jsaddle-wasm this is only honoured through the synchronous path (`processBatchSync`, `"wrapper sync"`), which the README says is the reason `run` exists in addition to `runWorker`; with the web-worker setup `stopPropagation`/`preventDefault` "definitely no longer works" [jsaddle-wasm README, "Separating execution environments"]. So: run wasm on the main thread; do not move it to a worker.
- Semantics from MDN: `KeyboardEvent.repeat` is `true` for auto-repeated keydowns, `false` for the first; `key` is the value produced (layout/modifier dependent), `code` is the physical position [MDN KeyboardEvent.repeat]. `preventDefault` on `keydown` stops default actions such as Tab focus move and suppresses the follow-up `keypress`. (The MDN `keydown` page itself was not retrievable, so the Tab statement rests on general browser behaviour; verify.)
- Alternative precedent in [TS]: `Frontend/Js.hs` does not use reflex-dom for keys at all; the JS shim registers listeners and calls Haskell with `(key, timeStamp)`. `Frontend.Run` wraps that with `newTriggerEvent` (`fireKey (Pressed t k)`). The same pattern for this project: the shim does `window.addEventListener("keydown", e => { if (e.key === "Tab") e.preventDefault(); cb(e.key, e.repeat, e.timeStamp) })` and the call into Haskell goes through `newTriggerEvent`. This sidesteps the sync-callback question for `preventDefault` entirely, since the decision is taken in JS.
- Use `{passive: false}`/default for keydown (it is cancelable); listen on `window` in the capture phase if focus is in no particular element.

## 5. Text rendering in WebGL

Common approaches:
1. **Canvas 2D glyph atlas.** Render glyphs with `fillText` into a 2D canvas, measure with `measureText` (`width` for advance; `actualBoundingBoxLeft/Right/Ascent/Descent` for the ink box; `fontBoundingBoxAscent/Descent` for a stable line box) [MDN measureText; the metric list is from the HTML canvas spec as relayed there, not on the page itself], then upload the canvas as a texture: `texImage2D` accepts `HTMLCanvasElement`, `OffscreenCanvas`, `ImageBitmap`, `ImageData` as `source` [MDN texImage2D]. Draw text as textured quads. Browser does hinting/antialiasing and font fallback.
2. **Bitmap/pre-baked atlas** (e.g. angelfont). Same rendering, atlas produced offline; needs a tool and files.
3. **SDF/MSDF.** Distance-field texture sampled with a threshold in the shader for scale-independent edges (Valve, "Improved Alpha-Tested Magnification for Vector Textures and Special Effects", SIGGRAPH 2007; I could not retrieve its text, so the technique summary here is general knowledge). Needs offline generation or a JS/GLSL generator; rounded corners are the known weakness; MSDF is the common fix.
4. **Per-string canvas textures.** Re-render a canvas per changed string. Simple, wasteful for per-keystroke updates.

Practicality from wasm: all of 1-4 happen in JS/GL, none needs wasm compute. The glyph atlas is easiest: a ~50-line JS function, rendering ASCII once at startup with a monospace font, no dependencies; Haskell sends strings (or, better, glyph indices into a `Uint8Array`/`Float32Array` of instance data) and the shim looks up UVs. Doing `fillText` from Haskell would go through jsaddle (JSON per call) or a bespoke JSFFI import; doing it in the shim is cheaper.
Notes: wait for the font to be ready before measuring (`document.fonts.ready`; the MDN-relayed spec text says measure only after the web font is ready); pad cells to avoid bleeding with linear filtering; in WebGL1 non-power-of-two textures need `CLAMP_TO_EDGE` and no mipmaps, WebGL2 lifts that (general WebGL knowledge, not on the fetched MDN page).

For this project (fixed-size typed text, mostly monospace, DOM-sized UI): option 1 is the practical default; SDF only if smooth scaling/zoom is required.

## Open questions / to verify in a prototype
1. Per-call cost: no primary source gives numbers. Measure one `unsafe` JSFFI import with a `Ptr` upload vs a `jsg` call in the prototype.
2. Does `foreign import javascript` coexist with jsaddle-wasm in the same module? Both are in `jsffi.js` already (jsaddle-wasm's imports are JSFFI), so yes in principle.
3. Memory growth: confirm views are rebuilt per call.
4. Whether rAF-callback -> `newTriggerEvent` -> propagation lands within the same frame in practice.
5. `MVar` on this wasm RTS is not documented anywhere I could reach; if needed, test `takeMVar` blocking inside `forkIO` with a writer in another green thread.
6. The MDN `keydown` page was unreachable; confirm Tab `preventDefault` in the target browser.
