-- | Hit and Streak feedback (spec section 9): the records the step creates and
-- expires and what the builder shows at chosen times. Rounds are hand-made
-- (seed 1, injected word list). Hit rounds start with a Tick at 100 (so the
-- Hit's record time is 100) and use Grace 0.5 s; meter rounds start with a
-- Tick at 10 and group size 10.
module FeedbackTests (feedbackTests) where

import Data.Maybe (isJust, isNothing)
import Renderer
import Test.HUnit hiding (Node)

import Game.Save (emptySave)
import Game.Save qualified as Sv
import Game.Scene
import Game.Settings (Settings (..))
import Game.State
import ScoringTests (scoredRound)
import StateTests (testWords, tinyCfg)
import TypingTests (enemyAt)

-- Rounds -----------------------------------------------------------------------

hitCfg :: Settings
hitCfg = tinyCfg { intervalStart = 100, intervalEnd = 100, gracePeriod = 0.5, startingLives = 3, maxTickDt = 60 }

-- | A Round with these Enemies after a first Tick at 100.
hitRound :: Settings -> [Enemy] -> GameState
hitRound c es = step c testWords (Tick 100)
  ((step c testWords (Start 1 emptySave) initialState) { enemies = es, nextEnemyId = length es })

touch :: Int -> Enemy
touch i = enemyAt i (1.1, 0) "cat"

-- | The state after Ticks at these times.
ticksAt :: Settings -> [Double] -> GameState -> GameState
ticksAt c ts st = foldl' (\s t -> step c testWords (Tick t) s) st ts

-- | One Hit at 100, then the Enemy gone (so there is no re-Hit).
oneHit :: GameState
oneHit = (hitRound hitCfg [touch 0]) { enemies = [] }

-- Meter rounds ---------------------------------------------------------------------

meterCfg :: Settings
meterCfg = tinyCfg { intervalStart = 100, intervalEnd = 100, startingLives = 100, gracePeriod = 10, maxTickDt = 60, streakGroupSize = 10 }

-- | A Round after a Tick at 10 carrying this Streak and holding these Enemies.
meterRound :: Int -> [Enemy] -> GameState
meterRound strk es = step meterCfg testWords (Tick 10) (scoredRound meterCfg emptySave { Sv.streak = strk } es)

cat, dog :: Enemy
cat = enemyAt 0 (6, 0) "cat"
dog = enemyAt 1 (0, 7) "dog"

typeKeys :: String -> GameState -> GameState
typeKeys cs st = foldl' (flip (step meterCfg testWords . Key)) st cs

tickTo :: Double -> GameState -> GameState
tickTo t = step meterCfg testWords (Tick t)

-- Queries over the built scene ---------------------------------------------------

sceneAt :: Settings -> Double -> GameState -> Scene
sceneAt c t = buildScene c (Frame (Viewport 1600 900 (16 / 9)) t)

-- | The Player's alpha at a time (the third world node).
playerAlpha :: Settings -> GameState -> Double -> Float
playerAlpha c st t = case (sceneAt c t st).sceneWorld of
  _ : _ : Square _ (Colour _ _ _ a) : _ -> a
  other -> error ("no Player: " <> show (length other))

-- | The red overlay's alpha (0 when there is no overlay node).
flash :: Settings -> GameState -> Double -> Float
flash c st t = case [ a | Square _ (Colour 1 0 0 a) <- (sceneAt c t st).sceneOverlay ] of
  [a] -> a
  [] -> 0
  _ -> error "two overlays"

-- | The meter as drawn: (fill width, fill colour, label scale, label alpha, label text).
data Meter = Meter { fillW :: Float, fillCol :: Maybe Colour, labScale :: Maybe Float, labAlpha :: Maybe Float, labText :: Maybe String }
  deriving stock (Eq, Show)

meterAt :: GameState -> Double -> Meter
meterAt st t = case (sceneAt meterCfg t st).sceneWorld of
  _ : _ : _ : Group _ kids : _ -> Meter
    { fillW = case [ w | Square (Transform _ _ (V2 w _)) _ <- drop 1 kids ] of { w : _ -> w; [] -> 0 }
    , fillCol = case [ c | Square _ c <- drop 1 kids ] of { c : _ -> Just c; [] -> Nothing }
    , labScale = case [ s | Text (Transform _ _ (V2 s _)) _ _ _ <- kids ] of { s : _ -> Just s; [] -> Nothing }
    , labAlpha = case [ a | Text _ _ _ ((_, Colour _ _ _ a) : _) <- kids ] of { a : _ -> Just a; [] -> Nothing }
    , labText = case [ map fst cs | Text _ _ _ cs <- kids ] of { s : _ -> Just s; [] -> Nothing }
    }
  _ -> error "no meter"

white :: Colour
white = Colour 1 1 1 1

assertNear :: String -> Float -> Float -> Assertion
assertNear what want got = assertBool (what <> ": want " <> show want <> ", got " <> show got) (abs (want - got) < 1e-4)

nearM :: String -> Maybe Float -> Maybe Float -> Assertion
nearM what (Just a) (Just b) = assertNear what a b
nearM what a b = assertEqual what a b

feedbackTests :: Test
feedbackTests = TestLabel "feedback" $ TestList [blinkRows, flashRows, growRows, completeRows, typoRows, backToBackRows, lifeRows]

blinkRows :: Test
blinkRows = TestLabel "blink" $ TestList
  [ "a Hit creates the record at the Tick clock" ~: do
      (hitRound hitCfg [touch 0]).hitAt @?= Just 100
      (hitRound hitCfg []).hitAt @?= Nothing

  , "the Player alternates 1.0 / 0.25 every 0.1 s for the whole Grace Period (full first)" ~: do
      let st = hitRound hitCfg [touch 0]
      graceActive st @?= True
      sequence_
        [ assertNear ("t=100+" <> show off) (if even i then 1 else 0.25) (playerAlpha hitCfg st (100 + off))
        | i <- (enumFromTo 0 4 :: [Int]), let off = 0.1 * fromIntegral i + 0.05 ]

  , "the Player is full opacity (and the blink is over) once the Grace Period ends" ~: do
      let st = ticksAt hitCfg [100.25, 100.75] oneHit
      graceActive st @?= False
      mapM_ (\t -> assertNear (show t) 1 (playerAlpha hitCfg st t)) [100.75, 100.85, 100.95, 101.5]

  , "before any Hit the Player is full opacity" ~:
      assertNear "alpha" 1 (playerAlpha hitCfg (hitRound hitCfg []) 100.15)

  , "only the Player's alpha changes (colour is the Player colour)" ~:
      case (sceneAt hitCfg 100.15 (hitRound hitCfg [touch 0])).sceneWorld of
        _ : _ : Square _ (Colour r g b _) : _ -> Colour r g b 1 @?= hexColour tinyCfg.playerColour
        _ -> assertFailure "no Player"

  , "a parked Enemy re-Hitting restarts the blink at each Grace Period" ~: do
      let st = ticksAt hitCfg [100.5] (hitRound hitCfg [touch 0])
      st.hitAt @?= Just 100.5
      assertNear "full at re-Hit" 1 (playerAlpha hitCfg st 100.52)
      assertNear "dim after 0.1" 0.25 (playerAlpha hitCfg st 100.62)
  ]

flashRows :: Test
flashRows = TestLabel "flash" $ TestList
  [ "the red overlay is 30% at the Hit, decays linearly and is gone at +0.3 s" ~: do
      let st = hitRound hitCfg [touch 0]
      assertNear "t0" 0.3 (flash hitCfg st 100)
      assertNear "+0.075" 0.225 (flash hitCfg st 100.075)
      assertNear "+0.15" 0.15 (flash hitCfg st 100.15)
      assertNear "+0.3" 0 (flash hitCfg st 100.3)
      assertNear "+0.4" 0 (flash hitCfg st 100.4)

  , "the overlay is a screen-fixed square covering the view (world height and aspect)" ~:
      case [ (p, sz) | Square (Transform p _ sz) (Colour 1 0 0 _) <- (sceneAt hitCfg 100.1 (hitRound hitCfg [touch 0])).sceneOverlay ] of
        [(V2 0 0, V2 w h)] -> assertBool ("covers: " <> show (w, h)) (h >= 20 && w >= 20 * 16 / 9)
        other -> assertFailure ("overlay: " <> show other)

  , "no overlay node outside the flash" ~: do
      length [ () | Square _ (Colour 1 0 0 _) <- (sceneAt hitCfg 100.5 oneHit).sceneOverlay ] @?= 0
      length [ () | Square _ (Colour 1 0 0 _) <- (sceneAt hitCfg 100 (hitRound hitCfg [])).sceneOverlay ] @?= 0

  , "a re-Hit restarts the overlay, also during an old flash" ~: do
      let c = hitCfg { gracePeriod = 0.25 }
          st = ticksAt c [100.25] (hitRound c [touch 0])
      st.hitAt @?= Just 100.25
      assertNear "restarts at 0.3 (the old one would be 0.05)" 0.3 (flash c st 100.25)
      assertNear "decays from there" 0.15 (flash c st 100.4)

  , "the Hit that ends the Round flashes behind the Summary; the blink is gone" ~: do
      let c = hitCfg { startingLives = 1 }
          st = hitRound c [touch 0]
      st.phase @?= Over
      st.hitAt @?= Just 100
      assertNear "flash" 0.15 (flash c st 100.15)
      assertNear "no blink" 1 (playerAlpha c st 100.15)
      let later = ticksAt c [100.2] st
      isJust later.hitAt @? "still finishing at 100.2"
      assertNear "mid" 0.1 (flash c later 100.2)
      isNothing (ticksAt c [100.2, 100.35] st).hitAt @? "expired after +0.3"

  , "the record expires once Grace and flash are over and does not come back" ~: do
      isJust oneHit.hitAt @? "present at the Hit"
      isJust (ticksAt hitCfg [100.3] oneHit).hitAt @? "Grace still running"
      isNothing (ticksAt hitCfg [100.3, 100.6] oneHit).hitAt @? "gone after the Grace Period"
      let many = ticksAt hitCfg [ 101 + 0.25 * fromIntegral i | i <- (enumFromTo 0 400 :: [Int]) ] oneHit
      isNothing many.hitAt @? "still gone after 400 Ticks"

  , "a short Grace keeps the record until the flash is over" ~: do
      let c = hitCfg { gracePeriod = 0.1 }
          st = (hitRound c [touch 0]) { enemies = [] }
      isJust (ticksAt c [100.2] st).hitAt @? "flash still running"
      isNothing (ticksAt c [100.2, 100.31] st).hitAt @? "flash over"

  , "the builder is pure: the same input gives the same Scene" ~: do
      let st = hitRound hitCfg [touch 0]
      sceneAt hitCfg 100.17 st @?= sceneAt hitCfg 100.17 st
  ]

growRows :: Test
growRows = TestLabel "grow" $ TestList
  [ "a Kill grows the fill from the old to the new fill over 0.1 s (linear)" ~: do
      let st = typeKeys "cat" (meterRound 3 [cat])
      st.streak @?= 4
      (fmap (.maKind) st.meterAnim, fmap (.maStart) st.meterAnim) @?= (Just MeterGrow, Just 10)
      assertNear "t0" 0.6 (fillW (meterAt st 10))
      assertNear "+0.05" 0.7 (fillW (meterAt st 10.05))
      assertNear "+0.1" 0.8 (fillW (meterAt st 10.1))
      assertNear "after" 0.8 (fillW (meterAt st 10.5))
      (meterAt st 10.05).fillCol @?= (meterAt st 11).fillCol

  , "the first Kill from an empty meter grows from no fill node" ~: do
      let st = typeKeys "cat" (meterRound 0 [cat])
      assertNear "t0" 0 (fillW (meterAt st 10))
      assertNear "+0.05" 0.1 (fillW (meterAt st 10.05))
      assertNear "+0.1" 0.2 (fillW (meterAt st 10.1))
      (meterAt st 10).labText @?= Nothing

  , "no animation, no record: the static meter" ~: do
      let st = meterRound 3 [cat]
      st.meterAnim @?= Nothing
      assertNear "fill" 0.6 (fillW (meterAt st 99))
  ]

completeRows :: Test
completeRows = TestLabel "complete" $ TestList
  [ "a group-completing Kill: full white 0.15 s, then empties over 0.25 s" ~: do
      let st = typeKeys "cat" (meterRound 9 [cat])
      (st.streak, fmap (.maKind) st.meterAnim) @?= (10, Just MeterComplete)
      st.groupCompletedAt @?= Just st.roundTime
      let m t = meterAt st t
      assertNear "t0 full" 2 (fillW (m 10))
      (m 10).fillCol @?= Just white
      assertNear "+0.1 full" 2 (fillW (m 10.1))
      (m 10.1).fillCol @?= Just white
      assertNear "+0.15 starts to empty" 2 (fillW (m 10.15))
      assertBool "coloured again" ((m 10.15).fillCol /= Just white)
      assertNear "+0.275 half" 1 (fillW (m 10.275))
      assertNear "+0.4 empty" 0 (fillW (m 10.4))
      assertNear "after" 0 (fillW (m 11))

  , "the +N label pops from 1.4x to 1x over 0.2 s, alpha 1, text +1" ~: do
      let st = typeKeys "cat" (meterRound 9 [cat])
          m t = meterAt st t
      nearM "t0" (Just 1.4) (m 10).labScale
      nearM "+0.1" (Just 1.2) (m 10.1).labScale
      nearM "+0.2" (Just 1) (m 10.2).labScale
      nearM "after" (Just 1) (m 12).labScale
      nearM "alpha" (Just 1) (m 10.05).labAlpha
      (m 10).labText @?= Just "+1"
      (m 12).labText @?= Just "+1"

  , "the label is hidden at Bonus 0 (no completing Kill, no label ever)" ~: do
      let st = typeKeys "cat" (meterRound 4 [cat])
      mapM_ (\t -> (meterAt st t).labText @?= Nothing) [10, 10.05, 10.5]

  , "the record expires on Ticks and the rest view is the final frame" ~: do
      let st = typeKeys "cat" (meterRound 9 [cat])
      isJust (tickTo 10.3 st).meterAnim @? "alive mid-animation"
      isNothing (tickTo 10.5 st).meterAnim @? "gone after"
      meterAt (tickTo 10.5 st) 10.5 @?= meterAt st 10.4
  ]

typoRows :: Test
typoRows = TestLabel "typo" $ TestList
  [ "a Typo empties the bar and fades the label over 0.2 s from the pre-Typo values; the Streak is 0 at once" ~: do
      let st = typeKeys "cx" (meterRound 15 [cat])
          m t = meterAt st t
      st.streak @?= 0
      fmap (.maKind) st.meterAnim @?= Just MeterTypo
      assertNear "t0 fill" 1 (fillW (m 10))
      assertNear "+0.1 fill" 0.5 (fillW (m 10.1))
      assertNear "+0.2 fill" 0 (fillW (m 10.2))
      nearM "t0 alpha" (Just 1) (m 10).labAlpha
      nearM "+0.1 alpha" (Just 0.5) (m 10.1).labAlpha
      (m 10.1).labText @?= Just "+1"
      nearM "scale kept" (Just 1) (m 10.1).labScale
      (m 10.2).labText @?= Nothing
      (m 11).labText @?= Nothing
      assertNear "after" 0 (fillW (m 11))
      (m 10.1).fillCol @?= Just (shotColour meterCfg 15)

  , "a Typo with nothing on show makes no record" ~: do
      (typeKeys "cx" (meterRound 0 [cat])).meterAnim @?= Nothing

  , "a Typo during Bonus 0 empties the bar only" ~: do
      let st = typeKeys "cx" (meterRound 5 [cat])
      assertNear "t0" 1 (fillW (meterAt st 10))
      assertNear "+0.1" 0.5 (fillW (meterAt st 10.1))
      (meterAt st 10).labText @?= Nothing
  ]

backToBackRows :: Test
backToBackRows = TestLabel "back to back" $ TestList
  [ "two Kills 0.05 s apart: the second grows from the fill shown, continuously" ~: do
      let st = typeKeys "dog" (tickTo 10.05 (typeKeys "cat" (meterRound 0 [cat, dog])))
      assertNear "continuous at the second Kill" 0.1 (fillW (meterAt st 10.05))
      assertNear "+0.05" 0.25 (fillW (meterAt st 10.1))
      assertNear "+0.1" 0.4 (fillW (meterAt st 10.15))
      assertNear "after" 0.4 (fillW (meterAt st 10.4))

  , "a Kill then a Typo within the window: the Typo empties from the fill shown" ~: do
      let st = typeKeys "dx" (tickTo 10.05 (typeKeys "cat" (meterRound 0 [cat, dog])))
      assertNear "continuous" 0.1 (fillW (meterAt st 10.05))
      assertNear "+0.1" 0.05 (fillW (meterAt st 10.15))
      assertNear "+0.2" 0 (fillW (meterAt st 10.25))

  , "a Typo during a completion's flash starts from full, no longer white, and fades the label from its shown scale" ~: do
      let st = typeKeys "dx" (tickTo 10.05 (typeKeys "cat" (meterRound 9 [cat, dog])))
          m t = meterAt st t
      assertNear "full at the Typo" 2 (fillW (m 10.05))
      assertBool "not white" ((m 10.05).fillCol /= Just white)
      nearM "scale as shown" (Just 1.3) (m 10.05).labScale
      nearM "alpha 1" (Just 1) (m 10.05).labAlpha
      nearM "alpha half" (Just 0.5) (m 10.15).labAlpha
      (m 10.25).labText @?= Nothing
      assertNear "empty" 0 (fillW (m 10.25))

  , "a Kill while the completed group empties grows from the shown fill" ~: do
      let st = typeKeys "dog" (tickTo 10.25 (typeKeys "cat" (meterRound 9 [cat, dog])))
          m t = meterAt st t
      st.streak @?= 11
      assertNear "shown fill at the Kill (1 - 0.1/0.25)" 1.2 (fillW (m 10.25))
      assertNear "new fill" 0.2 (fillW (m 10.35))

  , "a Kill during the pop finishes the pop at its own speed" ~: do
      let st = typeKeys "dog" (tickTo 10.1 (typeKeys "cat" (meterRound 9 [cat, dog])))
          m t = meterAt st t
      nearM "as shown" (Just 1.2) (m 10.1).labScale
      nearM "+0.05" (Just 1.1) (m 10.15).labScale
      nearM "done" (Just 1) (m 10.2).labScale
      (m 10.1).labText @?= Just "+1"
      isJust (tickTo 10.15 st).meterAnim @? "record alive while the pop finishes"
      isNothing (tickTo 10.25 st).meterAnim @? "then gone"

  , "records do not grow: many Kills and Ticks leave at most one record, and none at rest" ~: do
      let es = [ enemyAt i (6 + fromIntegral i, 0) "cat" | i <- (enumFromTo 0 29 :: [Int]) ]
          killOne (s, t) _ = (tickTo (t + 0.05) (typeKeys "cat" s), t + 0.05)
          (st, t1) = foldl' killOne (meterRound 0 es, 10) (enumFromTo 1 30 :: [Int])
      length st.killAnims <= 30 @? "kill anims are the ticket 20 records"
      st.streak @?= 30
      let rest = ticksAt meterCfg [ t1 + 1 + 0.5 * fromIntegral i | i <- (enumFromTo 0 100 :: [Int]) ] st
      rest.meterAnim @?= Nothing
      rest.killAnims @?= []
  ]

lifeRows :: Test
lifeRows = TestLabel "over and purity" $ TestList
  [ "the meter record survives Round end and finishes behind the Summary" ~: do
      let c = meterCfg { startingLives = 1 }
          r0 = step c testWords (Tick 10) (scoredRound c emptySave [cat])
          killed = foldl' (flip (step c testWords . Key)) r0 ("cat" :: String)
          over = step c testWords (Tick 10.05) killed { enemies = [touch 9] }
      over.phase @?= Over
      isJust over.meterAnim @? "kept at Round end"
      assertNear "mid" 0.1 (fillW (meterAt over 10.05))
      isNothing (step c testWords (Tick 10.3) over).meterAnim @? "expires in Over"
      (step c testWords (Tick 10.3) over).phase @?= Over

  , "the builder is pure: the same input gives the same Scene" ~: do
      let st = typeKeys "cat" (meterRound 9 [cat])
      sceneAt meterCfg 10.07 st @?= sceneAt meterCfg 10.07 st

  , "Start clears every record" ~: do
      let st = typeKeys "cat" (meterRound 9 [cat])
          fresh = step meterCfg testWords (Start 2 emptySave) st
      (fresh.meterAnim, fresh.hitAt) @?= (Nothing, Nothing)
  ]

