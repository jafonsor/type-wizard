# 23: Polish and tuning

**What to build:** The game is checked in a real browser and tuned (spec section 15).

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 20, 21, 22

**Status:** ready-for-agent

- [ ] The manual browser checklist passes: resize, device pixel ratio change, canvas detach stops the loop, WebGL-unavailable message
- [ ] Key presses with Ctrl, Cmd or Alt are ignored and not counted; other browser shortcuts such as quick find are checked and the result recorded
- [ ] Numeric defaults flagged as placeholders (spawn interval, speed) are tuned by play and updated in the settings and spec
- [ ] A contrast pass confirms every colour on the dark background
- [ ] The embedded word list is read back in the running page
