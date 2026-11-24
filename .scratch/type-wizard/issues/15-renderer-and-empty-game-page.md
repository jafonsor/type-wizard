# 15: Renderer and an empty game page

**What to build:** A separate `renderer` package with the public interface in spec section 5, and a Game page that draws a canvas showing a Player square, a dot grid and overlay text, so the renderer is proven before any game logic exists.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 13

**Status:** ready-for-agent

- [ ] The renderer package exposes only the public types and initRenderer, getViewport and startRenderLoop
- [ ] Pure tests cover transform composition, node order in flatten, the camera matrix and the packed buffer layout including text to glyph instances
- [ ] The Game page shows the Player, the dot grid and overlay text, scales with the window and device pixel ratio, and redraws on resize
- [ ] One JS call is made per frame; the loop stops by itself when the canvas leaves the document and restarts on a fresh visit
- [ ] If WebGL is unavailable the page shows an error instead of a blank canvas
- [ ] The JS boundary cost per call is measured and recorded in the ticket
- [ ] A short manual browser checklist for the JS executor is written
