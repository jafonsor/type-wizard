# Type Wizard

A top-down typing game in Haskell compiled to wasm (reflex-dom, Obelisk v2). The plan is `.scratch/type-wizard/spec.md`; terms are in `GLOSSARY.md`.

## Layout

- `common`: shared code (`Common.Route`).
- `frontend`: the browser app (`Frontend`, `Frontend.Page`, `Frontend.Words`). `frontend/wasm` and `frontend/js` are Obelisk wrapper packages that cross-compile it.
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

## Pages

`Frontend.Page` holds a `Dynamic Page` (`Start | Game | Settings`) above the page switch. There is no URL routing: `FrontendRoute` has one constructor, there is one exported `index.html`, and the address bar never changes. Each page is a `<section data-page="start|game|settings">` with an `<h1>` title.

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
