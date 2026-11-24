Type: research
Status: resolved
Blocked by:
Findings: research/02-obelisk-multipage-routing.md

# Research: Obelisk v2 multi-page routing in a static wasm deploy

## Question

`~/devs/type-solution` has a single route (`FrontendRoute_Main`) and a catch-all. Find out how to get three pages (start, game, settings) in an Obelisk v2 frontend:

1. How are routes declared in `common/src/Common/Route.hs` (`obelisk-route`), and how does the frontend switch pages with `subRoute`/`routeLink`?
2. Does this work in a static deploy (for example GitHub Pages under a sub-path) with history API or only with hash routes? Note the base-path handling in `type-solution`.
3. Does the same Reflex network survive page switches, or does it rebuild? Where should app-wide state (settings Dynamics, persisted totals) live so that both pages see it?
4. How does `prerender`/`prerender_` behave here, given that WebGL needs a browser-only context?

Primary sources: Obelisk v2 docs and source, `obelisk-route` docs, and `~/devs/type-solution`. Write the findings to `.scratch/type-wizard/research/02-obelisk-multipage-routing.md`.
