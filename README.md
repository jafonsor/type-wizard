# Type Wizard

A top-down typing game in Haskell compiled to wasm (reflex-dom, Obelisk v2). The plan is `.scratch/type-wizard/spec.md`; terms are in `GLOSSARY.md`.

## Layout

- `common`: shared code (`Common.Route`) and the pure game modules (`Game.Settings`, `Game.Save`), with a test-suite.
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

The pure tests (`common/test` and `renderer/test`, HUnit) run as flake checks:

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

1. A dark window with a white square in the middle, a dot grid, `Type Wizard renderer demo` at the top and `Esc: menu` at the bottom-left; the Menu button is clickable.
2. Resize the window: the square stays centred and 1.2 world units wide (a 20-unit world height is the window height), the dots keep their 2-unit spacing, nothing stretches or stays blurry.
3. Change the device pixel ratio (drag the window between screens, or browser zoom, or DevTools device toolbar DPR): the picture stays sharp and the same size in CSS pixels. `canvas.width` is CSS width times `devicePixelRatio`.
4. Click Menu: `TypeWizardRenderer.stats.stopped` becomes 1 and `frames` stops growing. Play again: `started` is 2 and `frames` grows.
5. WebGL unavailable (start Chrome with `--disable-gpu`, or run `HTMLCanvasElement.prototype.getContext = () => null` before load): the Game page shows `WebGL is not available in this browser...` and no blank canvas; Menu still works.
6. DevTools console: no errors while it runs.

Results of the run for ticket 15 are in `.scratch/type-wizard/issues/15-renderer-and-empty-game-page.md`. The scripted version used a Chrome DevTools Protocol client (resize with `Emulation.setDeviceMetricsOverride`, pixels from `Page.captureScreenshot`).

### Measuring the JS boundary (dev only)

Open the Game page with `?bench` in the URL (for example `http://localhost:8765/type-wizard/?bench`; the page is a single page, so the query is only read, not routed). After a few seconds read `window.TypeWizardBench` (100,000 JS FFI calls from Haskell, 100,000 JS-to-Haskell `wrapper sync` calls, 1,000 jsaddle calls, in milliseconds) and, from `TypeWizardRenderer.stats`, `callbackMs / frames` (the whole per-frame Haskell callback: pull, flatten, pack and the draw call) and `drawMs / frames` (the JS side of the draw call). Without `?bench` no timing is done. The code is `Frontend.Bench` and the `bench` flag in `renderer.js`.

## Settings and saved progress

`Game.Settings` is the `Settings` record plus a field table (default, min, max, group); the Settings page, the JSON codec, the clamp and the group resets all run from that table. The stored form is flat JSON under `localStorage` key `typewizard.settings` with `version: 1`. Saved progress (`Game.Save`: Total Points, Streak, Bonus) is `typewizard.save`, separate. `Frontend.Page` holds `Dynamic Settings` and `Dynamic Save` above the page switch, loads them once in the browser and writes them back on every change. `static/src/js/storage.js` wraps every `localStorage` access in try/catch; with storage blocked the game uses defaults and in-memory state. To add a setting: add the record field, its default, and one line in `fields`; no other code changes.

## Pages

`Frontend.Page` holds a `Dynamic Page` (`Start | Game | Settings`) above the page switch. There is no URL routing: `FrontendRoute` has one constructor, there is one exported `index.html`, and the address bar never changes. Each page is a `<section data-page="start|game|settings">` with an `<h1>` title. The Game page's section is pinned to the top-left over a full-window canvas (`Frontend.Game`).

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
