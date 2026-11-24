# 17: Typing: Focus, Typo, Lock, Tab, Kill

**What to build:** Typing kills Enemies (spec section 4 table). The JS key shim feeds Keystrokes in; the state machine handles Focus, Typo, Lock, Tab and Kill; Words show typed and Lock-expected letters.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 16

**Status:** ready-for-agent

- [ ] Key capture ignores auto-repeat and non-letter keys, prevents the default for Tab in JS, and only listens while the Game page canvas is attached
- [ ] Every transition in the spec's typing table behaves as written, including Closest Enemy wins and tie to the earlier spawn
- [ ] Typed letters, the Lock-expected letter and default letters use the visual spec's colours
- [ ] Tab resets the Word with no cost to Streak or Accuracy; Tab with no Focus does nothing
- [ ] A Kill removes the Enemy; correct and wrong Keystrokes are counted for Accuracy and WPM
- [ ] Tests cover each transition, wrong keys while Locked, and the Accuracy definition
