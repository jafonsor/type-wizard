-- | The typing table of spec section 4, row by row, on hand-made Rounds: a
-- Running state with chosen Enemies (positions and Words set by the test, no
-- spawning), so each row is one short fold of 'Key' and 'Tab' inputs.
module TypingTests (typingTests, roundWith, enemyAt, press, keys) where

import Data.Text (Text)
import Data.Text qualified as T
import Test.HUnit

import Game.Save (emptySave)
import Game.Settings (Settings (..))
import Game.State
import StateTests (runTicks, testWords, tinyCfg)

-- | An Enemy of the given id at the given position with the given Word.
enemyAt :: Int -> (Double, Double) -> Text -> Enemy
enemyAt i (x, y) w = Enemy { enemyId = i, enemyPos = Vec2 x y, enemyWord = w, enemyTier = 3 }

-- | A Running Round (fixed seed) holding exactly these Enemies.
roundWith :: [Enemy] -> GameState
roundWith es = (step tinyCfg testWords (Start 1 emptySave) initialState) { enemies = es, nextEnemyId = length es }

press :: Input -> GameState -> GameState
press = step tinyCfg testWords

-- | Presses a string of letters in order.
keys :: String -> GameState -> GameState
keys cs st = foldl' (flip (press . Key)) st cs

-- | Two Enemies: "cat" (id 0) and "dog" (id 1).
catDog :: GameState
catDog = roundWith [enemyAt 0 (6, 0) "cat", enemyAt 1 (0, 9) "dog"]

focusOf :: GameState -> Focus
focusOf = (.focus)

tally :: GameState -> (Int, Int, Int)
tally st = (st.correctKeys, st.wrongKeys, st.typos)

typingTests :: Test
typingTests = TestLabel "typing" $ TestList [idleRows, focusedRows, lockedRows, tabRows, killRows, phaseRows, countRows]

idleRows :: Test
idleRows = TestLabel "idle" $ TestList
  [ "Idle plus a first letter Focuses that Enemy with k = 1, a correct Keystroke" ~: do
      let st = keys "d" catDog
      focusOf st @?= Focused 1 1
      tally st @?= (1, 0, 0)

  , "Idle plus a letter matching no Word does nothing: not a Keystroke, not a Typo" ~: do
      let st = keys "zq" catDog
      st @?= catDog

  , "a letter that only matches a later letter of a Word is no Focus" ~: keys "a" catDog @?= catDog

  , "the closest Enemy wins when several Words start with the letter" ~: do
      let st = keys "c" (roundWith [enemyAt 0 (9, 0) "cab", enemyAt 1 (3, 0) "cow", enemyAt 2 (6, 0) "cub"])
      focusOf st @?= Focused 1 1

  , "distance is Euclidean, centre to Player: (3,4) is nearer than (0,6)" ~: do
      let st = keys "c" (roundWith [enemyAt 0 (0, 6) "cab", enemyAt 1 (3, 4) "cow"])
      focusOf st @?= Focused 1 1

  , "a tie in distance goes to the earlier spawn" ~: do
      let st = keys "c" (roundWith [enemyAt 3 (5, 0) "cab", enemyAt 1 (0, 5) "cow", enemyAt 2 (-5, 0) "cub"])
      focusOf st @?= Focused 1 1
      -- and the order of the list does not matter
      focusOf (keys "c" (roundWith [enemyAt 2 (-5, 0) "cub", enemyAt 1 (0, 5) "cow"])) @?= Focused 1 1

  , "Enemies parked at contact (equal up to rounding) tie: the earliest spawn wins" ~: do
      let st = runTicks tinyCfg testWords 5 0.05 1500
          parked = [ e | e <- st.enemies, e.enemyTier == 3 ]
          firsts = [ T.head e.enemyWord | e <- parked ]
          shared = [ c | c <- "abcd", length (filter (== c) firsts) >= 2 ]
      assertBool "enough parked Enemies" (length parked >= 6)
      assertBool "all parked" (all (\e -> distanceToPlayer st e < 1.1 + 1e-6) parked)
      assertBool "a letter is shared" (not (null shared))
      sequence_
        [ focusOf (press (Key c) st) @?= Focused (minimum [ e.enemyId | e <- parked, T.head e.enemyWord == c ]) 1
        | c <- shared ]

  , "a parked Enemy (touching the Player) can be Focused" ~:
      focusOf (keys "c" (roundWith [enemyAt 0 (1.1, 0) "cat", enemyAt 1 (8, 0) "cow"])) @?= Focused 0 1
  ]

focusedRows :: Test
focusedRows = TestLabel "focused" $ TestList
  [ "the correct next letter advances k" ~: do
      let st = keys "ca" catDog
      focusOf st @?= Focused 0 2
      tally st @?= (2, 0, 0)

  , "a Focused Enemy keeps the Focus even when another matching Enemy is closer" ~: do
      let st = keys "co" (roundWith [enemyAt 0 (9, 0) "cab", enemyAt 1 (3, 0) "cow"])
      focusOf st @?= Focused 1 2 -- 'c' took cow (closer); 'o' continues it

  , "a wrong letter is a Typo: Locked at the same k, a wrong Keystroke" ~: do
      let st = keys "cx" catDog
      focusOf st @?= Locked 0 1
      tally st @?= (1, 1, 1)

  , "a letter that starts another Word is still a Typo while Focused" ~: do
      let st = keys "cd" catDog
      focusOf st @?= Locked 0 1
      tally st @?= (1, 1, 1)
  ]

lockedRows :: Test
lockedRows = TestLabel "locked" $ TestList
  [ "the expected letter unlocks: Focused with k + 1, a correct Keystroke" ~: do
      let st = keys "cxa" catDog
      focusOf st @?= Focused 0 2
      tally st @?= (2, 1, 1)

  , "another letter while Locked is a wrong Keystroke, not a new Typo, still Locked" ~: do
      let st = keys "cxyz" catDog
      focusOf st @?= Locked 0 1
      tally st @?= (1, 3, 1)

  , "the letter that was typed wrongly does not unlock, the same wrong letter again is wrong" ~: do
      let st = keys "cxx" catDog
      focusOf st @?= Locked 0 1
      tally st @?= (1, 2, 1)

  , "a Typo, a second Typo after unlocking, tally two Typos" ~: do
      let st = keys "cxaz" catDog
      focusOf st @?= Locked 0 2
      tally st @?= (2, 2, 2)

  , "a Typo on the last letter, then the expected letter, is a Kill; a letter after a Kill matching no Word does nothing" ~: do
      let st = keys "catx" catDog
      -- 't' completes the Word, so "catx" is a Kill then no match: x does nothing
      st.kills @?= 1
      let st' = keys "caxt" catDog
      st'.kills @?= 1
      focusOf st' @?= NoFocus
      tally st' @?= (3, 1, 1)
  ]

tabRows :: Test
tabRows = TestLabel "tab" $ TestList
  [ "Tab from Focused clears the Focus; Words are default (k = 0); counters untouched" ~: do
      let before = keys "ca" catDog
          after = press Tab before
      focusOf after @?= NoFocus
      tally after @?= tally before
      after.enemies @?= before.enemies

  , "Tab from Locked clears Focus and Lock; counters untouched" ~: do
      let before = keys "cx" catDog
          after = press Tab before
      focusOf after @?= NoFocus
      tally after @?= tally before

  , "Tab in Idle does nothing" ~: press Tab catDog @?= catDog

  , "after Tab the same Enemy can be Focused again and typed from k = 0" ~: do
      let st = keys "ca" (press Tab (keys "ca" catDog))
      focusOf st @?= Focused 0 2

  , "after Tab the closest Enemy is chosen afresh" ~: do
      let st = keys "c" (press Tab (keys "c" (roundWith [enemyAt 0 (9, 0) "cab", enemyAt 1 (3, 0) "cow"])))
      focusOf st @?= Focused 1 1

  , "the Enemy keeps moving after Tab" ~: do
      let st = press Tab (keys "c" (roundWith [enemyAt 0 (9, 0) "cab"]))
          t1 = press (Tick 10) st
          t2 = press (Tick 11) t1
      case (t1.enemies, t2.enemies) of
        ([a], [b]) -> assertBool "closer" (b.enemyPos.vx < a.enemyPos.vx)
        _ -> assertFailure "the Enemy is gone"
  ]

killRows :: Test
killRows = TestLabel "kill" $ TestList
  [ "typing the whole Word is a Kill: the Enemy is removed and the state is Idle" ~: do
      let st = keys "cat" catDog
      map (.enemyWord) st.enemies @?= ["dog"]
      focusOf st @?= NoFocus
      st.kills @?= 1
      tally st @?= (3, 0, 0)

  , "after a Kill the next letter Focuses afresh" ~: do
      let st = keys "catd" catDog
      focusOf st @?= Focused 1 1

  , "a Kill after a Typo tally the wrong key too" ~: do
      let st = keys "cxat" catDog
      st.kills @?= 1
      tally st @?= (3, 1, 1)

  , "the Enemy of the Kill moves on no more: other Enemies keep their ids" ~: do
      let st = keys "cat" (roundWith [enemyAt 0 (6, 0) "cat", enemyAt 1 (0, 9) "dog", enemyAt 2 (4, 4) "elk"])
      map (.enemyId) st.enemies @?= [1, 2]
  ]

phaseRows :: Test
phaseRows = TestLabel "phase" $ TestList
  [ "keys and Tab are ignored before Start (Idle phase)" ~: do
      let st = initialState { enemies = catDog.enemies }
      step tinyCfg testWords (Key 'c') st @?= st
      step tinyCfg testWords Tab st @?= st

  , "keys and Tab are ignored when the Round is Over" ~: do
      let over = (keys "c" catDog) { phase = Over }
      press (Key 'a') over @?= over
      press Tab over @?= over

  , "only a-z letters are Keystrokes" ~: do
      press (Key 'C') catDog @?= catDog
      press (Key '1') catDog @?= catDog
      press (Key ' ') catDog @?= catDog
      let focused = keys "c" catDog
      press (Key 'A') focused @?= focused
      press (Key '-') focused @?= focused

  , "Start resets Focus and the counters" ~: do
      let st = step tinyCfg testWords (Start 2 emptySave) (keys "cx" catDog)
      focusOf st @?= NoFocus
      tally st @?= (0, 0, 0)
      st.kills @?= 0
  ]

near :: Double -> Double -> Bool
near a b = abs (a - b) < 1e-9

countRows :: Test
countRows = TestLabel "accuracy and WPM" $ TestList
  [ "Accuracy is 100 with no Keystrokes" ~: accuracy catDog @?= 100

  , "a no-match key in Idle and Tab do not change Accuracy" ~: accuracy (press Tab (keys "zz" catDog)) @?= 100

  , "Accuracy = correct / (correct + wrong): 3 correct, 1 wrong is 75" ~: do
      let st = keys "cxat" catDog
      assertBool (show (accuracy st)) (near (accuracy st) 75)

  , "wrong letters while Locked lower Accuracy: 1 correct, 3 wrong is 25" ~: do
      let st = keys "cxyz" catDog
      assertBool (show (accuracy st)) (near (accuracy st) 25)

  , "Tab costs no Accuracy" ~: do
      let st = keys "cxa" catDog
      accuracy (press Tab st) @?= accuracy st

  , "WPM is 0 before time passes, and with no Keystroke" ~: do
      wpm catDog @?= 0
      wpm (keys "cat" catDog) @?= 0

  , "WPM = (correct characters / 5) / minutes from the first Keystroke" ~: do
      -- type "ca" at Round time 0, then 6 seconds pass: 2 chars -> 0.4 words in 0.1 min = 4
      let st0 = keys "ca" catDog
          later = st0 { roundTime = st0.roundTime + 6 }
      assertBool (show (wpm later)) (near (wpm later) 4)
      -- more correct characters later raise it: 3 chars in the same 6 s = 6 WPM
      let done = (keys "t" later) { roundTime = 6 }
      assertBool (show (wpm done)) (near (wpm done) 6)

  , "WPM time starts at the first Keystroke, not at Round start" ~: do
      let st0 = catDog { roundTime = 10 }
          st1 = keys "ca" st0
          st2 = st1 { roundTime = 16 }
      assertBool (show (wpm st2)) (near (wpm st2) 4)

  , "a wrong first Keystroke also starts the WPM clock" ~: do
      let st = (keys "cx" catDog) { roundTime = 6 }
      st.firstKeyAt @?= Just 0

  , "the Round time is the sum of clamped Tick steps (a long gap adds maxTickDt)" ~: do
      let st = foldl' (flip press) catDog [Tick 10, Tick 11, Tick 500]
      assertBool (show st.roundTime) (near st.roundTime (tinyCfg.maxTickDt * 2))

  , "typing is deterministic: the same inputs give the same state" ~:
      keys "cxatd" catDog @?= keys "cxatd" catDog
  ]
