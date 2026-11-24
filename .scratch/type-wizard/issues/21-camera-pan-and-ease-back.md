# 21: Camera pan and ease-back

**What to build:** The view follows the Focused Enemy when it is off-screen and returns afterwards, as in spec section 9.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 17

**Status:** ready-for-agent

- [ ] The target is the Focused Enemy only when it lies outside the default view, shifted by the smallest amount that brings it inside the inset
- [ ] The Player stays at least the margin inside every screen edge
- [ ] Exponential smoothing with the configured time constant, for both pan and return; fixed while the Word is typed; returns on Kill or Tab
- [ ] The dot grid scrolls with the Camera and spawns stay relative to the Player
- [ ] Builder tests assert the Camera centre at chosen times
