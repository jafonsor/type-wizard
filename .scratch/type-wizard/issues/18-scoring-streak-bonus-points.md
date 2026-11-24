# 18: Scoring: Streak, Bonus, Points

**What to build:** Kills score. Streak, Bonus and Points follow spec section 4, the Streak persists between Rounds and visits, and the HUD and the Player's side show the numbers.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 14, 17

**Status:** ready-for-agent

- [ ] A Kill increments the Streak first, then awards 1 plus floor(Streak / group size); the 10th consecutive Kill pays 2 and there is no cap
- [ ] A Typo clears Streak, Bonus and the meter immediately
- [ ] The Streak is read from saved progress at Start and written on every Kill and Typo
- [ ] The HUD shows Round Points and Total Points and the Streak; the Streak Meter and the '+N' label appear next to the Player as static nodes, hidden at Bonus 0
- [ ] Longest Streak counts from 0 at Round start regardless of the carried-in Streak
- [ ] Tests cover the 10th-Kill payout, Typo clearing, and the carried-in Streak case
