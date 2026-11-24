Type: research
Status: researched
Findings: research/01-wasm-webgl-interop.md
Blocked by:

# Research: WebGL, rAF loop and MVar from GHC wasm + reflex-dom

## Question

Facts needed before the renderer and FRP ticket can be decided, for GHC wasm (flavour 9.12, as in `~/devs/type-solution`) with reflex-dom:

1. How does Haskell call WebGL from wasm? Compare the JSFFI (`foreign import javascript`) route against a thin JS shim like `Frontend/Js.hs` in `type-solution`. Note the cost per call and what can cross the boundary (buffers, typed arrays, strings).
2. How should a `requestAnimationFrame` loop be driven from Haskell, and how does it interact with Reflex (triggering events from outside the network, `newTriggerEvent`, `performEvent`)?
3. Is the wasm runtime single-threaded? Do `MVar`, `forkIO` and blocking behave as expected, and is there any hazard in reading an `MVar` from the rAF callback while the Reflex network writes it?
4. How are global keyboard events (keydown, with `key` and `repeat`) captured in reflex-dom, including preventing default for tab?
5. What does text rendering in WebGL commonly use (glyph atlas, canvas 2D texture, SDF), and which of them is practical from wasm?

Use primary sources only: GHC user guide, ghc-wasm-meta docs, reflex-dom docs, MDN, and the code in `~/devs/type-solution` and `~/devs/type-solution/prototype-reflex-wasm`. Write the findings to `.scratch/type-wizard/research/01-wasm-webgl-interop.md`.
