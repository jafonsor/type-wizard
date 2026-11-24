# 20: Shot and Plus Sign animations

**What to build:** Kills look right: a Shot flies to the dying Enemy and Plus Signs fly to the Player, as in spec sections 6 and 9.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 18

**Status:** ready-for-agent

- [ ] A Shot is created per Kill, pointing along travel, with the 11-stop Streak colour ramp that follows the group size
- [ ] The Enemy is removed and Plus Signs spawn when the Shot arrives
- [ ] One Plus Sign per Point, with the spread, hold, stagger, quadratic fly, shrink and fade from the visual spec and a draw cap that does not change Points
- [ ] Animations are start-time records in the game state and evaluated by the builder at the frame time; the step only creates and expires them
- [ ] In-flight animations finish after the Round ends
- [ ] Builder tests assert evaluated positions, scales and colours at chosen times
