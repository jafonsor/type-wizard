# 18: Scoring: Streak, Bonus, Points

**What to build:** Kills score. Streak, Bonus and Points follow spec section 4, the Streak persists between Rounds and visits, and the HUD and the Player's side show the numbers.

**Source:** `.scratch/type-wizard/spec.md`

**Blocked by:** 14, 17

**Status:** done

- [x] A Kill increments the Streak first, then awards 1 plus floor(Streak / group size); the 10th consecutive Kill pays 2 and there is no cap
- [x] A Typo clears Streak, Bonus and the meter immediately
- [x] The Streak is read from saved progress at Start and written on every Kill and Typo
- [x] The HUD shows Round Points and Total Points and the Streak; the Streak Meter and the '+N' label appear next to the Player as static nodes, hidden at Bonus 0
- [x] Longest Streak counts from 0 at Round start regardless of the carried-in Streak
- [x] Tests cover the 10th-Kill payout, Typo clearing, and the carried-in Streak case

## Answer

Built and checked on 2026-11-24. Criterion -> mechanism:

1. **A Kill increments the Streak first, then pays 1 + floor(Streak / group size); the 10th Kill pays 2; no cap.** Pure tests (`common/test/ScoringTests.hs`, `common-test`: 202 cases, 0 failures; fixed seed, injected Word list): at group size 2 and Streak 1 the next Kill (Streak 2) pays 2 (the old Streak would pay 1); Kills 1 to 9 pay 1, the 10th pays 2 (Round Points 11), Kills 10 to 19 pay 2 and the 20th pays 3; carried-in Streak 1000 and a Kill pays 101; group size 5 gives 1,1,1,1,2,2,2,2,2,3; the Bonus is floor(Streak / group size). Browser (built page in headless Chrome, `check18.mjs`, real CDP key events, localStorage seeded with Streak 7, Total 5): Kills 1 to 3 reach Streak 8, 9, 10 with Round Points 1, 2, 4 (the third pays 2), Kill 4 (Streak 11) pays 2 (Round Points 6).
2. **A Typo clears Streak, Bonus and the meter at once.** Tests: carried 27 (Bonus 2, meter 0.7) then a Typo gives 0, 0, 0 and clears `groupCompletedAt`; the next Kill starts at Streak 1. A Locked wrong letter is not a new Typo (typos stay 1); Tab and a no-match letter leave Streak 27 and Bonus 2 alone. Browser: after a Typo the hook shows Streak 0, Bonus 0, meter 0, and `localStorage['typewizard.save']` read straight after shows `streak: 0, bonus: 0` (Total Points 5 kept); pixels: no fill and no "+N". Then a wrong key while Locked: typos still 1; Tab: Streak still 0.
3. **The Streak is read from saved progress at Start and written on every Kill and Typo.** `Start seed save` (state tests: carried 27 gives Streak 27, Bonus 2, meter 0.7, Points 0; saved Bonus is ignored; a second Start carries the Streak it is given and resets the Round's counters). `gameCanvas` reads `current save` at Start and emits `progressSave` on each Kill or Typo, applied by the switch's `saveEdit`. Browser: save is `streak 8 bonus 0`, then `10/1` after the third Kill, `0/0` after the Typo, `2/0` after two Kills; the Start page shows the Streak after Menu (Streak 11 and Bonus 1, Total 5), Play again starts from Streak 11 (Bonus 1, meter 0.1, label drawn from the first frame), and after a real reload (new `Page.navigate`) the Start page shows Streak 2 and the next Round starts from 2.
4. **HUD and meter next to the Player.** `buildScene` tests with query helpers: HUD lines "Points 8", "Total 321", "Streak 12" (top-right right-anchored, bottom-centre centred, inside the view); the meter group (track 2 x 0.25 at 1.6 above, `#2a3140`); fill width (Streak mod group) / group x 2 (0.8 at 4, 1 at 5, 1.8 at 29; follows group size), left aligned, Shot colour; no fill and no label at Streak 0; "+N" absent at Bonus 0 (Streak 9), present at 10 ("+1") and 34 ("+3"), gone after a Typo. Browser pixels (800x600, 30 px per unit): fill 42 px at 0.7, 48 px at 0.8, empty at Streak 10, 6 px at 11, left edge at the track's left end; the dim track is drawn; no label at Streak 8 and 9, label pixels in the group-1 Shot colour at Bonus 1 and after Play again, none after the Typo; the Points and Streak HUD regions' pixels changed after Kill 1 and the Total region did not. Screenshot read by eye (`game18-2-bonus1.png`): "Points 4" and "Total 5" top-right, "Streak 10" bottom-centre, empty track and a blue "+1" beside it.
5. **Longest Streak counts from 0.** Tests: carried 7 plus 5 Kills is Streak 12, Longest Streak 5; carried 40 plus 2 is 42 and 2; the best run survives a Typo (3, then 0, then 2 keeps 3), a later better run raises it. Browser: carried 7 plus 3 Kills shows Longest Streak 3; the Play-again Round carried 11 shows Longest Streak 0, then 1 after a Kill; after the reload carried 2 plus 3 Kills shows 3.
6. **Tests cover the 10th-Kill payout, Typo clearing and the carried-in case.** As in 1, 2 and 5, plus the ramp: `shotColour` is `#4aa3ff` at 0 and 9, `#ff3b3b` at 100, 200 and 100000, steps once per group (10 and 19 equal), the halfway stop (50) is the channel mean, there are 11 distinct stops, it follows the group size (at 4, Streak 40 is the end colour, 39 is not) and the ramp colours (settings).

Mutation: made the Kill pay with the old Streak (`1 + st.streak div size`); `common-test` went red with 5 failures (the "Streak before Points" case, the 10th Kill, 10 to 19 and 20th, group size 5, and the accumulating case). Restored; green again.

Gates (AGENTS.md names none; the README's): `nix build .#haskell-nix --cores 4 -L` ok, `nix log` has no `warning: [GHC` lines (the first build showed one `-Wname-shadowing` in `shotColour`'s argument, fixed); `nix build .#checks.aarch64-darwin.common-test .#checks.aarch64-darwin.renderer-test --cores 4 --rebuild` green; `check18.mjs` (35 checks) against `tools/export-site.sh` output, the only console entry a `favicon.ico` 404.

Decisions not in the spec:

- **`Start seed save`**: `Start` takes the whole `Save` (Streak and Total Points), not just the Streak, because the HUD needs Total Points in `GameState` and `buildScene` takes only the state. Every other input keeps its shape. All existing tests pass `emptySave`.
- **State shape.** `streak`, `roundPoints`, `longestStreak`, `runKills` (the Round's current run; Longest Streak is its maximum, as a Typo ends a run), `totalPoints` (carried in, unchanged until ticket 19 banks), and `groupCompletedAt :: Maybe Double` (Round time of the latest completing Kill, cleared by a Typo). Bonus and the meter fill are derived functions (`streakBonus`, `meterFill`), not fields, so they cannot disagree with the Streak. A group-completing Kill leaves `meterFill` at 0; "full" exists only as the `groupCompletedAt` record for ticket 22.
- **Save consistency.** The written Bonus is `floor(streak / group size)` with the Round's group size (`progressSave`). On load the Round ignores the saved Bonus and derives it, so a group-size change between sessions shows on the Start page the stored Bonus until the next Kill or Typo (the Start page shows the save as written).
- **Write trigger.** A new state with more `kills` or `typos` than the previous one (not on Start), so a Typo at Streak 0 still writes 0.
- **HUD wording and placement.** "Points N", "Total N" (two lines, 0.6 from the edges, 0.8 high, the Total line 1.0 units below the Points line), "Streak N" bottom-centre, letter default colour. Layout constants are in `Game.Layout`. The "+N" label sits to the right of the bar, in the Shot colour.
- **Scene order.** The meter and label are one `Group` right after the Player and before the Enemies (Enemies draw over it), so existing scene-test helpers moved from 3 to 4 leading nodes.
- **Ramp.** `Game.Scene.shotColour :: Settings -> Int -> Colour` takes the Streak. "Linear RGB" is read as linear interpolation of the `#rrggbb` channel values, not of linear-light values (spec ambiguity; flag if gamma-correct blending was meant).
- **Hook JSON** gained `streak`, `bonus`, `roundPoints`, `longestStreak`, `meter`, `totalPoints`, `groupCompletedAt`.
- No contradiction with the spec. The browser check did not assert the HUD's exact glyph positions (the pure tests do) and did not check the top-left and bottom-left corners empty (the DOM Menu control sits top-left and Enemies may pass bottom-left); the pure tests show the overlay has exactly the three lines.
