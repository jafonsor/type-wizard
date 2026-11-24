# Obelisk v2 multi-page routing in a static wasm deploy

Sources (all local, read-only):

- `TS` = `~/devs/type-solution` (the reference app).
- `OB` = `~/devs/type-solution/deps/obelisk` (submodule, fork `jafonsor/obelisk`, commit `12f0a434`, "Obelisk v2").
- `RD` = `~/devs/type-solution/deps/reflex-dom` (commit `7193774e`).
- `reflex` `Reflex.Dynamic.factorDyn`, read from the upstream repo (`raw.githubusercontent.com/reflex-frp/reflex/develop/src/Reflex/Dynamic.hs`); it is not vendored locally.

Nothing here was run. Claims marked "inference" follow from the source but were not executed.

## Short answers

1. Add constructors to `FrontendRoute` and one `case` arm each in the encoder. Switch pages with `subRoute_` over the routed `R FrontendRoute`; navigate with `routeLink` / `setRoute`.
2. History API routes work on GitHub Pages only for the root page as `type-solution` is set up today. Under a sub-path, the router drops the base path on every navigation and a refresh on a non-root page is a 404. Three workable fixes are listed in section 2. Hash routing is not a switch Obelisk exposes for web builds.
3. One Reflex network for the whole session. `subRoute` rebuilds only the page subtree, and only when the route constructor changes. State that must survive page switches must be created above the `subRoute`.
4. `prerender`/`prerender_` runs the `server` widget at export time (native backend, no JS) and the `client` widget only in the browser, so WebGL code goes in the `client` argument.

## 1. Declaring routes and switching pages

Current declaration, `TS/common/src/Common/Route.hs`:

```haskell
data FrontendRoute :: Type -> Type where
  FrontendRoute_Main :: FrontendRoute ()
...
fullRouteEncoder = mkFullRouteEncoder
  (FullRoute_Frontend (ObeliskRoute_App FrontendRoute_Main) :/ ())   -- "404" fallback
  (\case BackendRoute_Api -> PathSegment "api" $ unitEncoder mempty)
  (\case FrontendRoute_Main -> PathEnd $ unitEncoder mempty)
```

Three pages:

```haskell
data FrontendRoute :: Type -> Type where
  FrontendRoute_Start    :: FrontendRoute ()
  FrontendRoute_Game     :: FrontendRoute ()
  FrontendRoute_Settings :: FrontendRoute ()
...
  (\case
     FrontendRoute_Start    -> PathEnd $ unitEncoder mempty
     FrontendRoute_Game     -> PathSegment "game"     $ unitEncoder mempty
     FrontendRoute_Settings -> PathSegment "settings" $ unitEncoder mempty)
```

`deriveRouteComponent` (already in the file) derives the instances for the new constructors. `checkedFullRouteEncoder` stays and still verifies the encoder round-trips at startup. The `OB/guides/routes/introduction.md` section "Adding another page" shows the same pattern (a `["privacy"]` path).

Notes from `OB/lib/route/src/Obelisk/Route.hs`:

- `mkFullRouteEncoder missing backendSegment frontendSegment = handleEncoder (const missing) $ ...` (line 1085). The first argument is not only a 404 page: any path that fails to decode (including an unknown first segment) decodes to `missing`. That is the "catch-all" in `type-solution`. Pick `FrontendRoute_Start` as the fallback for the three-page app.
- `handleEncoder` (line 998) only changes decoding. Encoding of a route is unaffected.

Switching pages in the frontend. `frontendBody :: ObeliskWidget t (R FrontendRoute) m => RoutedT t (R FrontendRoute) m ()` already runs inside `RoutedT`, so:

```haskell
frontendBody = subRoute_ $ \case
  FrontendRoute_Start    -> startPage
  FrontendRoute_Game     -> gamePage
  FrontendRoute_Settings -> settingsPage
```

- `subRoute_ :: (MonadFix m, MonadHold t m, GEq r, Adjustable t m) => (forall a. r a -> RoutedT t a m ()) -> RoutedT t (R r) m ()` (`OB/lib/route/src/Obelisk/Route/Frontend.hs:196`). `subRoute` (line 200) is the same but returns `Dynamic t b` of the page's result.
- Links: `routeLink :: (DomBuilder t m, RouteToUrl route m, SetRoute t route m, Prerender t m) => route -> m a -> m a` (about line 700). `routeLink (FrontendRoute_Game :/ ()) (text "Play")` renders an `<a href=...>` with `preventDefault` on click and fires `setRoute` (`routeLinkDynAttrImpl`, same file, near line 660). `routeLinkAttr` adds attributes. Programmatic navigation: `setRoute :: Event t r -> m ()` from the `SetRoute` class (also available as `Routed`/`askRoute` to read the current route).
- Because `routeLink` has a `Prerender` constraint and the pages live in `RoutedT`, the page widgets need `ObeliskWidget t (R FrontendRoute) m` (or a subset) in their signatures. Sub-widgets under `subRoute_` get `RoutedT t () m` (the `()` payload), so pass app state in as arguments rather than reading the route.

## 2. Static deploy under a sub-path

### What `type-solution` does

- Export (`TS/tools/export-site.sh RESULT OUT BASE`): runs the built backend once, saves `GET /` as `index.html`, then rewrites two things with `sed`: `<base data-ssr="" href="/" />` becomes `<base ... href="$base" />` (BASE is `/type-solution/`, from `.github/workflows/deploy.yml`) and `"/ghcjs/` becomes `"ghcjs/`. It fails the build if Obelisk stops emitting those two strings. Assets are copied out of the hashed Obelisk asset folders into plain files. A `.nojekyll` file is added.
- Obelisk side: `baseTag` hard-codes `elAttr "base" ("href" =: "/")` with a "TODO: Figure out the base URL from the routes" (`OB/lib/frontend/src/Obelisk/Frontend.hs:94`). `OB/docs/migrating-to-v2.md` states `<base href="/">` is unconditional in v2.
- Route decoding in the browser reads the real URL path: `route = fmap (... tryDecode theEncoder . (adaptedUriPath useHash &&& uriQuery) . _historyItem_uri) historyState` (`Route/Frontend.hs`, `runRouteViewT`). With `useHash = False` that is `uriPath` as is, so on Pages the decoder sees `/type-solution/`, whose first segment `type-solution` matches nothing and falls to the `missing` route. `TS/common/src/Common/Route.hs` says this in its comment ("Any path no route matches is the game page. GitHub Pages serves the game under `/type-solution/`, which the frontend's router must accept").

So today the single page works only because every path is the fallback route.

### What breaks with three pages (inference from the source above)

1. **Navigation drops the sub-path.** `routeLink` sets `href` to `encode theEncoder route`, which is `"/game"` (the `pageNameEncoder` prefixes `"/"`, `Route.hs:991`). The history update does `setAdaptedUriPath useHash newPath uri`, i.e. `uriPath = "/game"`. The address bar becomes `https://host/game`, not `https://host/type-solution/game`. The `<base>` tag does not help because the path starts with `/`.
2. **Refresh or deep link to a non-root page is a 404.** The export produces one `index.html`. GitHub Pages serves a 404 for `/type-solution/game` unless a file exists there.
3. **Decoding of `/type-solution/game`** would see segments `["type-solution","game"]`, no match, so it falls back to Start.
4. **Hydration mismatch** if the initial route is not the one the exported HTML was rendered for. The export always renders `/`. `RD/.../Immediate.hs` logs "hydration failed: the DOM was not as expected at switchover time" when the DOM differs.

### Options

- **A. Hash routes.** `runFrontendWithConfigsAndCurrentRoute` and `FrontendMode(..)` are exported (`OB/lib/frontend/src/Obelisk/Frontend.hs` export list) and `_frontendMode_adjustRoute = True` makes `runRouteViewT` use the URL fragment (`adaptedUriPath`/`setAdaptedUriPath`, `pathToHash`). But `runFrontend` hard-codes `platformFrontendMode` with `adjustRoute = False` for wasm/ghcjs, so using it means calling `runFrontendWithConfigsAndCurrentRoute` yourself from `Main.hs` (and replicating `runFrontend`'s config lookup, `removeHTMLConfigs`, and the `setInitialRoute` step). With hash routing the path is always `/type-solution/`, so refresh works and the sub-path problem disappears. Cost: URLs look like `/type-solution/#/game`; the exported HTML is fine. Note `setInitialRoute` also does `replaceState` to `"/"`-in-fragment, so check the interplay with the exported `<base>`. Not tried.
- **B. Put the base path in the route encoder.** Make every frontend route sit under a fixed first segment, e.g. wrap the frontend routes in `PathSegment "type-solution"` (or make it a build-time constant). Then decode, `href` and `pushState` all agree with the real URL. Still need a 404 fix (below) for deep links and refresh. Locally (`ob run`/backend at `/`) the prefix would also be in the URL unless it is empty in dev.
- **C. Keep one URL, navigate without the URL.** Hold the current page in a `Dynamic` in app state and ignore the route (keep only `FrontendRoute_Main`). No history entries (browser Back leaves the site), nothing to break on Pages. Simplest, loses deep links, which the game probably does not need.

For A and B, deep links on Pages need either a copy of `index.html` for each route (`game/index.html`, `settings/index.html`; the exporter would write them) or a `404.html` that is a copy of `index.html` (Pages serves it for unknown paths, with status 404; the page still boots and the router reads the URL). For B, the per-route copies must be hydration-compatible, see the next point.

### Hydration and the static shell (inference)

`export-site.sh` renders `/` only. To avoid the hydration warning on deep links, keep the exported DOM identical for every route: put the whole `subRoute_` inside `prerender_ placeholder (...)` (as `Frontend.hs` already does for the one page) so the static HTML is only the placeholder. Everything route-dependent is then built after switchover. Note `prerender_` inside `RoutedT`: `RouteToUrlT` has a `Prerender` instance that passes the route through (`Route/Frontend.hs`, "instance (Prerender t m, Monad m) => Prerender t (RouteToUrlT r m)"), and so does `RoutedT`.

## 3. Does the network survive page switches?

- There is one Reflex network, started once in `runFrontendWithConfigsAndCurrentRoute` (`OB/.../Frontend.hs`) under `runRouteViewT`. `routeLink` and `setRoute` call `history.pushState` via `manageHistory'`; the page is never reloaded. The route is a `Dynamic t r` read from the history state.
- `subRoute_` is `factorRouted (strictDynWidget_ ...)` (`Route/Frontend.hs:196,266,286`). `factorRouted` uses `factorDyn`. Per the `reflex` source: "The outer `Dynamic` updates only when the key of the `DSum` changes, while the update of the inner `Dynamic` represents updates within the current key." (the `update` event returns `Nothing` when `newKey geq oldKey`.) `strictDynWidget_` does `runWithReplace (f r0) (f <$> updated r)`.
- Consequence: moving Start to Game runs `runWithReplace`, which tears down the Start page's widget subtree (its DOM, Dynamics created inside, event subscriptions) and builds the Game page. Re-selecting the same constructor does not rebuild. Anything created inside a page widget is gone when you leave that page (inference from `runWithReplace` semantics; I did not run it).
- Where state lives. Create it in `frontendBody` (or a wrapper) above `subRoute_`, and pass it down as arguments or via a `Reader`-style environment:

```haskell
frontendBody = do
  settings <- loadSettings            -- holdDyn / foldDyn built once, persisted via a JS seam
  totals   <- loadTotals
  subRoute_ $ \case
    FrontendRoute_Start    -> startPage settings totals
    FrontendRoute_Game     -> gamePage settings totals
    FrontendRoute_Settings -> settingsPage settings
```

  The Dynamics and any `foldDyn` accumulators there live for the whole session. If the pages must write back (settings page changes a setting), return an `Event` from the page and fold it into the Dynamic above, using `mdo`/`rec`, or use `subRoute` and merge the returned values. `type-solution` already does this shape in `Frontend/Run.hs`: `dHistory <- foldDyn addRecord (history stored) eRecord` is built once and read by the status line.
- Persistence across reloads is separate: a reload rebuilds everything. `type-solution` keeps saved data in `localStorage` through its JS shim (`Frontend.Js.loadRuns`, `jsg "TypeSolution" # "loadRuns"`). Settings and persisted totals need the same seam: load once at startup, write on change.
- JS-side objects are not owned by the Reflex network. A WebGL context or CodeMirror instance tied to a DOM node dies with that node when the page is replaced, so create and dispose it with the page widget (for example dispose in a `performEvent_` on the page's teardown; there is no built-in "on destroy" hook that I found, so the usual route is to keep the canvas element above `subRoute_` and show/hide it with CSS, or recreate on entry). This part is a design choice for the ticket that follows, not verified.

## 4. `prerender` / `prerender_` and WebGL

- Signature (`RD/reflex-dom-core/src/Reflex/Dom/Prerender.hs:83`): `prerender :: m a -> Client m a -> m (Dynamic t a)`. `prerender_ server client = void $ prerender server client`. Docs in the source: "Render the first widget on the server, and the second on the client. The hydration builder will run *both* widgets, updating the result dynamic at switchover time."
- Two build contexts exist:
  - **Export time.** `export-site.sh` runs the native `backend` binary, which calls `renderFrontendHtml` (`OB/.../Frontend.hs:~250`) on `StaticDomBuilderT`. Only the `server` widget runs. The `client` argument is not run (its type is `Client m`, and the static instance, `UnrunnableT`, makes any effect `unrunnable`). So a JS FFI call (`MonadJSM`, `liftJSM`) placed in the client widget is never executed during export.
  - **Browser.** Instance for `HydrationDomBuilderT GhcjsDomSpace` is `prerender _ client = pure <$> client`: the client widget runs directly. For the hydrating builder, the server widget is built in a detached fragment, the client widget is built after switchover and replaces the server DOM (`HydrationMode_Hydrating -> addHydrationStep ... insertBefore df =<< deleteToPrerenderEnd doc`). If hydration is already past (`HydrationMode_Immediate`), the client widget is built and appended right away.
- The client monad has the constraints `MonadJSM`, `MonadJSM (Performable m)`, `TriggerEvent`, `PostBuild`, `DomBuilderSpace ~ GhcjsDomSpace` etc. (`PrerenderClientConstraint`). That is why `runWidget` in `TS/frontend/src/Frontend/Run.hs` is written against those classes, not `ObeliskWidget`, and called as `prerender_ (el "p" $ text "Loading...") $ runWidget (static @"js/runner.js")`. WebGL setup (getting the `canvas`, `getContext("webgl2")`, `requestAnimationFrame`) must live inside that client argument.
- The `Dynamic` result of `prerender` has the server value until switchover and the client value after. Do not use it for anything the page needs before the browser exists.
- With routing: put `prerender_` around the `subRoute_` (see section 2) or inside the Game page only. Inside the Game page it is needed for the canvas/WebGL; the Start and Settings pages that are plain DOM can be built in both worlds.
- wasm note: in this stack the frontend is wasm (`frontend/wasm`, `foreign export javascript "hs_start"`), but Obelisk still names things "ghcjs" (`frontend.jsexe`, `/ghcjs/`; `OB/docs/migrating-to-v2.md`: "'GHCJS' names now govern WASM too"). `Obelisk.Frontend` picks hydration mode by `#if defined(ghcjs_HOST_OS) || defined(wasm32_HOST_ARCH)`, so the wasm build hydrates the exported HTML.

## Recommendation for the ticket

- Declare `Start`, `Game`, `Settings` routes with `subRoute_`; build settings and totals Dynamics above it.
- Pick one of A/B/C in section 2 before writing pages; `type-solution`'s current setup (catch-all route, base rewritten by `sed`) is only correct for a single page. If deep links are not needed, C is the least work and has no Pages failure mode. If URLs matter, B plus per-route `index.html` copies in the exporter (and an unchanged-DOM shell) keeps clean paths.
- Keep the shell around `subRoute_` route-independent to avoid hydration warnings.
- Put WebGL initialisation in the `client` argument of `prerender_`, and decide the canvas lifetime (inside the Game page, recreated per visit, or hoisted above `subRoute_`).

## Not verified

- No build or browser run was done; deep-link and `pushState` behaviour under `/type-solution/` is derived from reading `runRouteViewT`, `setAdaptedUriPath`, `routeLink` and `export-site.sh`.
- Whether a `404.html` copy of `index.html` hydrates cleanly on Pages was not tested.
- Obelisk's own docs say nothing about GitHub Pages or sub-paths; the only mention is the TODO on `baseTag`.
