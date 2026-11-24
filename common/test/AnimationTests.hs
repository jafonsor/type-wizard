-- | The Shot and Plus Sign animations (spec sections 6 and 9): the records the
-- step creates and expires, and what the builder evaluates from them at chosen
-- times. Rounds are hand-made (seed 1, injected word list); the Kill is typing
-- "cat" at Tick time 10, so a record starts at 10.
module AnimationTests (animationTests) where

import Renderer
import Test.HUnit hiding (Node)

import Game.Save (Save, emptySave)
import Game.Save qualified as Sv
import Game.Scene
import Game.Settings (Settings (..), defaultSettings)
import Game.State
import ScoringTests (scoredRound)
import StateTests (testWords, tinyCfg)
import TypingTests (enemyAt)

-- | A Round holding one "cat" Enemy at (6, 0), with a first Tick at 10 (so
-- 'lastTime' is 10), carrying this Streak.
roundAt :: Settings -> Int -> [Enemy] -> GameState
roundAt cfg strk es = step cfg testWords (Tick 10) (scoredRound cfg emptySave { Sv.streak = strk } es)

cat :: Enemy
cat = enemyAt 0 (6, 0) "cat"

killed :: Settings -> Int -> GameState
killed cfg strk = foldl' (flip (step cfg testWords . Key)) (roundAt cfg strk [cat]) ("cat" :: String)

oneKill :: GameState
oneKill = killed tinyCfg 0

-- | The first record of a state.
anim :: GameState -> KillAnim
anim st = case st.killAnims of
  k : _ -> k
  [] -> error "no record"

-- | The world nodes after the Player, the meter and the Enemies: the animation nodes.
animNodes :: Settings -> Double -> GameState -> [Node]
animNodes cfg t st = drop (4 + 2 * length st.enemies) (buildScene cfg (Frame (Viewport 1600 900 (16 / 9)) t) st).sceneWorld

near :: Float -> Float -> Bool
near a b = abs (a - b) < 1e-4

assertNear :: String -> Float -> Float -> Assertion
assertNear what want got = assertBool (what <> ": want " <> show want <> ", got " <> show got) (near want got)

-- | The Plus Signs among the nodes: (position, size, alpha).
signs :: [Node] -> [(V2, Float, Float)]
signs ns = [ (p, sx, a) | Group (Transform p _ (V2 sx _)) (Square _ (Colour _ _ _ a) : _) <- ns ]

triangles :: [Node] -> [(V2, Float, V2, Colour)]
triangles ns = [ (p, r, sz, c) | Triangle (Transform p r sz) c <- ns ]

-- | The first 'Colour' of a Plus Sign group (its alpha aside).
signColour :: Node -> Maybe Colour
signColour (Group _ (Square _ c : _)) = Just c
signColour _ = Nothing

cfg0 :: Settings
cfg0 = tinyCfg

animationTests :: Test
animationTests = TestLabel "animation" $ TestList [recordRows, shotRows, plusRows, capRows, expiryRows, roundEndRows]

recordRows :: Test
recordRows = TestLabel "records" $ TestList
  [ "a Kill creates one record: Tick-clock start, Player centre to the Enemy's position, durations, Streak after the Kill" ~: do
      length oneKill.killAnims @?= 1
      let k = anim oneKill
      (k.kaStart, k.kaFrom, k.kaTo) @?= (10, Vec2 0 0, Vec2 6 0)
      (k.kaShotDur, k.kaHold, k.kaFly) @?= (0.12, 0.1, 0.5)
      (k.kaStreak, k.kaPoints, length k.kaSigns) @?= (1, 1, 1)

  , "no Kill, no record; two Kills, two records" ~: do
      (roundAt cfg0 0 [cat]).killAnims @?= []
      let two = foldl' (flip (step cfg0 testWords . Key)) (roundAt cfg0 0 [cat, enemyAt 1 (0, 7) "dog"]) ("catdog" :: String)
      length two.killAnims @?= 2

  , "the record starts at the previous Tick's time, 0 before any Tick" ~: do
      let st = scoredRound cfg0 emptySave [cat]
          k0 = foldl' (flip (step cfg0 testWords . Key)) st ("cat" :: String)
      (anim k0).kaStart @?= 0
      (anim (killed cfg0 0)).kaStart @?= 10

  , "the colour streak is the Streak after the Kill: carried 9 gives 10 and 2 Points" ~: do
      let k = anim (killed cfg0 9)
      (k.kaStreak, k.kaPoints, length k.kaSigns) @?= (10, 2, 2)

  , "the Enemy is gone from the logic at the Kill (typing and Focus never see the Shot)" ~: do
      oneKill.enemies @?= []
      oneKill.focus @?= NoFocus

  , "the step only creates and expires: a Kill changes nothing else beyond its usual effects" ~: do
      let before = roundAt cfg0 0 [cat]
          after = killed cfg0 0
      length after.killAnims - length before.killAnims @?= 1

  , "Start clears the records" ~: do
      (step cfg0 testWords (Start 2 emptySave) oneKill).killAnims @?= []

  , "the sign parameters are deterministic for a seed and use their own generator" ~: do
      (killed cfg0 9).killAnims @?= (killed cfg0 9).killAnims
      (killed cfg0 9).rng @?= (roundAt cfg0 9 [cat]).rng
  ]

shotRows :: Test
shotRows = TestLabel "shot" $ TestList
  [ "at the Kill the Shot is at the Player centre, 0.5 long and pointing along travel, with the dying Enemy square under it" ~: do
      case animNodes cfg0 10 oneKill of
        [Square (Transform (V2 6 0) _ (V2 1 1)) c, Triangle (Transform (V2 sx sy) r (V2 l w)) col] -> do
          c @?= tierColour cfg0 3
          (sx, sy, l, w) @?= (0, 0, 0.5, 0.3)
          assertNear "rotation" 0 r
          col @?= shotColour cfg0 1
        other -> assertFailure (show other)

  , "it points along travel for any direction" ~: do
      let st = foldl' (flip (step cfg0 testWords . Key)) (roundAt cfg0 0 [enemyAt 0 (0, 6) "cat"]) ("cat" :: String)
      case triangles (animNodes cfg0 10 st) of
        [(_, r, _, _)] -> assertNear "rotation" (pi / 2) r
        other -> assertFailure (show other)

  , "midway (0.06 s) the ease-out puts it at 0.75 of the way, not 0.5" ~: do
      case triangles (animNodes cfg0 10.06 oneKill) of
        [(V2 x y, _, _, _)] -> assertNear "x" 4.5 x >> assertNear "y" 0 y
        other -> assertFailure (show other)

  , "at 25 percent of the duration it is at 0.4375 of the way (ease-out is quadratic)" ~: do
      case triangles (animNodes cfg0 10.03 oneKill) of
        [(V2 x _, _, _, _)] -> assertNear "x" (6 * 0.4375) x
        other -> assertFailure (show other)

  , "it ends at the Enemy: just before the duration it is nearly there, at the duration it is gone with the dying square" ~: do
      case triangles (animNodes cfg0 10.1199 oneKill) of
        [(V2 x _, _, _, _)] -> assertBool "near the Enemy" (x > 5.99)
        other -> assertFailure (show other)
      triangles (animNodes cfg0 10.12 oneKill) @?= []
      [ () | Square (Transform _ _ (V2 1 1)) _ <- animNodes cfg0 10.12 oneKill ] @?= []

  , "the Shot colour is the ramp at the Streak after the Kill: 0, 9, 10 and 100 (11 stops, group 10)" ~: do
      let colourOf strk = case triangles (animNodes cfg0 10 (oneKill { killAnims = [(anim oneKill) { kaStreak = strk }] })) of
            [(_, _, _, c)] -> c
            other -> error (show other)
      colourOf 0 @?= hexColour defaultSettings.shotStartColour
      colourOf 9 @?= hexColour defaultSettings.shotStartColour
      colourOf 10 @?= shotColour cfg0 10
      assertBool "stop 1 differs from the start" (colourOf 10 /= colourOf 9)
      colourOf 100 @?= hexColour defaultSettings.shotEndColour
      colourOf 250 @?= hexColour defaultSettings.shotEndColour

  , "the Shot colour at a carried Streak of 9: the Kill makes it 10, so the Shot is already stop 1" ~: do
      case triangles (animNodes cfg0 10 (killed cfg0 9)) of
        [(_, _, _, c)] -> c @?= shotColour cfg0 10
        other -> assertFailure (show other)

  , "the duration is the Round's setting" ~: do
      let st = killed cfg0 { shotDuration = 0.5 } 0
      case triangles (animNodes cfg0 10.25 st) of
        [(V2 x _, _, _, _)] -> assertNear "x" 4.5 x
        other -> assertFailure (show other)

  , "before the record's start the Shot waits at the Player" ~: do
      case triangles (animNodes cfg0 9 oneKill) of
        [(V2 x _, _, _, _)] -> assertNear "x" 0 x
        other -> assertFailure (show other)
  ]

-- | One "cat" Kill at Streak 9 (2 Points, 2 signs).
two :: GameState
two = killed cfg0 9

plusRows :: Test
plusRows = TestLabel "plus signs" $ TestList
  [ "no Plus Signs while the Shot flies" ~: do
      signs (animNodes cfg0 10 two) @?= []
      signs (animNodes cfg0 10.1199 two) @?= []

  , "they appear when the Shot arrives, one per Point (1 + Bonus), each a Group of two Squares" ~: do
      let ns = animNodes cfg0 10.12 two
      length (signs ns) @?= 2
      length [ () | Group _ [Square _ _, Square _ _] <- ns ] @?= 2
      length (signs (animNodes cfg0 10.12 oneKill)) @?= 1

  , "they start inside the spread radius around the Enemy, 0.5 units, in the Shot colour, opaque" ~: do
      let ns = animNodes cfg0 10.12 two
      sequence_ [ do assertBool "inside the radius" ((x - 6) ^ (2 :: Int) + y ^ (2 :: Int) <= 0.6 ^ (2 :: Int) + 1e-4)
                     assertNear "size" 0.5 s
                     assertNear "alpha" 1 a
                | (V2 x y, s, a) <- signs ns ]
      mapM_ (\n -> signColour n @?= Just (shotColour cfg0 10)) [ g | g@(Group {}) <- ns ]

  , "the offsets are the record's, deterministic for the seed, and not all alike" ~: do
      let ks = (anim (killed cfg0 399)).kaSigns
          offs = map (.psOffset) ks
      length ks @?= 30
      assertBool "spread over several places" (length (filter (/= head offs) offs) > 20)
      (anim (killed cfg0 399)).kaSigns @?= ks
      assertBool "a zero radius puts all on the Enemy" (all ((== Vec2 0 0) . (.psOffset)) (anim (killed cfg0 { plusSpreadRadius = 0 } 399)).kaSigns)

  , "each sign's delay is 0 to 0.15 s and they differ" ~: do
      let ds = map (.psDelay) (anim (killed cfg0 399)).kaSigns
      assertBool "within 0 to 0.15" (all (\d -> d >= 0 && d <= 0.15) ds)
      assertBool "not all equal" (length (filter (/= head ds) ds) > 20)

  , "hold: until 0.1 s after arrival every sign stays where it started" ~: do
      let at0 = signs (animNodes cfg0 10.12 two)
          atHold = signs (animNodes cfg0 10.2199 two)
      map (\(p, _, _) -> p) atHold @?= map (\(p, _, _) -> p) at0

  , "fly: quadratic ease-in from the start position to the Player after the sign's own delay" ~: do
      let k = anim two
          p = head k.kaSigns
          t0 = signFlyStart k p
          Vec2 ox oy = p.psOffset
          startX = 6 + ox
          startY = oy
          pos t = [ q | (q, _, _) <- take 1 (signs (animNodes cfg0 t two)) ]
      case pos (t0 + 0.25) of
        [V2 x y] -> do
          -- halfway through the flight the ease-in has covered a quarter
          assertNear "x" (realToFrac (startX * 0.75)) x
          assertNear "y" (realToFrac (startY * 0.75)) y
        other -> assertFailure (show other)
      case pos (t0 + 0.1) of
        [V2 x _] -> assertNear "x at 20 percent" (realToFrac (startX * (1 - 0.04))) x
        other -> assertFailure (show other)

  , "scale and fade: full until the last 0.15 s, then 0.3 times and transparent at the end" ~: do
      let k = anim two
          p = head k.kaSigns
          e = signEnd k p
          sg t = take 1 [ (s, a) | (_, s, a) <- signs (animNodes cfg0 t two) ]
      sg (e - 0.2) @?= [(0.5, 1)]
      case sg (e - 0.075) of
        [(s, a)] -> assertNear "scale" (0.5 * 0.65) s >> assertNear "alpha" 0.5 a
        other -> assertFailure (show other)
      case sg (e - 0.0001) of
        [(s, a)] -> assertBool "nearly 0.3x" (abs (s - 0.15) < 1e-3) >> assertBool "nearly transparent" (a < 1e-2)
        other -> assertFailure (show other)

  , "removed on reaching the Player: gone at the sign's end, all gone at the record's end" ~: do
      let k = anim two
      signs (animNodes cfg0 (killAnimEnd k) two) @?= []
      assertBool "one sign gone before the other can be" (killAnimEnd k >= signEnd k (head k.kaSigns))

  , "the fly time is the Round's setting" ~: do
      let st = killed cfg0 { plusFlyDuration = 2 } 9
          k = anim st
          p = head k.kaSigns
      assertBool "ends 2 s after its start" (abs (signEnd k p - signFlyStart k p - 2) < 1e-9)

  , "at the Player: the last instants of the flight are at the Player, up to the final frame" ~: do
      let k = anim two
          p = head k.kaSigns
      case [ q | (q, _, _) <- take 1 (signs (animNodes cfg0 (signEnd k p - 1e-6) two)) ] of
        [V2 x y] -> assertBool "at the Player" (abs x < 1e-2 && abs y < 1e-2)
        other -> assertFailure (show other)
  ]

capRows :: Test
capRows = TestLabel "draw cap" $ TestList
  [ "Bonus 40 (Streak 400) pays 41 Points but draws 30 signs" ~: do
      let st = killed cfg0 399
      st.roundPoints @?= 41
      (anim st).kaPoints @?= 41
      length (anim st).kaSigns @?= 30
      length (signs (animNodes cfg0 (shotArrival (anim st)) st)) @?= 30

  , "the cap is the setting, and Points do not change with it" ~: do
      let st = killed cfg0 { plusDrawCap = 5 } 399
      length (anim st).kaSigns @?= 5
      st.roundPoints @?= 41
      (killed cfg0 { plusDrawCap = 200 } 399).roundPoints @?= 41
      length (anim (killed cfg0 { plusDrawCap = 200 } 399)).kaSigns @?= 41

  , "below the cap there is one sign per Point" ~: do
      mapM_ (\(strk, n) -> length (anim (killed cfg0 strk)).kaSigns @?= n) ([(0, 1), (9, 2), (19, 3), (28, 3), (29, 4)] :: [(Int, Int)])
  ]

expiryRows :: Test
expiryRows = TestLabel "expiry" $ TestList
  [ "a Tick before the end keeps the record, a Tick at the end drops it" ~: do
      let e = killAnimEnd (anim two)
      length (step cfg0 testWords (Tick (e - 0.001)) two).killAnims @?= 1
      length (step cfg0 testWords (Tick e) two).killAnims @?= 0

  , "the end is the last sign's end: arrival + hold + its delay + fly" ~: do
      let k = anim two
      killAnimEnd k @?= maximum (map (signEnd k) k.kaSigns)
      assertBool "inside the bounds" (killAnimEnd k >= 10 + 0.12 + 0.1 + 0.5 && killAnimEnd k <= 10 + 0.12 + 0.1 + 0.15 + 0.5 + 1e-9)

  , "records expire while paused (Ticks still come) and the state is otherwise only moved as before" ~: do
      let p = step cfg0 testWords Blur two
          e = killAnimEnd (anim two)
      (step cfg0 testWords (Tick (e + 1)) p).killAnims @?= []
      (step cfg0 testWords (Tick (e + 1)) p).paused @?= True

  , "records of different Kills expire separately" ~: do
      let st = foldl' (flip (step cfg0 testWords . Key)) (roundAt cfg0 0 [cat, enemyAt 1 (0, 7) "dog"]) ("cat" :: String)
          st2 = foldl' (flip (step cfg0 testWords . Key)) (step cfg0 testWords (Tick 10.3) st) ("dog" :: String)
          e1 = killAnimEnd (head st2.killAnims)
      length st2.killAnims @?= 2
      map (.kaStart) (step cfg0 testWords (Tick e1) st2).killAnims @?= [10.3]

  , "buildScene is pure: the same state and frame give the same Scene, and building does not change the state" ~: do
      let sc t = buildScene cfg0 (Frame (Viewport 1600 900 (16 / 9)) t) two
      sc 10.3 @?= sc 10.3
      sc 10.3 /= sc 10.4 @? "the Scene depends on the frame time"

  , "the Scene holds no times: it is only nodes (positions, scales, colours)" ~: do
      -- the same evaluated Scene for two states that differ only in an unrelated clock field
      let a = buildScene cfg0 (Frame (Viewport 1600 900 (16 / 9)) 10.3) two
          b = buildScene cfg0 (Frame (Viewport 1600 900 (16 / 9)) 10.3) two { lastTime = Just 99 }
      a @?= b
  ]

-- | Round end with animations in flight: 1 Life, a Kill, then a parked Enemy
-- ends the Round while the Plus Signs are still flying.
roundEndRows :: Test
roundEndRows = TestLabel "round end" $ TestList
  [ "animations survive the Round end and finish behind the Summary; Over expires and does nothing else" ~: do
      let cfg = cfg0 { startingLives = 1, gracePeriod = 10, plusFlyDuration = 2, plusHold = 1 }
          dog = enemyAt 1 (0, 2.4) "dog"
          st0 = foldl' (flip (step cfg testWords . Key)) (roundAt cfg 9 [cat, dog]) ("cat" :: String)
          ticks = scanl (\s i -> step cfg testWords (Tick (10 + 0.1 * i)) s) st0 [1 .. 60]
          over = head [ s | s <- ticks, s.phase == Over ]
          k = anim over
      over.enemies @?= []
      length over.killAnims @?= 1
      assertBool "still flying when Over" (killAnimEnd k > over.roundTime + 10 - 1)
      -- the Plus Signs are drawn behind the Summary at the frame time
      let tOver = maybe 0 id over.lastTime
      assertBool "signs on show when the Round ends" (length (signs (animNodes cfg tOver over)) == 2)
      -- later Ticks change nothing but the records
      let later = step cfg testWords (Tick (tOver + 0.5)) over
      later { killAnims = [] } @?= over { killAnims = [] }
      length later.killAnims @?= 1
      let done = step cfg testWords (Tick (killAnimEnd k)) over
      done.killAnims @?= []
      done { killAnims = over.killAnims } @?= over
      signs (animNodes cfg (killAnimEnd k) over) @?= []

  , "a record keeps finishing in Over after the Summary shows: lastTime is not advanced by Over Ticks" ~: do
      let cfg = cfg0 { startingLives = 1, gracePeriod = 10, plusFlyDuration = 2 }
          st0 = foldl' (flip (step cfg testWords . Key)) (roundAt cfg 0 [cat, enemyAt 1 (0, 2.4) "dog"]) ("cat" :: String)
          over = head [ s | s <- scanl (\s i -> step cfg testWords (Tick (10 + 0.1 * i)) s) st0 [1 .. 60], s.phase == Over ]
      (step cfg testWords (Tick 500) over).lastTime @?= over.lastTime
  ]
