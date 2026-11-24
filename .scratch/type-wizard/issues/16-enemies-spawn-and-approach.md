# 16: Enemies spawn and approach

**What to build:** The first playable frame: Enemies of the right Tier spawn outside the view, carrying Words, and move to the Player and park there (spec sections 4, 6, 7 and 10). It includes the pure `step`, the `IORef` handoff cell, the JS-owned tick and the first `buildScene`.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 14, 15

**Status:** ready-for-agent

- [ ] `step` handles Start with a seed, Tick with clamped dt, spawning along the per-Tier linear ramp, Tier advance after the set count of spawns, and endless last Tier
- [ ] Words come from one shuffled bag per Tier with no duplicates on screen and best-effort distinct first letters within the lookahead
- [ ] Enemies move at the configured speed and stop at contact distance; the Player does not move
- [ ] `buildScene` draws Enemies in their Tier colours with Words below them, using the visual spec's sizes
- [ ] The handoff is an IORef peeked by the render pull, never an MVar; the pull returns a fresh Scene every frame once a state exists
- [ ] Entering the Game page starts a Round with a clock-derived seed and a snapshot of the settings
- [ ] Headless tests with a fixed seed and a tiny injected word list cover the ramp, Tier advance, no duplicate Words and determinism
