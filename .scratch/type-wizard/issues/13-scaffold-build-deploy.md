# 13: Scaffold, build and deploy

**What to build:** An Obelisk v2 wasm app laid out like `type-solution`, with a `Dynamic Page` switching between empty Start, Game and Settings pages (spec section 8, no URL routing). The words list is embedded following the three build rules in spec section 10, and the Start page shows the loaded word count. The app deploys as a static site to a GitHub Pages sub-path.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The app builds with the wasm toolchain and the three pages switch through buttons, with no URL routing
- [ ] The Start page shows the word count read from the embedded list in the running browser page
- [ ] The list passes the build rules: tracked file outside the gitignored data directory, declared in the cabal file, embedded through the project-relative path
- [ ] A static deploy works from a sub-path and the page loads
- [ ] Run and deploy steps are written down for later tickets
