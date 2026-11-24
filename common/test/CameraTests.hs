-- | The Camera (spec section 9): the target rule, the Player margin, the
-- exponential easing record, the hold while Focused, the retarget on Kill,
-- Tab and Round end, and what 'buildScene' draws from it. Rounds are
-- hand-made (seed 1, injected word list); the view aspect is 2 (so the
-- default view is 40 by 20 at the default world height 20: half-width 20,
-- half-height 10, and the inset rectangle is 18 by 8 around the Camera).
module CameraTests (cameraTests) where

import Data.IntMap.Strict qualified as IntMap
import Renderer
import Test.HUnit hiding (Node)

import Game.Save (emptySave)
import Game.Scene
import Game.Settings (Settings (..))
import Game.State
import ScoringTests (scoredRound)
import StateTests (testWords, tinyCfg)
import TypingTests (enemyAt)

-- | No spawns, slow Enemies (1 unit/s), long Ticks allowed, aspect 2 below.
cfg :: Settings
cfg = tinyCfg { intervalStart = 1000, intervalEnd = 1000, maxTickDt = 5, enemySpeed = 1 }

viewAsp :: Double
viewAsp = 2

-- | A Round holding these Enemies, at aspect 2, with its first Tick at 10.
roundOf :: Settings -> [Enemy] -> GameState
roundOf c es = step c testWords (Tick 10) (step c testWords (Aspect viewAsp) (scoredRound c emptySave es))

far :: Enemy
far = enemyAt 0 (30, 0) "cat"

tickTo :: Settings -> Double -> GameState -> GameState
tickTo c t = step c testWords (Tick t)

typeKeys :: Settings -> String -> GameState -> GameState
typeKeys c ks st = foldl' (flip (step c testWords . Key)) st ks

centreAt :: Double -> GameState -> Vec2
centreAt t = cameraCentreAt t . (.camera)

nearD :: Double -> Double -> Bool
nearD a b = abs (a - b) < 1e-6

assertV :: String -> (Double, Double) -> Vec2 -> Assertion
assertV what (x, y) (Vec2 a b) =
  assertBool (what <> ": want " <> show (x, y) <> ", got " <> show (a, b)) (nearD x a && nearD y b)

-- | The Camera target for an Enemy at a point, Player at the origin, aspect 2.
target :: Settings -> (Double, Double) -> Vec2
target c (x, y) = cameraTarget c viewAsp (Vec2 0 0) (Vec2 x y)

scene :: Settings -> Double -> GameState -> Scene
scene c t = buildScene c (Frame (Viewport 1800 900 (realToFrac viewAsp)) t)

firstEnemy :: GameState -> Enemy
firstEnemy st = case st.enemies of
  e : _ -> e
  [] -> error "no Enemy"

camOf :: Scene -> (Float, Float, Float)
camOf s = case s.sceneCamera of Camera (V2 x y) h -> (x, y, h)

near :: Float -> Float -> Bool
near a b = abs (a - b) < 1e-4

assertCam :: String -> (Float, Float) -> Scene -> Assertion
assertCam what (x, y) s =
  let (cx, cy, _) = camOf s
  in assertBool (what <> ": want " <> show (x, y) <> ", got " <> show (cx, cy)) (near x cx && near y cy)

cameraTests :: Test
cameraTests = TestLabel "camera" $ TestList [targetRows, marginRows, easingRows, holdRows, retargetRows, sceneRows]

targetRows :: Test
targetRows = TestLabel "target" $ TestList
  [ "an Enemy inside the default view leaves the target on the Player, even inside the inset zone" ~: do
      assertV "centre" (0, 0) (target cfg (5, 3))
      assertV "at the edge" (0, 0) (target cfg (20, 10))
      assertV "inside the view but inside the inset zone" (0, 0) (target cfg (19.5, -9.5))

  , "outside on x: the smallest shift that puts the Enemy on the inset (x 18 from the centre), both directions" ~: do
      assertV "right" (12, 0) (target cfg (30, 0))
      assertV "left" (-12, 0) (target cfg (-30, 0))

  , "outside on y: the smallest shift (y 8 from the centre), both directions" ~: do
      assertV "up" (0, 6) (target cfg (0, 14))
      assertV "down" (0, -6) (target cfg (0, -14))

  , "a corner shifts both axes independently" ~: do
      assertV "up right" (12, 6) (target cfg (30, 14))
      assertV "down left" (-12, -6) (target cfg (-30, -14))

  , "outside on one axis only: the other axis is still brought inside the inset (smallest shift)" ~: do
      assertV "x only" (7, 0) (target cfg (25, 5))
      assertV "x outside, y in the inset zone" (3, 1.5) (target cfg (21, 9.5))

  , "after the shift the Enemy is inside the inset rectangle (while the margin clamp allows)" ~:
      sequence_
        [ do let Vec2 cx cy = target cfg (x, y)
             assertBool (show (x, y)) (abs (x - cx) <= 18 + 1e-9 && abs (y - cy) <= 8 + 1e-9)
        | x <- [-34, -25, -21, 0, 21, 25, 34], y <- [-15, -12, -11, 0, 11, 12, 15] ]

  , "cameraInset is respected: 0 puts the Enemy on the edge, 6 leaves a wider border" ~: do
      assertV "inset 0" (10, 0) (target cfg { cameraInset = 0 } (30, 0))
      assertV "inset 6" (16, 0) (target cfg { cameraInset = 6 } (30, 0))

  , "worldHeight is respected: the default view follows it" ~: do
      -- height 30: half 15 by 30, inset boundary 28 from the centre in x, 13 in y
      assertV "inside the larger view" (0, 0) (target cfg { worldHeight = 30 } (30, 0))
      assertV "outside it" (12, 0) (target cfg { worldHeight = 30 } (40, 0))
  ]

-- | Every Enemy position on a grid, over several aspects and settings: the Player
-- (at the origin) stays at least the margin inside every edge of the shifted view.
marginRows :: Test
marginRows = TestLabel "margin" $ TestList
  [ "the Player stays at least playerMargin inside every edge, whatever the Enemy position, aspect and settings (a margin beyond the half-view pins the Camera)" ~:
      sequence_
        [ assertBool (show (asp, c', (x, y)) <> ": Player at " <> show (px, py) <> " from the centre")
            (abs cx <= max 0 (hw - c'.playerMargin) + 1e-9 && abs cy <= max 0 (hh - c'.playerMargin) + 1e-9)
        | asp <- [16 / 9, 2, 1, 0.75, 21 / 9]
        , c' <- [cfg, cfg { playerMargin = 8 }, cfg { playerMargin = 1, cameraInset = 0 }, cfg { worldHeight = 30, cameraInset = 6 }]
        , x <- [-80, -40, -25, -3, 0, 3, 25, 40, 80], y <- [-80, -40, -25, -3, 0, 3, 25, 40, 80]
        , let hh = c'.worldHeight / 2
              hw = hh * asp
              Vec2 cx cy = cameraTarget c' asp (Vec2 0 0) (Vec2 x y)
              (px, py) = (negate cx, negate cy) ]

  , "a far Enemy is clamped (shift 17 of 20 in x, 7 of 10 in y), so the Player sits exactly 3 from the edge" ~: do
      assertV "x" (17, 0) (target cfg (200, 0))
      assertV "y" (0, 7) (target cfg (0, 200))
      assertV "both" (-17, -7) (target cfg (-200, -200))

  , "the margin wins over the inset: with margin 8 the shift is clamped to 12 (not 12+) and the Enemy is left outside its inset" ~: do
      let Vec2 cx _ = target cfg { playerMargin = 8, cameraInset = 0 } (60, 0)
      assertBool "clamped to half - margin" (nearD 12 cx)
      assertBool "Enemy beyond the inset" (60 - cx > 20)

  , "a margin larger than the half-view leaves the Camera on the Player (nothing to clamp to)" ~:
      assertV "stays" (0, 0) (target cfg { worldHeight = 8, playerMargin = 8 } (50, 50))

  , "a non-16:9 aspect uses its own width: aspect 1 shifts x by half-height-based amounts" ~:
      let Vec2 cx cy = cameraTarget cfg 1 (Vec2 0 0) (Vec2 30 0)
      in assertBool (show (cx, cy)) (nearD 7 cx && nearD 0 cy) -- clamp 10 - 3 = 7, shift would be 22
  ]

easingRows :: Test
easingRows = TestLabel "easing" $ TestList
  [ "exponential: at t0 the start, at t0 + tau 63.2% of the way, long after the target" ~: do
      let c = CameraAnim { caStart = 4, caFrom = Vec2 2 0, caTarget = Vec2 12 0, caTau = 0.25 }
      assertV "t0" (2, 0) (cameraCentreAt 4 c)
      assertV "t0 + tau" (2 + 10 * (1 - exp (-1)), 0) (cameraCentreAt 4.25 c)
      assertBool "63.2 percent" (abs (let Vec2 x _ = cameraCentreAt 4.25 c in (x - 2) / 10 - 0.6321205588) < 1e-9)
      assertV "t0 + 2 tau" (2 + 10 * (1 - exp (-2)), 0) (cameraCentreAt 4.5 c)
      assertV "converged" (12, 0) (cameraCentreAt 400 c)

  , "before the start the Camera is at the start centre (no extrapolation)" ~:
      assertV "early" (2, 0) (cameraCentreAt 1 (CameraAnim 4 (Vec2 2 0) (Vec2 12 0) 0.25))

  , "the time constant is the record's: tau 1 is 63.2% at one second" ~:
      assertV "tau 1" (10 * (1 - exp (-1)), 0) (cameraCentreAt 1 (CameraAnim 0 (Vec2 0 0) (Vec2 10 0) 1))

  , "cameraTimeConstant is read at Round start into the record" ~: do
      (roundOf cfg { cameraTimeConstant = 0.5 } []).camera.caTau @?= 0.5
      (typeKeys cfg { cameraTimeConstant = 0.5 } "c" (roundOf cfg { cameraTimeConstant = 0.5 } [far])).camera.caTau @?= 0.5

  , "Focus on an off-screen Enemy: the Scene's Camera is at the start at t0, 63.2% of the way a tau later, converged much later" ~: do
      let st = typeKeys cfg "c" (roundOf cfg [far]) -- target (12, 0) from (0, 0), record start 10
      assertCam "t0" (0, 0) (scene cfg 10 st)
      assertCam "t0 + tau" (realToFrac (12 * (1 - exp (-1) :: Double)), 0) (scene cfg 10.25 st)
      assertCam "t0 + 10 tau" (realToFrac (12 * (1 - exp (-10) :: Double)), 0) (scene cfg 12.5 st)
      assertCam "converged" (12, 0) (scene cfg 100 st)

  , "the time constant setting changes the pan speed" ~: do
      let c2 = cfg { cameraTimeConstant = 1 }
          st = typeKeys c2 "c" (roundOf c2 [far])
      assertCam "one second at tau 1" (realToFrac (12 * (1 - exp (-1) :: Double)), 0) (scene c2 11 st)
  ]

holdRows :: Test
holdRows = TestLabel "hold" $ TestList
  [ "Focus on an in-view Enemy: no pan and no new record" ~: do
      let st = typeKeys cfg "c" (roundOf cfg [enemyAt 0 (12, 5) "cat"])
      st.camera @?= (roundOf cfg [enemyAt 0 (12, 5) "cat"]).camera
      assertCam "stays" (0, 0) (scene cfg 50 st)

  , "Focus on an off-screen Enemy creates one record, at the last Tick's time, from the Player, to the target" ~: do
      let st = typeKeys cfg "c" (roundOf cfg [far])
      st.camera @?= CameraAnim { caStart = 10, caFrom = Vec2 0 0, caTarget = Vec2 12 0, caTau = 0.25 }

  , "while Focused the record is untouched: more letters, a Typo (Lock), Ticks and a moving Enemy do not change it" ~: do
      let st0 = typeKeys cfg "c" (roundOf cfg [far])
          later = tickTo cfg 12 (typeKeys cfg "x" (tickTo cfg 11 (typeKeys cfg "a" (tickTo cfg 10.5 st0)))) -- 'a' correct, 'x' a Typo
      later.focus @?= Locked 0 2
      assertBool "the Enemy moved" ((firstEnemy later).enemyPos /= far.enemyPos)
      later.camera @?= st0.camera
      assertCam "still heading for the first target" (realToFrac (12 * (1 - exp (-(12 - 10) / 0.25) :: Double)), 0) (scene cfg 12 later)

  , "the Enemy keeps moving toward the Player but stays on screen with the held Camera" ~: do
      let st = tickTo cfg 14 (typeKeys cfg "c" (roundOf cfg [far])) -- 4 s later: Enemy at 26, Camera at ~12
          Vec2 ex _ = (firstEnemy st).enemyPos
          Vec2 cx _ = centreAt 14 st
      assertBool "closer to the Player" (ex < 30)
      assertBool "inside the visible rectangle" (abs (ex - cx) < 20)

  , "the record is created only when the target changes: a whole Round of Ticks adds none" ~: do
      let ticks = foldl' (flip (tickTo cfg)) (roundOf cfg [enemyAt 0 (12, 5) "cat"]) [10.1, 10.2 .. 20]
      ticks.camera @?= (roundOf cfg [enemyAt 0 (12, 5) "cat"]).camera
  ]

retargetRows :: Test
retargetRows = TestLabel "retarget" $ TestList
  [ "a Kill eases back: new record from the centre evaluated at the Kill time (no jump), target the Player" ~: do
      let st = tickTo cfg 10.25 (typeKeys cfg "c" (roundOf cfg [far]))
          before = centreAt 10.25 st
          killed' = typeKeys cfg "at" st
      killed'.focus @?= NoFocus
      killed'.camera.caStart @?= 10.25
      killed'.camera.caTarget @?= Vec2 0 0
      assertV "no jump" (let Vec2 x y = before in (x, y)) (centreAt 10.25 killed')
      assertBool "mid-pan, away from both ends" (let Vec2 x _ = before in x > 1 && x < 11)
      -- one tau later the remaining distance is 1/e of it
      let Vec2 bx _ = before
      assertV "one tau after the Kill" (bx / exp 1, 0) (centreAt 10.5 killed')
      assertV "converged to the Player" (0, 0) (centreAt 100 killed')

  , "a Tab eases back the same way" ~: do
      let st = tickTo cfg 11 (typeKeys cfg "c" (roundOf cfg [far]))
          tabbed = step cfg testWords Tab st
          Vec2 bx _ = centreAt 11 st
      tabbed.focus @?= NoFocus
      tabbed.camera @?= CameraAnim { caStart = 11, caFrom = Vec2 bx 0, caTarget = Vec2 0 0, caTau = 0.25 }
      assertV "continuous" (bx, 0) (centreAt 11 tabbed)
      assertV "one tau later" (bx / exp 1, 0) (centreAt 11.25 tabbed)

  , "a Tab with nothing Focused changes nothing" ~: do
      let st = roundOf cfg [far]
      step cfg testWords Tab st @?= st

  , "a new Focus during the return retargets from the current centre (continuous)" ~: do
      let two = [far, enemyAt 1 (0, 40) "dog"]
          st = tickTo cfg 10.25 (typeKeys cfg "c" (roundOf cfg two))
          back = tickTo cfg 10.5 (step cfg testWords Tab st)
          Vec2 bx byy = centreAt 10.5 back
          again = typeKeys cfg "d" back
      again.camera.caTarget @?= Vec2 0 7 -- clamped: shift 32 of 7
      assertV "continuous" (bx, byy) (centreAt 10.5 again)
      assertBool "now heading up" (let Vec2 _ y = centreAt 10.75 again in y > 0)

  , "Round end drops Focus and eases back: the new record starts at the Over Tick, from the current centre" ~: do
      let c = cfg { startingLives = 1 }
          st0 = typeKeys c "c" (roundOf c [far, enemyAt 1 (1.5, 0) "dog"])
          st1 = tickTo c 10.25 st0
          over = tickTo c 10.5 st1
          Vec2 bx _ = centreAt 10.5 st1
      over.phase @?= Over
      assertBool "Focus dropped" (over.focus == NoFocus)
      over.camera.caStart @?= 10.5
      over.camera.caTarget @?= Vec2 0 0
      let Vec2 ox _ = centreAt 10.5 over
          Vec2 ex _ = cameraCentreAt 10.5 st1.camera
      assertBool "continuous across the Round end" (nearD ex ox && nearD bx ox)
      -- the Summary shows the canvas: Ticks in Over leave 'lastTime' alone but the builder's clock still eases it
      assertCam "converged behind the Summary" (0, 0) (scene c 100 (tickTo c 20 over))
      assertCam "mid-return behind the Summary" (realToFrac (ox / exp 1), 0) (scene c 10.75 over)

  , "Start resets the Camera to the Player" ~: do
      let st = step cfg testWords (Start 2 emptySave) (tickTo cfg 10.25 (typeKeys cfg "c" (roundOf cfg [far])))
      st.camera.caTarget @?= Vec2 0 0
      assertV "at rest" (0, 0) (centreAt 99 st)
  ]

sceneRows :: Test
sceneRows = TestLabel "scene" $ TestList
  [ "the Camera centre is the record evaluated at Frame.time, at the settings' world height" ~: do
      let st = typeKeys cfg "c" (roundOf cfg [far])
      camOf (scene cfg 10 st) @?= (0, 0, 20)
      camOf (scene cfg { worldHeight = 30 } 10 st) @?= (0, 0, 30)
      let (_, _, h) = camOf (scene cfg 11 st)
      h @?= 20

  , "the dot grid is a world node (the renderer anchors it to the Camera centre, so it scrolls with a pan)" ~: do
      let st = typeKeys cfg "c" (roundOf cfg [far])
          isGrid n = case n of DotGrid {} -> True; _ -> False
      assertBool "in the world" (any isGrid (scene cfg 12 st).sceneWorld)
      assertBool "not in the overlay" (not (any isGrid (scene cfg 12 st).sceneOverlay))

  , "the background follows the Camera, the Player stays in the world at its position" ~: do
      let st = typeKeys cfg "c" (roundOf cfg [far])
          s = scene cfg 100 st
      case s.sceneWorld of
        Square (Transform p _ _) _ : _ : Square (Transform pp _ _) _ : _ -> do
          p @?= V2 12 0
          pp @?= V2 0 0
        other -> assertFailure ("unexpected world: " <> show (take 3 other))

  , "the overlay (HUD) is the same whatever the Camera does" ~: do
      let st = typeKeys cfg "c" (roundOf cfg [far])
      (scene cfg 10 st).sceneOverlay @?= (scene cfg 100 st).sceneOverlay

  , "world nodes stay at world coordinates: the Enemy's square does not move with the Camera" ~: do
      let st = typeKeys cfg "c" (roundOf cfg [far])
          enemySquare s = [ p | Square (Transform p _ _) _ <- s.sceneWorld, p == V2 30 0 ]
      enemySquare (scene cfg 10 st) @?= [V2 30 0]
      enemySquare (scene cfg 100 st) @?= [V2 30 0]

  , "the spawn ring stays Player-relative with the Camera panned away" ~: do
      let c = cfg { intervalStart = 0.2, intervalEnd = 0.2, enemySpeed = 0, maxTickDt = 0.1 }
          panned = typeKeys c "c" (roundOf c [far])
          plain = roundOf c [far]
          run st = foldl' (flip (tickTo c)) st [10.1, 10.2 .. 14]
          a = run panned
          b = run plain
          spawned st = drop 1 st.enemies
      assertBool "spawned some" (length (spawned a) >= 5)
      assertBool "the Camera is away from the Player" (let Vec2 x _ = centreAt 14 a in x > 10)
      -- on the ring around the Player, never around the Camera
      sequence_ [ assertBool "on the ring" (abs (distanceToPlayer a e - spawnRingRadius c viewAsp) < 1e-9) | e <- spawned a ]
      -- and identical to the game that never Focused: the Camera does not touch the generator
      map (.enemyPos) (spawned a) @?= map (.enemyPos) (spawned b)
      IntMap.toList a.spawnCounts @?= IntMap.toList b.spawnCounts

  , "determinism: the same inputs give the same state and Scene" ~: do
      let go = tickTo cfg 11 . typeKeys cfg "c" . roundOf cfg
      go [far] @?= go [far]
      (scene cfg 10.3 (go [far])).sceneCamera @?= (scene cfg 10.3 (go [far])).sceneCamera
  ]
