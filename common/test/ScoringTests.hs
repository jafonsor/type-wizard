-- | Streak, Bonus, Points and the Streak Meter (spec section 4, "Scoring"),
-- on hand-made Rounds: a Running state (fixed seed) holding chosen Enemies,
-- the saved progress carried in through 'Start'.
module ScoringTests (scoringTests, scoredRound, killsFrom) where

import Test.HUnit

import Game.Save (Save (Save), emptySave)
import Game.Save qualified as Sv
import Game.Settings (Settings (..))
import Game.State
import StateTests (testWords, tinyCfg)
import TypingTests (enemyAt, keys, press)

-- | A Running Round (seed 1) holding these Enemies, started with the given
-- saved progress and Settings.
scoredRound :: Settings -> Save -> [Enemy] -> GameState
scoredRound cfg sv es = (step cfg testWords (Start 1 sv) initialState) { enemies = es, nextEnemyId = length es }

-- | n Enemies, all with the Word "cat", spread on distinct rays.
cats :: Int -> [Enemy]
cats n = [ enemyAt i (6 + fromIntegral i, 0) "cat" | i <- [0 .. n - 1] ]

-- | The state after each of n Kills (typing "cat" n times), starting from a Round
-- that holds n "cat" Enemies. The list has n elements.
killsFrom :: Settings -> Save -> Int -> [GameState]
killsFrom cfg sv n = drop 1 (scanl (\st _ -> typeCat st) (scoredRound cfg sv (cats n)) [1 .. n])
  where
    typeCat st = foldl' (flip (step cfg testWords . Key)) st ("cat" :: String)

-- | The Points paid by Kill number i (from 1): the difference of the Round's Points.
payouts :: [GameState] -> [Int]
payouts sts = zipWith (-) (map (.roundPoints) sts) (0 : map (.roundPoints) sts)

carried :: Int -> Save
carried s = emptySave { Sv.streak = s }

scoringTests :: Test
scoringTests = TestLabel "scoring" $ TestList [payoutRows, typoRows, streakRows, startRows, meterRows]

payoutRows :: Test
payoutRows = TestLabel "payout" $ TestList
  [ "the Streak goes up before the Points are paid: at group size 2 and Streak 1, the next Kill (Streak 2) pays 2, not 1" ~: do
      let st = last (killsFrom tinyCfg { streakGroupSize = 2 } (carried 1) 1)
      st.streak @?= 2
      st.roundPoints @?= 2

  , "Kills 1 to 9 pay 1 each, the 10th pays 2 (1 + floor (10 / 10))" ~: do
      let sts = killsFrom tinyCfg emptySave 10
      take 9 (payouts sts) @?= replicate 9 1
      payouts sts !! 9 @?= 2
      (last sts).streak @?= 10
      (last sts).roundPoints @?= 11

  , "Kills 10 to 19 pay 2 and the 20th pays 3" ~: do
      let ps = payouts (killsFrom tinyCfg emptySave 20)
      take 9 ps @?= replicate 9 1
      take 10 (drop 9 ps) @?= replicate 10 2
      ps !! 19 @?= 3

  , "there is no cap: Streak 1000 carried in, the next Kill (1001) pays 1 + 100" ~: do
      let st = last (killsFrom tinyCfg (carried 1000) 1)
      st.streak @?= 1001
      st.roundPoints @?= 101

  , "the group size is a setting: at 5 the 5th Kill pays 2 and the 10th pays 3" ~: do
      let ps = payouts (killsFrom tinyCfg { streakGroupSize = 5 } emptySave 10)
      ps @?= [1, 1, 1, 1, 2, 2, 2, 2, 2, 3]

  , "the Round's Points accumulate over the Kills" ~: do
      let sts = killsFrom tinyCfg (carried 7) 5
      -- Streaks 8, 9, 10, 11, 12 pay 1, 1, 2, 2, 2
      payouts sts @?= [1, 1, 2, 2, 2]
      (last sts).roundPoints @?= 8
      (last sts).kills @?= 5

  , "the Bonus is floor (Streak / group size) and follows the group size" ~: do
      let b cfg s = streakBonus (scoredRound cfg (carried s) [])
      b tinyCfg 9 @?= 0
      b tinyCfg 10 @?= 1
      b tinyCfg 29 @?= 2
      b tinyCfg { streakGroupSize = 4 } 9 @?= 2

  , "Total Points are not banked by a Kill (the Round-end slice owns that)" ~: do
      let st = last (killsFrom tinyCfg emptySave { Sv.totalPoints = 40 } 3)
      st.totalPoints @?= 40
  ]

typoRows :: Test
typoRows = TestLabel "typo" $ TestList
  [ "a Typo clears the Streak, the Bonus and the meter at once" ~: do
      let st0 = scoredRound tinyCfg (carried 27) [enemyAt 0 (6, 0) "cat"]
      (streakBonus st0, meterFill st0) @?= (2, 0.7)
      let st = keys "cx" st0
      st.streak @?= 0
      streakBonus st @?= 0
      meterFill st @?= 0
      st.groupCompletedAt @?= Nothing

  , "the persisted progress after a Typo is Streak 0 and Bonus 0 (Total Points kept)" ~: do
      let st = keys "cx" (scoredRound tinyCfg (carried 27) [enemyAt 0 (6, 0) "cat"])
      progressSave st (Save 55 27 2) @?= Save 55 0 0

  , "the persisted progress after a Kill is the new Streak and its Bonus (group size in force)" ~: do
      let st = last (killsFrom tinyCfg { streakGroupSize = 4 } (carried 7) 1)
      progressSave st (Save 55 7 1) @?= Save 55 8 2

  , "a wrong letter while Locked is not a new Typo: the Typo count and the Streak (already 0) stay" ~: do
      let st1 = keys "cx" (scoredRound tinyCfg (carried 27) [enemyAt 0 (6, 0) "cat"])
          st2 = keys "yz" st1
      st1.typos @?= 1
      st2.typos @?= 1
      (st2.streak, st2.focus) @?= (0, Locked 0 1)

  , "after a Typo the next Kill starts the Streak again: 1, paying 1" ~: do
      let st = keys "cxat" (scoredRound tinyCfg (carried 27) [enemyAt 0 (6, 0) "cat"])
      (st.streak, st.roundPoints, st.kills) @?= (1, 1, 1)

  , "Tab and a letter that matches no Word do not touch the Streak" ~: do
      let st0 = scoredRound tinyCfg (carried 27) [enemyAt 0 (6, 0) "cat"]
          focused = keys "c" st0
      (press Tab focused).streak @?= 27
      (keys "q" st0).streak @?= 27
      (keys "q" st0).typos @?= 0
      streakBonus (press Tab focused) @?= 2
  ]

streakRows :: Test
streakRows = TestLabel "longest streak" $ TestList
  [ "Longest Streak counts from 0 at Round start: carried-in 7 plus 5 Kills is Streak 12, Longest Streak 5" ~: do
      let st = last (killsFrom tinyCfg (carried 7) 5)
      (st.streak, st.longestStreak) @?= (12, 5)

  , "Longest Streak keeps the best run across a Typo" ~: do
      let st0 = scoredRound tinyCfg (carried 7) (cats 6)
          run3 = keys "catcatcat" st0
          typo = keys "cx" run3
          again = keys "atcat" typo -- finishes the locked Word, then one more Kill
      (run3.streak, run3.longestStreak) @?= (10, 3)
      (typo.streak, typo.longestStreak) @?= (0, 3)
      (again.streak, again.longestStreak) @?= (2, 3)

  , "a new best run after a Typo raises Longest Streak" ~: do
      let st0 = scoredRound tinyCfg emptySave (cats 6)
          st = keys "catcxatcatcatcat" st0
      (st.streak, st.longestStreak) @?= (4, 4)
  ]

startRows :: Test
startRows = TestLabel "start" $ TestList
  [ "Start carries the Streak in; the Bonus and the meter follow from it" ~: do
      let st = scoredRound tinyCfg (carried 27) []
      st.streak @?= 27
      (streakBonus st, meterFill st) @?= (2, 0.7)
      (st.roundPoints, st.longestStreak, st.kills) @?= (0, 0, 0)

  , "the saved Bonus is not trusted: it is derived from the Streak and the group size in force" ~: do
      streakBonus (scoredRound tinyCfg emptySave { Sv.streak = 27, Sv.bonus = 9 } []) @?= 2

  , "Start carries the Total Points in, for the HUD" ~: totalPoints' (scoredRound tinyCfg emptySave { Sv.totalPoints = 321 } []) @?= 321

  , "a second Start (Play again) carries the Streak it is given and resets the Round's counters" ~: do
      let st1 = last (killsFrom tinyCfg (carried 7) 5)
          st2 = step tinyCfg testWords (Start 2 (carried st1.streak)) st1
      st2.streak @?= 12
      (st2.roundPoints, st2.longestStreak, st2.kills, st2.typos, st2.runKills) @?= (0, 0, 0, 0, 0)
      st2.groupCompletedAt @?= Nothing

  , "Longest Streak after a carried-in Streak counts the Round's own Kills only" ~: do
      let st2 = last (killsFrom tinyCfg (carried 40) 2)
      (st2.streak, st2.longestStreak) @?= (42, 2)
  ]
  where totalPoints' st = st.totalPoints

meterRows :: Test
meterRows = TestLabel "meter" $ TestList
  [ "the meter shows (Streak mod group) / group" ~: do
      meterFill (scoredRound tinyCfg (carried 0) []) @?= 0
      meterFill (scoredRound tinyCfg (carried 4) []) @?= 0.4
      meterFill (scoredRound tinyCfg { streakGroupSize = 4 } (carried 6) []) @?= 0.5

  , "a Kill that completes a group reads empty again and records when it completed" ~: do
      let st0 = (scoredRound tinyCfg (carried 9) [enemyAt 0 (6, 0) "cat"]) { roundTime = 3.5 }
          st = keys "cat" st0
      st.streak @?= 10
      meterFill st @?= 0
      st.groupCompletedAt @?= Just 3.5

  , "a Kill that does not complete a group leaves the record alone" ~: do
      let st0 = (scoredRound tinyCfg (carried 5) [enemyAt 0 (6, 0) "cat"]) { roundTime = 3.5 }
      (keys "cat" st0).groupCompletedAt @?= Nothing
      (keys "cat" st0).streak @?= 6
  ]
