module StateTests (stateTests, testWords, runTicks, tinyCfg) where

import Data.IntMap.Strict qualified as IntMap
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as T
import Test.HUnit

import Game.Layout (contactDistance)
import Game.Settings (Settings (..), defaultSettings)
import Game.State
import Game.Words (Words, mkWords)

-- | Words of length n from the given letters (every combination, in order).
combos :: Int -> [Char] -> [Text]
combos n letters = map T.pack (sequence (replicate n letters))

-- | A tiny injected list: 64 three-letter Words (first letters a to d), 64
-- four-letter Words, and 8 five-letter Words.
testWords :: Words
testWords = mkWords (combos 3 "abcd" <> take 64 (combos 4 "efgh") <> take 8 (combos 5 "ijklmnop"))

-- | Quick rules: 10 Enemies per Tier, intervals 2 s down to 1 s, Tiers 3 to 4.
tinyCfg :: Settings
tinyCfg = defaultSettings
  { enemiesPerTier = 10, firstTier = 3, lastTier = 4
  , intervalStart = 2, intervalEnd = 1, enemySpeed = 1, wordLookahead = 0 }

-- | Start with a seed, then Ticks every dt seconds from t = 100 for n steps
-- (the first Tick has dt 0).
runTicks :: Settings -> Words -> Seed -> Double -> Int -> GameState
runTicks cfg ws seed dt n = last (trace cfg ws seed dt n)

-- | The state after Start and after each Tick.
trace :: Settings -> Words -> Seed -> Double -> Int -> [GameState]
trace cfg ws seed dt n = scanl (flip (step cfg ws)) (step cfg ws (Start seed) initialState)
  (ticksOf (\i -> 100 + dt * i) n)

-- | Ticks at times given by a function of the index, for indices 0 to n.
ticksOf :: (Double -> Double) -> Int -> [Input]
ticksOf f n = map (Tick . f . fromIntegral) (enumFromTo 0 n)

-- | Tick indices at which the total spawned went up.
spawnTimes :: [GameState] -> [Int]
spawnTimes sts = [ i | (i, (a, b)) <- zip [0 ..] (zip sts (drop 1 sts)), totalSpawned b > totalSpawned a ]

-- | The first state that has an Enemy.
firstWithEnemy :: [GameState] -> GameState
firstWithEnemy sts = case [ s | s <- sts, not (null s.enemies) ] of
  s : _ -> s
  [] -> error "no Enemy ever spawned"

near :: Double -> Double -> Double -> Bool
near eps a b = abs (a - b) <= eps

assertNear :: String -> Double -> Double -> Double -> Assertion
assertNear msg eps expected actual =
  assertBool (msg <> ": expected " <> show expected <> " got " <> show actual) (near eps expected actual)

stateTests :: Test
stateTests = TestLabel "state" $ TestList
  [ startTests, tickTests, rampTests, tierTests, movementTests, wordTests, determinismTests ]

startTests :: Test
startTests = TestLabel "start" $ TestList
  [ "before Start the state is Idle and Ticks do nothing" ~: do
      initialState.phase @?= Idle
      step tinyCfg testWords (Tick 5) initialState @?= initialState

  , "Start runs the Round: first Tier, empty field, counters 0, Player at the origin" ~: do
      let st = step tinyCfg { firstTier = 5, lastTier = 5 } testWords (Start 42) initialState
      st.phase @?= Running
      st.currentTier @?= 5
      st.enemies @?= []
      totalSpawned st @?= 0
      st.playerPos @?= Vec2 0 0
      st.lastTime @?= Nothing

  , "Start snapshots the Settings: later Settings arguments do not change the Round" ~: do
      let cfgA = tinyCfg { enemySpeed = 4 }
          cfgB = tinyCfg { enemySpeed = 0.2, maxTickDt = 0.5 }
          st0 = step cfgA testWords (Start 1) initialState
          st1 = foldl' (flip (step cfgB testWords)) st0 [Tick 0, Tick 0.1]
      st1.roundSettings @?= cfgA
      st1.roundSettings.enemySpeed @?= 4

  , "Start resets a Round in progress and keeps the view aspect" ~: do
      let mid = step tinyCfg testWords (Aspect 2) (runTicks tinyCfg testWords 1 0.05 400)
      assertBool "had Enemies" (not (null mid.enemies))
      let again = step tinyCfg { firstTier = 4, lastTier = 4 } testWords (Start 2) mid
      again.enemies @?= []
      again.spawnCounts @?= IntMap.empty
      again.currentTier @?= 4
      again.nextEnemyId @?= 0
      again.sinceSpawn @?= 0
      again.lastTime @?= Nothing
      again.viewAspect @?= 2

  , "Key and Tab are accepted and ignored" ~: do
      let st = runTicks tinyCfg testWords 1 0.05 100
      step tinyCfg testWords (Key 'a') st @?= st
      step tinyCfg testWords Tab st @?= st

  , "a bad aspect is ignored" ~: do
      let st = step tinyCfg testWords (Start 1) initialState
      (step tinyCfg testWords (Aspect 0) st).viewAspect @?= st.viewAspect
      (step tinyCfg testWords (Aspect (-1)) st).viewAspect @?= st.viewAspect
  ]

tickTests :: Test
tickTests = TestLabel "tick" $ TestList
  [ "the first Tick after Start has dt 0" ~: do
      let st = foldl' (flip (step tinyCfg testWords)) initialState [Start 1, Tick 1000]
      st.sinceSpawn @?= 0
      st.lastTime @?= Just 1000

  , "dt is clamped to maxTickDt" ~: do
      let st = foldl' (flip (step tinyCfg testWords)) initialState [Start 1, Tick 0, Tick 50]
      assertNear "sinceSpawn" 1e-12 tinyCfg.maxTickDt st.sinceSpawn
      st.lastTime @?= Just 50

  , "a Tick that goes back in time has dt 0" ~: do
      let st = foldl' (flip (step tinyCfg testWords)) initialState [Start 1, Tick 10, Tick 5]
      st.sinceSpawn @?= 0

  , "a clamped Tick moves Enemies by speed times maxTickDt only" ~: do
      let st0 = (step tinyCfg testWords (Start 1) initialState)
            { enemies = [Enemy 0 (Vec2 20 0) "cat" 3] }
          st = foldl' (flip (step tinyCfg testWords)) st0 [Tick 0, Tick 1000]
      case st.enemies of
        [e] -> assertNear "x" 1e-9 (20 - 0.1) e.enemyPos.vx
        _ -> assertFailure "one Enemy"
  ]

-- | Gaps (in ticks of 0.01 s) between spawns, per Enemy index.
rampTests :: Test
rampTests = TestLabel "ramp" $ TestList
  [ "spawn interval formula: Enemy 1, mid and last of a Tier" ~: do
      spawnInterval tinyCfg 1 @?= 2
      assertNear "mid (6 of 10)" 1e-12 (2 - 5 / 9) (spawnInterval tinyCfg 6)
      spawnInterval tinyCfg 10 @?= 1
      spawnInterval tinyCfg 11 @?= 1
      spawnInterval tinyCfg { enemiesPerTier = 10 } 5 @?= 2 - 4 / 9

  , "the Round's spawns follow the ramp (Enemy 1 after intervalStart, last after intervalEnd)" ~: do
      let dt = 0.01
          sts = trace tinyCfg { firstTier = 3, lastTier = 3 } testWords 3 dt 2000
          ts = map fromIntegral (spawnTimes sts) :: [Double]
          gaps = zipWith (-) ts (0 : ts)
          expected = [ spawnInterval tinyCfg k | k <- [1 .. 10] ]
      -- Tick 0 is the zeroth step; a spawn lands on the first tick at or after it is due.
      assertBool ("at least 10 spawns, got " <> show (length ts)) (length ts >= 10)
      sequence_ [ assertNear ("gap before Enemy " <> show k) 1.5 (e / dt) g
                | (k, e, g) <- zip3 [1 :: Int ..] expected gaps ]
  ]

tierTests :: Test
tierTests = TestLabel "tiers" $ TestList
  [ "Tier advances after enemiesPerTier spawns, not before" ~: do
      let sts = trace tinyCfg testWords 5 0.02 3000
          afterN n = [ st | st <- sts, totalSpawned st == n ]
      case (afterN 9, afterN 10, afterN 11) of
        (a : _, b : _, c : _) -> do
          a.currentTier @?= 3
          b.currentTier @?= 4
          spawnedIn b 3 @?= 10
          c.currentTier @?= 4
          spawnedIn c 4 @?= 1
          map (.enemyTier) c.enemies @?= replicate 10 3 <> [4]
          map (T.length . (.enemyWord)) c.enemies @?= replicate 10 3 <> [4]
        _ -> assertFailure "not enough spawns"

  , "the ramp restarts at each Tier" ~: do
      let sts = trace tinyCfg testWords 5 0.01 4000
          ts = map fromIntegral (spawnTimes sts) :: [Double]
          gaps = zipWith (-) ts (0 : ts)
          tier4Gaps = take 10 (drop 10 gaps)
      assertBool "20 spawns" (length gaps >= 20)
      sequence_ [ assertNear ("Tier 4 gap " <> show k) 1.5 (spawnInterval tinyCfg k / 0.01) g
                | (k, g) <- zip [1 ..] tier4Gaps ]

  , "the last Tier is endless and holds at intervalEnd" ~: do
      let cfg = tinyCfg { firstTier = 3, lastTier = 3 }
          sts = trace cfg testWords 6 0.01 4000
          ts = map fromIntegral (spawnTimes sts) :: [Double]
          gaps = zipWith (-) ts (0 : ts)
          lateGaps = take 10 (drop 10 gaps)
      assertBool "20+ spawns" (length gaps >= 20)
      mapM_ (assertNear "late gap = intervalEnd" 1.5 (1 / 0.01)) lateGaps
      let final = last sts
      final.currentTier @?= 3
      assertBool "more than enemiesPerTier spawned in the last Tier" (spawnedIn final 3 > 10)

  , "firstTier from the Settings is where the Round starts" ~: do
      let st = runTicks tinyCfg { firstTier = 4, lastTier = 4 } testWords 1 0.05 400
      assertBool "spawned" (not (null st.enemies))
      map (.enemyTier) st.enemies @?= map (const 4) st.enemies
  ]

movementTests :: Test
movementTests = TestLabel "movement" $ TestList
  [ "an Enemy appears on the ring: half-diagonal of the default view plus spawnRadius" ~: do
      let ring = sqrt ((20 * 16 / 9) ^ (2 :: Int) + 20 ^ (2 :: Int)) / 2 + 1
          at = firstWithEnemy (trace tinyCfg testWords 1 0.01 400)
      assertNear "ring formula" 1e-9 ring (spawnRingRadius tinyCfg (16 / 9))
      case at.enemies of
        [e] -> assertNear "distance at spawn" 1e-9 ring (distanceToPlayer at e)
        _ -> assertFailure "one Enemy at the first spawn"

  , "the ring follows the aspect, the world height and spawnRadius" ~: do
      let cfg = tinyCfg { spawnRadius = 3, worldHeight = 10 }
          st0 = step cfg testWords (Aspect 2) (step cfg testWords (Start 1) initialState)
          at = firstWithEnemy (scanl (flip (step cfg testWords)) st0 (ticksOf (\i -> i * 0.1) 40))
      case at.enemies of
        [e] -> assertNear "radius" 1e-9 (sqrt (20 ^ (2 :: Int) + 10 ^ (2 :: Int)) / 2 + 3) (distanceToPlayer at e)
        _ -> assertFailure "one Enemy at the first spawn"

  , "the ring is centred on the Player, not the origin" ~: do
      let st0 = (step tinyCfg testWords (Start 1) initialState) { playerPos = Vec2 5 (-3) }
          at = firstWithEnemy (scanl (flip (step tinyCfg testWords)) st0 (ticksOf (\i -> i * 0.1) 40))
      case at.enemies of
        [e] -> do
          assertNear "distance from the Player" 1e-9 (spawnRingRadius tinyCfg (16 / 9)) (distanceToPlayer at e)
          assertBool "and not from the origin" (abs (sqrt (e.enemyPos.vx ^ (2 :: Int) + e.enemyPos.vy ^ (2 :: Int)) - spawnRingRadius tinyCfg (16 / 9)) > 0.1)
        _ -> assertFailure "one Enemy at the first spawn"

  , "spawn angles vary" ~: do
      let st = runTicks tinyCfg { firstTier = 3, lastTier = 3 } testWords 1 0.05 1000
          angles = [ atan2 e.enemyPos.vy e.enemyPos.vx | e <- st.enemies ]
      assertBool "ten Enemies or more" (length angles >= 10)
      assertBool "not all the same angle" (length (nub (map (\a -> round (a * 100) :: Int) angles)) > 5)
      assertBool "both signs of x and y appear" (any (\e -> e.enemyPos.vx > 0) st.enemies && any (\e -> e.enemyPos.vx < 0) st.enemies
        && any (\e -> e.enemyPos.vy > 0) st.enemies && any (\e -> e.enemyPos.vy < 0) st.enemies)

  , "an Enemy moves toward the Player at enemySpeed units per second, along its ray" ~: do
      let st0 = (step tinyCfg { intervalStart = 10, intervalEnd = 10 } testWords (Start 1) initialState)
            { enemies = [Enemy 0 (Vec2 6 8) "cat" 3] }
          st = foldl' (flip (step tinyCfg testWords)) st0 (ticksOf (\i -> i * 0.1) 20)
      case st.enemies of
        [e] -> do
          assertNear "distance after 2 s at speed 1" 1e-9 8 (distanceToPlayer st e)
          assertNear "same ray (x/y)" 1e-9 (6 / 8) (e.enemyPos.vx / e.enemyPos.vy)
        _ -> assertFailure "one Enemy"

  , "an Enemy stops at contact distance and parks; the Player does not move" ~: do
      let cfg = tinyCfg { intervalStart = 10, intervalEnd = 10, enemySpeed = 5 }
          st0 = (step cfg testWords (Start 1) initialState) { enemies = [Enemy 0 (Vec2 6 8) "cat" 3] }
          ticks n = foldl' (flip (step cfg testWords)) st0 (ticksOf (\i -> i * 0.1) n)
          parked = ticks 40
          later = ticks 80
      assertNear "contact distance is 0.6 + 0.5" 1e-12 1.1 contactDistance
      case (parked.enemies, later.enemies) of
        ([e], [l]) -> do
          assertNear "contact distance" 1e-9 contactDistance (distanceToPlayer parked e)
          assertNear "x unchanged" 1e-9 e.enemyPos.vx l.enemyPos.vx
          assertNear "y unchanged" 1e-9 e.enemyPos.vy l.enemyPos.vy
        _ -> assertFailure "one Enemy"
      parked.playerPos @?= Vec2 0 0
      later.playerPos @?= Vec2 0 0

  , "an Enemy does not overshoot in the Tick that reaches contact" ~: do
      let cfg = tinyCfg { intervalStart = 10, intervalEnd = 10, enemySpeed = 5, maxTickDt = 0.5 }
          st0 = (step cfg testWords (Start 1) initialState) { enemies = [Enemy 0 (Vec2 1.5 0) "cat" 3] }
          st = foldl' (flip (step cfg testWords)) st0 [Tick 0, Tick 0.5]
      case st.enemies of
        [e] -> assertNear "x" 1e-9 contactDistance e.enemyPos.vx
        _ -> assertFailure "one Enemy"
  ]

wordTests :: Test
wordTests = TestLabel "words in play" $ TestList
  [ "no two Words on screen are equal, at any point of a long Round" ~:
      sequence_ [ assertBool ("duplicate at step " <> show i) (length (nub ws') == length ws')
                | (i, st) <- zip [0 :: Int ..] (trace tinyCfg testWords 4 0.05 4000)
                , let ws' = map (.enemyWord) st.enemies ]

  , "a Word is of its Tier's length" ~: do
      let st = runTicks tinyCfg testWords 4 0.05 3000
      assertBool "Enemies" (length st.enemies > 10)
      mapM_ (\e -> T.length e.enemyWord @?= e.enemyTier) st.enemies

  , "a bucket smaller than the Enemies needed defers the spawn: never a duplicate, never a crash" ~: do
      let cfg = tinyCfg { firstTier = 5, lastTier = 5, intervalStart = 0.5, intervalEnd = 0.5 }
          sts = trace cfg testWords 3 0.05 2000
          final = last sts
      length final.enemies @?= 8 -- the 8 five-letter Words
      length (nub (map (.enemyWord) final.enemies)) @?= 8
      totalSpawned final @?= 8
      assertBool "time keeps being owed" (final.sinceSpawn > 0.5)

  , "a Tier with no Words spawns nothing and does not crash" ~: do
      let cfg = tinyCfg { firstTier = 7, lastTier = 7 }
          final = runTicks cfg testWords 3 0.05 600
      final.enemies @?= []
      final.phase @?= Running

  , "a Word freed from the screen is drawn again after the bag reshuffles" ~: do
      -- all 8 Words used; remove one Enemy; the next spawn must be that Word
      let cfg = tinyCfg { firstTier = 5, lastTier = 5, intervalStart = 0.5, intervalEnd = 0.5 }
          full = runTicks cfg testWords 3 0.05 2000
          freed = case full.enemies of
            e : rest -> (e.enemyWord, full { enemies = rest })
            [] -> error "no Enemies"
          (gone, st1) = freed
          st2 = foldl' (flip (step cfg testWords)) st1 (ticksOf (\i -> 1000 + i * 0.05) 60)
      assertBool "respawned the freed Word" (gone `elem` map (.enemyWord) st2.enemies)

  , "first letters on screen are distinct when the lookahead allows it" ~: do
      let letters = "abcdefgh"
          ws = mkWords (concat [ [ T.pack (c : s) | s <- ["aa", "bb", "cc", "dd", "ee", "ff", "gg", "hh"] ] | c <- letters ])
          cfg = tinyCfg { firstTier = 3, lastTier = 3, enemiesPerTier = 200, intervalStart = 0.5, intervalEnd = 0.5, wordLookahead = 50 }
          st = runTicks cfg ws 11 0.05 84
          firsts = map (T.take 1 . (.enemyWord)) st.enemies
      length firsts @?= 8
      length (nub firsts) @?= 8

  , "with wordLookahead 0 (off) the same Round repeats first letters" ~: do
      let letters = "abcdefgh"
          ws = mkWords (concat [ [ T.pack (c : s) | s <- ["aa", "bb", "cc", "dd", "ee", "ff", "gg", "hh"] ] | c <- letters ])
          cfg = tinyCfg { firstTier = 3, lastTier = 3, enemiesPerTier = 200, intervalStart = 0.5, intervalEnd = 0.5, wordLookahead = 0 }
          st = runTicks cfg ws 11 0.05 84
          firsts = map (T.take 1 . (.enemyWord)) st.enemies
      length firsts @?= 8
      assertBool "some first letter repeats" (length (nub firsts) < 8)
  ]

determinismTests :: Test
determinismTests = TestLabel "determinism" $ TestList
  [ "the same seed and inputs give the same states" ~:
      trace tinyCfg testWords 77 0.05 1500 @?= trace tinyCfg testWords 77 0.05 1500

  , "another seed gives another game" ~: do
      let a = runTicks tinyCfg testWords 1 0.05 1500
          b = runTicks tinyCfg testWords 2 0.05 1500
      assertBool "different Enemies" (a.enemies /= b.enemies)
      assertBool "same count (the schedule does not depend on the seed)" (totalSpawned a == totalSpawned b)
  ]
