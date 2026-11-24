# 13: Scaffold, build and deploy

**What to build:** An Obelisk v2 wasm app laid out like `type-solution`, with a `Dynamic Page` switching between empty Start, Game and Settings pages (spec section 8, no URL routing). The words list is embedded following the three build rules in spec section 10, and the Start page shows the loaded word count. The app deploys as a static site to a GitHub Pages sub-path.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** None (can start immediately)

**Status:** done

- [x] The app builds with the wasm toolchain and the three pages switch through buttons, with no URL routing
- [x] The Start page shows the word count read from the embedded list in the running browser page
- [x] The list passes the build rules: tracked file outside the gitignored data directory, declared in the cabal file, embedded through the project-relative path
- [x] A static deploy works from a sub-path and the page loads
- [x] Run and deploy steps are written down for later tickets

## Answer

Done. Mechanisms:

1. Build: `nix build .#haskell-nix --cores 4 -L` (wasm frontend plus native frontend and backend) succeeds with no compiler warnings in the module logs. Page switch: `Frontend.Page.pageSwitch`, a `Dynamic Page` above a `dyn`; verified in headless Chrome by clicking Play, Menu, Settings, Back; the URL never changed.
2. Word count: headless Chrome (Chrome DevTools Protocol script) loaded the exported site and read `Words: 400` from the DOM, before and after wasm-driven page switches (so it was rendered by the running wasm, not only the exported HTML).
3. Embed: `frontend/words/words.txt` is git-tracked, outside `frontend/data/`; `extra-source-files: words/words.txt`; `makeRelativeToProject "words/words.txt" >>= embedFile` in `Frontend.Words`; `file-embed` and `bytestring` in the library's main `build-depends`.
4. Sub-path: `tools/export-site.sh result site /type-wizard/`, copied to `<root>/type-wizard/` and served by `python3 -m http.server` from `<root>`; the page loaded and ran at `http://localhost:8765/type-wizard/`. The workflow passes the repository name as the base.
5. Steps: `README.md`.

Decisions not in the spec:

- **Base path scheme.** `tools/export-site.sh` (copied from `type-solution`, PureScript parts removed) rewrites `<base href="/">` to `/<repo>/` and `"/ghcjs/` to `"ghcjs/`. `FrontendRoute`'s fallback route (`FrontendRoute_Main`) decodes `/<repo>/` with no router change. The base is `/${GITHUB_REPOSITORY#*/}/` in `.github/workflows/deploy.yml` (triggers: push to `main`, manual). The workflow was not run; only its export script was exercised locally.
- **Placeholder words.** `frontend/words/words.txt` has 400 made-up `[a-z]{3,8}` strings; `frontend/words/SOURCES.md` marks it as a placeholder.
- **Module names.** `Frontend.Words` (embed, `parseWords`) and `Frontend.Page`. Spec section 3's `Game.Words` parsing and `Game.*` modules are left for later tickets.
- **Static files.** `obelisk.static.path = ./static/src` (no build step); only `css/app.css`.
- `deps/nix-haskell`, `deps/nixpkgs`, `deps/reflex-dom` are symlinks into `deps/obelisk`, as in `type-solution`; the submodule needs `--recursive` (nested pins).
- No `renderer` package yet (ticket 15). No test suite: no pure code worth testing.
