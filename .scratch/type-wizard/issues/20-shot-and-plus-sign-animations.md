# 20: Shot and Plus Sign animations

**What to build:** Kills look right: a Shot flies to the dying Enemy and Plus Signs fly to the Player, as in spec sections 6 and 9.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 18

**Status:** done

- [x] A Shot is created per Kill, pointing along travel, with the 11-stop Streak colour ramp that follows the group size
- [x] The Enemy is removed and Plus Signs spawn when the Shot arrives
- [x] One Plus Sign per Point, with the spread, hold, stagger, quadratic fly, shrink and fade from the visual spec and a draw cap that does not change Points
- [x] Animations are start-time records in the game state and evaluated by the builder at the frame time; the step only creates and expires them
- [x] In-flight animations finish after the Round ends
- [x] Builder tests assert evaluated positions, scales and colours at chosen times

## Answer

Proof, by mechanism (pure tests are `common/test/AnimationTests.hs`, 285 cases total in `common-test`, 0 failures; browser checks are `check20.mjs` in headless Chrome against the built page, 1200x800, run three times on the final build, 47 checks each, all passing):

1. **A Shot per Kill, along travel, 11-stop ramp.** Tests: one record per Kill with start, Player-to-Enemy endpoints, durations and Streak; the triangle is 0.5 long, at the Player at the start, rotated 0 for travel along +x and pi/2 for +y; `shotColour` at 0/9 (start colour), 10, 100 and 250 (end colour). Browser: the Shot's pixels are in the ramp colour for the Streak, lie on the Player-Enemy line (within 12 px), at the eased fraction expected for the screenshot's time window, and the apex is narrower than the base (front quarter vs back quarter width).
2. **Enemy removed and Plus Signs spawn on arrival.** Tests: no signs before `kaStart + shotDuration`, signs appear at arrival, the Shot and the dying square are gone at arrival. Browser: the Tier-coloured square without Word is on screen during the flight and gone after; the hook shows 0 signs while a Shot flies and Points signs after.
3. **One sign per Point, spread, hold, stagger, quadratic fly, shrink, fade, cap.** Tests: count = Points (1 and 2); offsets within 0.6 and deterministic for the seed (a zero radius puts them on the Enemy); delays in 0 to 0.15; positions unchanged during the hold; halfway through the flight a sign has covered 1/4 of the way and 20 percent in covers 4 percent (quadratic ease-in); scale 0.5 until the last 0.15 s, then 0.325 and alpha 0.5 midway, near 0.15 and 0 at the end; gone at its end; Streak 400 (Bonus 40) pays 41 Points and draws 30 signs, a cap of 5 draws 5 and 200 draws 41 with Points unchanged. Browser (Streak carried 7: Points 1, 1, 2): hook counts equal Points, the sign mass is within the spread of the Enemy position at hold, closer to the Player in flight, gone after, and the two-Point Kill leaves at least 1.4 times the coloured mass of a one-Point Kill.
4. **Start-time records, step creates and expires only.** The step appends at a Kill and filters on a Tick; the Scene holds no times (a test builds the same Scene from states differing only in `lastTime`); `buildScene` purity test (same input, same Scene; a different time gives a different Scene). Tests assert Kills change nothing but the record list beyond their usual effects.
5. **Animations finish after Round end.** Tests: a Round with 1 Life ends with a record in flight; it is still there in `Over`, signs are drawn, a later Tick changes only `killAnims`, `Over` Ticks do not move `lastTime`, and the record is dropped at its end. Browser (1 Life, fast Hit): at Over the hook still holds the record, Plus Signs are on screen outside the Summary panel, the record expires at its end (within 0.3 s of it, observed with the page clock), every other field of the state is unchanged since the Round ended, and no sign-coloured pixels remain after.
6. **Builder tests assert evaluated positions, scales and colours** at chosen times: see 1 and 3.

Mutations: ease-in made linear (`fly` instead of `fly * fly` in `Game.Scene`): the fly test went red (1 failure). Plus count `min (points - 1) cap`: 7 failures (record, count, cap, expiry and round-end cases). Both restored.

Gates (AGENTS.md names none; the README's): `nix build .#haskell-nix --cores 4 -L` ok and no `warning: [GHC` in the log (the first build had a `-Wname-shadowing` on `colour`, fixed); `nix build .#checks.aarch64-darwin.common-test .#checks.aarch64-darwin.renderer-test --cores 4 --rebuild` ok.

Decisions not in the spec (also in the README, "Shot and Plus Signs"):

- **Record shape.** One `KillAnim` per Kill with a list of `PlusSign` parameters (capped at `plusDrawCap` at creation, with `kaPoints` keeping the Points), the durations stored from the Round snapshot. The builder reads times from the record, colour from `shotColour cfg`.
- **Time base.** Record start is `lastTime`, the previous Tick's raw rAF timestamp (the builder's `Frame.time` base); not `roundTime`. A Kill therefore starts up to one frame early. Expiry is on Tick timestamps in every Phase (including paused and `Over`); in `Over` the step touches nothing else. Verified in the page: `lastTime` and `performance.now()/1000` agree within 0.3 s.
- **Streak value for colour:** the Streak after the Kill (the meter reads the same Streak).
- **Dying Enemy (spec ambiguity, flagged).** Spec section 9: "The Enemy is removed and Plus Signs spawn on arrival." Tickets 17 and 18 remove the Enemy from `enemies` at the Kill, so typing, Focus, Hits and the Hit/Round-end logic never depend on a Shot in flight. I kept that, and the builder draws the Enemy's square (no Word) from the record until the Shot arrives. The alternative (keep the Enemy in `enemies` until arrival) would let a Shot-in-flight Enemy be Focused or touch the Player and was rejected. On Round end the dying squares of Kills in flight are also kept until they arrive (they last at most `shotDuration`).
- **Separate animation generator.** `animRng` (derived from the seed) so adding animations did not change any existing seeded game; the spec says "seeded from `GameState`", which still holds.
- **Constants not settings** (in `Game.Layout`): Shot 0.5 by 0.3, Plus Sign 0.5 with bars 0.2 of its size thick, stagger max 0.15 s, shrink time 0.15 s, shrink scale 0.3. The shrink time is `min 0.15 plusFlyDuration`.
- **Fade with two overlapping squares.** The sign's two squares each carry the alpha, so the crossing is slightly more opaque than the arms while fading; not noticeable.
- **Hook** gained `lastTime`, `killAnims`, `shots`, `plusSigns`, `anims`. In `Over`, `lastTime` is frozen, so `shots` and `plusSigns` are too (the page's `anims` list and the clock give the live picture).
- **`Start` clears the records** (a new Round starts with an empty field); in-flight animations of an abandoned Round are not carried into "Play again".
- **Spec deviation: none.** Item 6 and 7 of section 14 hold.
