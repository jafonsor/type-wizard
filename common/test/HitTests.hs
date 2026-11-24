-- | Hits, the Grace Period, Lives, Round end, banking and Blur (spec section 4,
-- "Hit, Grace Period, Lives, Round end"; section 8, "Blur"), on hand-made
-- Rounds with a fixed seed and the injected Word list.
module HitTests (hitTests) where

import Data.Maybe (catMaybes, fromMaybe)
import Test.HUnit

import Game.Save (Save (..), emptySave)
import Game.Settings (Settings (..))
import Game.State
import Game.Summary (fixed1, summaryRows)
import StateTests (testWords, tinyCfg)
import TypingTests (enemyAt)

-- | Quiet rules: no spawn for 100 s (Enemies are hand-placed), Grace 0.5 s
-- (exact in binary), 3 Lives, a generous Tick clamp.
cfg :: Settings
cfg = tinyCfg { intervalStart = 100, intervalEnd = 100, gracePeriod = 0.5, startingLives = 3, maxTickDt = 60 }

-- | A Running Round holding these Enemies, with a first Tick at 100 (dt 0).
roundOf :: Settings -> Save -> [Enemy] -> GameState
roundOf c save es = step c testWords (Tick 100)
  ((step c testWords (Start 1 save) initialState) { enemies = es, nextEnemyId = length es })

-- | A Save with these Total Points and Streak.
sv :: Int -> Int -> Save
sv t s = Save { totalPoints = t, streak = s, bonus = 0 }

-- | The Round Result of a state that has one.
resultOf :: GameState -> RoundResult
resultOf st = fromMaybe (error "no Round Result") st.roundResult

-- | An Enemy already touching the Player (distance 1.1), on the +x side.
touch :: Int -> Enemy
touch i = enemyAt i (1.1, 0) "cat"

-- | The state after each Tick at t = 100 + dt * i, i = 1 .. n.
advanceBy :: Settings -> Double -> Int -> GameState -> [GameState]
advanceBy c dt n st0 = drop 1 (scanl (\st i -> step c testWords (Tick (100 + dt * i)) st) st0 (map fromIntegral [1 .. n]))

press :: Settings -> Input -> GameState -> GameState
press c = step c testWords

typeKeys :: Settings -> String -> GameState -> GameState
typeKeys c cs st = foldl' (flip (press c . Key)) st cs

hitTests :: Test
hitTests = TestLabel "hits" $ TestList [hitRows, graceRows, overRows, resultRows, bankRows, blurRows, summaryRowsTests]

hitRows :: Test
hitRows = TestLabel "hit" $ TestList
  [ "an Enemy touching the Player costs one Life and starts the Grace Period" ~: do
      let st = roundOf cfg emptySave [touch 0]
      st.lives @?= 2
      graceActive st @?= True
      st.graceStart @?= Just 0
      st.phase @?= Running

  , "a Round starts with full Lives, no Grace, not paused" ~: do
      let st = step cfg testWords (Start 1 emptySave) initialState
      (st.lives, st.graceStart, st.paused, st.roundResult) @?= (3, Nothing, False, Nothing)

  , "an Enemy that walks up to the Player Hits when it parks, not before" ~: do
      let sts = advanceBy cfg 0.25 12 (roundOf cfg emptySave [enemyAt 0 (3, 0) "cat"])
          (before, after) = span ((== 3) . (.lives)) sts
      assertBool "walked for a while first" (length before >= 5)
      case after of
        st : _ -> do
          st.lives @?= 2
          [ distanceToPlayer st e <= 1.1 + 1e-6 | e <- st.enemies ] @?= [True]
        [] -> assertFailure "never Hit"

  , "an Enemy still on its way (just outside contact) does not Hit" ~: do
      let sts = advanceBy cfg 0.25 4 (roundOf cfg emptySave [enemyAt 0 (5, 0) "cat"])
      map (.lives) sts @?= [3, 3, 3, 3]
      map (.graceStart) sts @?= replicate 4 Nothing
      [ distanceToPlayer st e > 1.1 | st <- sts, e <- st.enemies ] @?= replicate 4 True

  , "a Hit never touches the Streak, Bonus, runs or Points" ~: do
      let carried = (sv 5 7)
          st0 = roundOf cfg carried []
          st = roundOf cfg carried [touch 0]
      st.lives @?= 2
      (st.streak, streakBonus st, st.runKills, st.longestStreak, st.roundPoints) @?= (st0.streak, streakBonus st0, st0.runKills, st0.longestStreak, st0.roundPoints)
      st.streak @?= 7

  , "an Enemy is not removed by touching" ~: do
      let c = cfg { startingLives = 10 }
          sts = advanceBy c 0.25 6 (roundOf c emptySave [touch 0])
      map (length . (.enemies)) sts @?= replicate 6 1

  , "several Enemies touching at once cost one Life per Hit moment" ~: do
      let st = roundOf cfg emptySave [touch 0, enemyAt 1 (0, 1.1) "dog", enemyAt 2 (-1.1, 0) "bat"]
      st.lives @?= 2
      -- and the re-Hit when Grace ends takes one more, not three
      let sts = advanceBy cfg 0.25 2 st
      map (.lives) sts @?= [2, 1]

  , "the Focused Enemy that touches can still be typed and Killed (and the Grace goes on)" ~: do
      let st = typeKeys cfg "cat" (roundOf cfg emptySave [touch 0])
      st.kills @?= 1
      st.enemies @?= []
      st.lives @?= 2
      graceActive st @?= True
  ]

graceRows :: Test
graceRows = TestLabel "grace" $ TestList
  [ "no second Hit during Grace, however many Enemies arrive" ~: do
      let sts = advanceBy cfg 0.125 3 (roundOf cfg emptySave [touch 0])
      map (.lives) sts @?= [2, 2, 2]
      map graceActive sts @?= [True, True, True]
      map graceRemaining sts @?= [Just 0.375, Just 0.25, Just 0.125]

  , "an Enemy that arrives during Grace waits: it Hits when the Grace ends" ~: do
      let st0 = roundOf cfg emptySave [touch 0]
          st1 = step cfg testWords (Tick 100.25) st0 { enemies = st0.enemies <> [enemyAt 1 (0, 1.1) "dog"] }
      st1.lives @?= 2
      (step cfg testWords (Tick 100.5) st1).lives @?= 1

  , "the Grace ends and a still-touching Enemy Hits at once, exactly when it ends" ~: do
      let sts = advanceBy cfg 0.25 2 (roundOf cfg emptySave [touch 0])
      map (.lives) sts @?= [2, 1]
      map (.graceStart) sts @?= [Just 0, Just 0.5]
      map graceActive sts @?= [True, True]

  , "a parked Enemy costs a Life every Grace Period (0.5 s here)" ~: do
      let c = cfg { startingLives = 6 }
          sts = advanceBy c 0.25 8 (roundOf c emptySave [touch 0])
      map (.lives) sts @?= [5, 4, 4, 3, 3, 2, 2, 1]

  , "when no Enemy touches any more, Grace ends and nothing follows" ~: do
      let st0 = roundOf cfg emptySave [touch 0]
          st1 = step cfg testWords (Tick 100.25) (typeKeys cfg "cat" st0)
          st2 = step cfg testWords (Tick 100.5) st1
      st2.lives @?= 2
      graceActive st2 @?= False
      st2.graceStart @?= Nothing
      graceRemaining st2 @?= Nothing

  , "the Grace Period setting is respected: 1 s makes the re-Hit come at 1 s" ~: do
      let c = cfg { gracePeriod = 1 }
          sts = advanceBy c 0.25 4 (roundOf c emptySave [touch 0])
      map (.lives) sts @?= [2, 2, 2, 1]

  , "the Grace clock is Round time: a long gap (clamped Tick) is not a free pass" ~: do
      let c = cfg { maxTickDt = 0.25 }
          st = step c testWords (Tick 200) (roundOf c emptySave [touch 0])
      -- dt is clamped to 0.25: Grace (0.5) still has 0.25 left
      st.lives @?= 2
      graceRemaining st @?= Just 0.25
  ]

overRows :: Test
overRows = TestLabel "over" $ TestList
  [ "the last Life lost ends the Round: Over, Lives 0, Grace cleared" ~: do
      let c = cfg { startingLives = 1 }
          st = roundOf c emptySave [touch 0]
      st.phase @?= Over
      st.lives @?= 0
      graceActive st @?= False

  , "Lives run out after startingLives Hits: 3 Lives, Over at the third Hit" ~: do
      let sts = advanceBy cfg 0.25 6 (roundOf cfg emptySave [touch 0])
      map (.phase) sts @?= [Running, Running, Running, Over, Over, Over]
      map (.lives) sts @?= [2, 1, 1, 0, 0, 0]
      -- the Hits came at Round time 0, 0.5 and 1.0

  , "Over: Enemies are discarded with no Points, Focus and Lock drop" ~: do
      let c = cfg { startingLives = 1 }
          start = (roundOf c emptySave [enemyAt 0 (8, 0) "cat", enemyAt 1 (0, 7) "dog"])
          focused = typeKeys c "d" start
          lock = typeKeys c "dx" start
      focused.focus @?= Focused 1 1
      lock.focus @?= Locked 1 1
      let over st = step c testWords (Tick 100.25) st { enemies = st.enemies <> [touch 2] }
      (over focused).phase @?= Over
      (over focused).enemies @?= []
      (over focused).focus @?= NoFocus
      (over lock).focus @?= NoFocus
      (over lock).roundPoints @?= 0
      (over lock).kills @?= 0
      (over lock).streak @?= 0

  , "Over: input, movement and spawning stop; counters are frozen" ~: do
      let c = cfg { startingLives = 1, intervalStart = 0.5, intervalEnd = 0.5 }
          over = typeKeys c "d" (roundOf c emptySave [enemyAt 0 (8, 0) "dog", touch 1])
      over.phase @?= Over
      let later = foldl' (flip (press c)) over ([Tick 101, Tick 105, Tick 150] <> map Key "cdogxyz" <> [Tab, Blur, Click, Focus])
      -- Blur, Focus and Aspect are not Round input either way
      (later { windowFocused = over.windowFocused }) @?= over
      later.enemies @?= []
      totalSpawned later @?= totalSpawned over
      (later.correctKeys, later.wrongKeys, later.roundTime) @?= (over.correctKeys, over.wrongKeys, over.roundTime)
      (wpm later, accuracy later) @?= (wpm over, accuracy over)

  , "startingLives is respected at Start (2 Lives, then Over on the second Hit)" ~: do
      let c = cfg { startingLives = 2 }
          sts = advanceBy c 0.25 2 (roundOf c emptySave [touch 0])
      (roundOf c emptySave []).lives @?= 2
      map (.phase) sts @?= [Running, Over]

  , "the Round snapshots startingLives: a different setting later does not change a Round" ~: do
      let st = roundOf cfg emptySave [touch 0]
          later = step cfg { startingLives = 1, gracePeriod = 10 } testWords (Tick 100.5) st
      later.lives @?= 1 -- the Round's 0.5 s Grace, not the new 10 s
  ]

-- | A Round with a Typo, a Kill and a later Hit: carried in Streak 7, Total 5.
finished :: GameState
finished = step c testWords (Tick 160) withTouch
  where
    c = cfg { startingLives = 1 }
    start = step c testWords (Tick 100) ((step c testWords (Start 1 (sv 5 7)) initialState)
      { enemies = [enemyAt 0 (6, 0) "cat", enemyAt 1 (0, 9) "dog"], nextEnemyId = 2 })
    typed = typeKeys c "cat" (press c Tab (typeKeys c "dx" start))
    withTouch = typed { enemies = typed.enemies <> [touch 5] }

resultRows :: Test
resultRows = TestLabel "result" $ TestList
  [ "the Round Result: Points, Kills, Longest Streak, final Streak, Accuracy and WPM at Round end" ~: do
      finished.phase @?= Over
      -- "dx": d correct, x a Typo (Streak 7 -> 0); Tab; then "cat" is a Kill (Streak 1, 1 Point)
      -- correct 1 + 3 = 4, wrong 1, from Round time 0 to 60 s
      case finished.roundResult of
        Nothing -> assertFailure "no Round Result"
        Just r -> do
          r.resPoints @?= 1
          r.resKills @?= 1
          r.resLongestStreak @?= 1
          r.resStreak @?= 1
          r.resAccuracy @?= 80
          r.resWpm @?= 0.8 -- (4 chars / 5) over 1 minute
          r.resTotalPoints @?= 6 -- Total 5 + 1 banked

  , "the Round Result agrees with the Over state (WPM and Accuracy are frozen at Round end)" ~: do
      let r = resultOf finished
      (r.resWpm, r.resAccuracy) @?= (wpm finished, accuracy finished)
      finished.totalPoints @?= r.resTotalPoints
      finished.roundPoints @?= r.resPoints

  , "a Round with no Keystrokes: Accuracy 100, WPM 0, Points 0, Streak as carried in" ~: do
      let c = cfg { startingLives = 1 }
          st = roundOf c (sv 9 4) [touch 0]
          r = resultOf st
      (r.resPoints, r.resTotalPoints, r.resWpm, r.resAccuracy, r.resKills, r.resLongestStreak, r.resStreak) @?= (0, 9, 0, 100, 0, 0, 4)

  , "Start after Over resets the Round but carries the Streak and the banked Total Points" ~: do
      let r = resultOf finished
          saved = bankRound r (sv 5 r.resStreak)
          again = step cfg testWords (Start 2 saved) finished
      again.phase @?= Running
      (again.lives, again.graceStart, again.roundResult, again.enemies, again.roundPoints, again.kills, again.longestStreak)
        @?= (3, Nothing, Nothing, [], 0, 0, 0)
      (again.streak, again.totalPoints) @?= (1, 6)
      (again.correctKeys, again.wrongKeys, again.roundTime) @?= (0, 0, 0)
      again.focus @?= NoFocus
  ]

bankRows :: Test
bankRows = TestLabel "bank" $ TestList
  [ "roundEnded is the Running to Over transition, once" ~: do
      let running = roundOf cfg { startingLives = 1 } emptySave []
          over = step cfg { startingLives = 1 } testWords (Tick 100.5) running { enemies = [touch 0] }
      over.phase @?= Over
      fmap (.resPoints) (roundEnded running over) @?= Just 0
      roundEnded over over @?= Nothing
      roundEnded running running @?= Nothing
      roundEnded over running @?= Nothing

  , "banking adds the Round Points to the saved Total Points exactly once over a re-emitted Over state" ~: do
      let start = roundOf cfg { startingLives = 1 } (sv 100 3) [enemyAt 0 (6, 0) "cat"]
          killed = typeKeys cfg "cat" start
          withHit = killed { enemies = [touch 1] }
          over = step cfg { startingLives = 1 } testWords (Tick 101) withHit
          -- the states the network would emit: Running ... Over, then Over again and again
          emitted = [start, killed, withHit, over, step cfg testWords (Tick 102) over, press cfg (Key 'a') over, over]
          results = catMaybes (zipWith roundEnded emitted (drop 1 emitted))
          saved = foldl' (flip bankRound) (sv 100 3) results
      length results @?= 1
      saved.totalPoints @?= 100 + 1
      saved.streak @?= 3

  , "banking does not touch the Streak or Bonus" ~: do
      let r = RoundResult 4 14 0 100 0 0 9
      bankRound r Save { totalPoints = 10, streak = 9, bonus = 0 } @?= Save { totalPoints = 14, streak = 9, bonus = 0 }
  ]

blurRows :: Test
blurRows = TestLabel "blur" $ TestList
  [ "Blur pauses a Running Round; Ticks then only move the clock (nothing advances)" ~: do
      let st = roundOf cfg emptySave [enemyAt 0 (6, 0) "cat"]
          p = press cfg Blur st
          later = foldl' (flip (press cfg)) p [Tick 105, Tick 130, Tick 160]
      p.paused @?= True
      later.enemies @?= st.enemies
      (later.roundTime, later.sinceSpawn, later.lives, later.graceStart) @?= (st.roundTime, st.sinceSpawn, st.lives, st.graceStart)
      (later { lastTime = st.lastTime }) @?= p { lastTime = st.lastTime }

  , "a paused Round does not Hit and its Grace does not run out" ~: do
      let st = roundOf cfg emptySave [touch 0]
          p = press cfg Blur st
          later = press cfg (Tick 200) p
      later.lives @?= 2
      later.graceStart @?= Just 0
      (later.roundTime, graceRemaining later) @?= (0, Just 0.5)

  , "keys while paused do not count as Keystrokes and do not resume before Focus" ~: do
      let st = roundOf cfg emptySave [enemyAt 0 (6, 0) "cat"]
          p = typeKeys cfg "cxyz" (press cfg Tab (press cfg Blur st))
      p.paused @?= True
      (p.correctKeys, p.wrongKeys, p.focus) @?= (0, 0, NoFocus)
      (press cfg Click p).paused @?= True

  , "Focus alone does not resume" ~: do
      let p = press cfg Focus (press cfg Blur (roundOf cfg emptySave []))
      (p.paused, p.windowFocused) @?= (True, True)

  , "after Focus a key press resumes and is swallowed (not a Keystroke)" ~: do
      let st = roundOf cfg emptySave [enemyAt 0 (6, 0) "cat"]
          r = press cfg (Key 'c') (press cfg Focus (press cfg Blur st))
      r.paused @?= False
      (r.correctKeys, r.focus, firstKeyAt r) @?= (0, NoFocus, Nothing)
      -- the next key is typed
      (typeKeys cfg "c" r).focus @?= Focused 0 1

  , "after Focus a click resumes; so does Tab (swallowed, no Focus change)" ~: do
      let p = press cfg Focus (press cfg Blur (roundOf cfg emptySave []))
      (press cfg Click p).paused @?= False
      (press cfg Tab p).paused @?= False
      (press cfg (Key ' ') p).paused @?= False

  , "resuming has no time jump: the next Tick moves Enemies by one clamped step only" ~: do
      let c = cfg { maxTickDt = 0.25 }
          st = roundOf c emptySave [enemyAt 0 (6, 0) "cat"]
          p = press c (Tick 100.25) (press c Blur st) -- a Tick while paused: clock moves, nothing else
          r = press c (Tick 130) (press c (Tick 130) p) -- a long paused stretch
          resumed = press c (Key 'x') (press c Focus r)
          next = press c (Tick 130.125) resumed
      resumed.paused @?= False
      next.roundTime @?= 0.125
      case next.enemies of
        [e] -> e.enemyPos.vx @?= 6 - 0.125
        other -> assertFailure (show other)

  , "Blur outside a Running Round does nothing (Over keeps its Summary, no overlay)" ~: do
      let c = cfg { startingLives = 1 }
          over = roundOf c emptySave [touch 0]
      (press c Blur over).paused @?= False
      (press c Blur initialState).paused @?= False

  , "Start clears a pause" ~: do
      let p = press cfg Blur (roundOf cfg emptySave [])
      (press cfg (Start 3 emptySave) p).paused @?= False
      (press cfg (Start 3 emptySave) p).windowFocused @?= True
  ]

summaryRowsTests :: Test
summaryRowsTests = TestLabel "summary rows" $ TestList
  [ "the seven rows, in the spec's order, with the formatted values" ~: do
      let r = RoundResult { resPoints = 12, resTotalPoints = 345, resWpm = 41.26, resAccuracy = 93.333, resKills = 9, resLongestStreak = 6, resStreak = 2 }
      summaryRows r @?=
        [ ("points", "Points", "12"), ("total", "Total Points", "345"), ("wpm", "WPM", "41.3")
        , ("accuracy", "Accuracy", "93.3%"), ("kills", "Kills", "9"), ("longest", "Longest Streak", "6"), ("streak", "Streak", "2") ]

  , "fixed1 rounds to one decimal" ~: do
      map fixed1 [0, 100, 0.04, 0.06, 99.96, 12.34] @?= ["0.0", "100.0", "0.0", "0.1", "100.0", "12.3"]
  ]
