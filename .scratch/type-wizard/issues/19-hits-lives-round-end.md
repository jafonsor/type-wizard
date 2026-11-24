# 19: Hits, Lives and Round end

**What to build:** A Round can be lost and finished (spec sections 4, 7 and 8): Hit, Grace Period, Lives, the Over phase, banking, the Round Summary, and leaving the page.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 18

**Status:** ready-for-agent

- [ ] An Enemy touching the Player with no Grace Period costs one Life and starts the Grace Period; a parked Enemy hits again each time Grace ends; a Hit never touches the Streak
- [ ] Lives are drawn as white squares at the HUD top-left, lost ones dim
- [ ] At 0 Lives spawning, movement and input stop, Focus drops, Enemies are discarded with no Points, and the Round Summary shows the seven rows in order
- [ ] RoundEnded banks the Round Points into Total Points and saves; Play again (button or Enter) starts a fresh Round; Back to start returns to the Start page
- [ ] The Menu control and Escape leave to Start with no confirm, abandoning the Round, banking nothing and showing no Summary
- [ ] Window blur freezes the Round with a Paused overlay and focus plus click or key resumes with no time jump
- [ ] Tests cover Grace Period re-Hit, Round end and the Round Result values
