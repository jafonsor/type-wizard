module SceneTests (sceneTests) where

import Data.Text qualified as T
import Renderer
import Test.HUnit hiding (Node)

import Game.Save (Save (Save), emptySave)
import Game.Save qualified as Sv
import Game.Scene
import Game.Settings (Settings (..), defaultSettings)
import Game.State
import ScoringTests (scoredRound)
import StateTests (runTicks, testWords, tinyCfg)
import TypingTests (enemyAt, keys, roundWith)

frame :: Frame
frame = Frame (Viewport 1600 900 (16 / 9)) 12.5

-- | A Round long enough to have Enemies of Tier 3 and 4.
stateWithBothTiers :: GameState
stateWithBothTiers = runTicks tinyCfg testWords 5 0.05 700

sceneOf :: Settings -> GameState -> Scene
sceneOf cfg = buildScene cfg frame

-- Query helpers ---------------------------------------------------------------

-- | The Enemy part of the world: after the background, the dot grid, the
-- Player and the meter group, each Enemy is a Square then a Text.
enemyPairs :: Scene -> [(Node, Node)]
enemyPairs sc = pairs (drop 4 sc.sceneWorld)
  where
    pairs (a : b : rest) = (a, b) : pairs rest
    pairs _ = []

squareAt :: Node -> Maybe (V2, V2, Colour)
squareAt (Square (Transform p _ sz) c) = Just (p, sz, c)
squareAt _ = Nothing

textOf :: Node -> Maybe (V2, Anchor, Float, String, [Colour])
textOf (Text (Transform p _ _) a h cs) = Just (p, a, h, map fst cs, map snd cs)
textOf _ = Nothing

sceneTests :: Test
sceneTests = TestLabel "scene" $ TestList
  [ "the background is the first world node, a square in the background colour covering the view" ~:
      case sceneOf defaultSettings stateWithBothTiers of
        Scene _ (bg : _) _ -> case squareAt bg of
          Just (V2 0 0, V2 w h, c) -> do
            c @?= hexColour defaultSettings.backgroundColour
            assertBool "covers the view width" (w >= 20 * 16 / 9)
            assertBool "covers the view height" (h >= 20)
          other -> assertFailure ("not a centred square: " <> show other)
        _ -> assertFailure "no world"

  , "the dot grid comes second, with the visual spec's spacing, radius and colour" ~:
      case (sceneOf defaultSettings stateWithBothTiers).sceneWorld of
        _ : DotGrid sp r c : _ -> do
          (sp, r) @?= (2, 0.08)
          c @?= hexColour defaultSettings.dotGridColour
        other -> assertFailure ("second node is not the dot grid: " <> show (take 2 other))

  , "the Player is a 1.2 square at the centre in the Player colour, drawn third" ~:
      case (sceneOf defaultSettings stateWithBothTiers).sceneWorld of
        _ : _ : p : _ -> squareAt p @?= Just (V2 0 0, V2 1.2 1.2, hexColour "#f5f5f5")
        _ -> assertFailure "no Player"

  , "the Camera is fixed on the Player at the settings' world height" ~: do
      (sceneOf defaultSettings stateWithBothTiers).sceneCamera @?= Camera (V2 0 0) 20
      (sceneOf defaultSettings { worldHeight = 30 } stateWithBothTiers).sceneCamera @?= Camera (V2 0 0) 30

  , "there is one Square and one Text per Enemy" ~: do
      let sc = sceneOf defaultSettings stateWithBothTiers
      length (enemyPairs sc) @?= length stateWithBothTiers.enemies
      length sc.sceneWorld @?= 4 + 2 * length stateWithBothTiers.enemies
      assertBool "Enemies of two Tiers" (length (filter ((== 4) . (.enemyTier)) stateWithBothTiers.enemies) > 0)

  , "an Enemy is a 1.0 square at its position in its Tier's colour" ~:
      sequence_
        [ do
            (p, sz, c) <- maybe (assertFailure "not a square" >> undefined) pure (squareAt sq)
            p @?= V2 (realToFrac e.enemyPos.vx) (realToFrac e.enemyPos.vy)
            sz @?= V2 1 1
            c @?= hexColour (if e.enemyTier == 3 then defaultSettings.tier3Colour else defaultSettings.tier4Colour)
        | (e, (sq, _)) <- zip stateWithBothTiers.enemies (enemyPairs (sceneOf defaultSettings stateWithBothTiers)) ]

  , "the Tier colours follow the settings" ~: do
      let cfg = defaultSettings { tier3Colour = "#010203", tier4Colour = "#a0b0c0" }
          st = stateWithBothTiers { roundSettings = cfg }
          colours = [ c | (sq, _) <- enemyPairs (sceneOf cfg st), Just (_, _, c) <- [squareAt sq] ]
      assertBool "tier 3 colour present" (hexColour "#010203" `elem` colours)
      assertBool "tier 4 colour present" (hexColour "#a0b0c0" `elem` colours)
      assertBool "default colours gone" (hexColour defaultSettings.tier3Colour `notElem` colours)

  , "all six Tier colours map to their settings fields" ~: do
      let cfg = defaultSettings
      map (tierColour cfg) [3 .. 8] @?= map hexColour
        [cfg.tier3Colour, cfg.tier4Colour, cfg.tier5Colour, cfg.tier6Colour, cfg.tier7Colour, cfg.tier8Colour]
      assertBool "they differ" (length (foldr (\c acc -> if c `elem` acc then acc else c : acc) [] (map (tierColour cfg) [3 .. 8])) == 6)

  , "the Word is centred, 1.0 below the Enemy centre, 0.9 high, in the default letter colour" ~:
      sequence_
        [ case textOf tx of
            Just (V2 x y, anchor, h, str, cols) -> do
              (x, y) @?= (realToFrac e.enemyPos.vx, realToFrac e.enemyPos.vy - 1)
              anchor @?= AnchorCentre
              h @?= 0.9
              str @?= T.unpack e.enemyWord
              cols @?= replicate (length str) (hexColour defaultSettings.letterDefaultColour)
            Nothing -> assertFailure "not text"
        | (e, (_, tx)) <- zip stateWithBothTiers.enemies (enemyPairs (sceneOf defaultSettings stateWithBothTiers)) ]

  , "Enemies are drawn after the Player (on top of it) and in spawn order" ~:
      map (\e -> T.unpack e.enemyWord) stateWithBothTiers.enemies
        @?= [ s | (_, tx) <- enemyPairs (sceneOf defaultSettings stateWithBothTiers), Just (_, _, _, s, _) <- [textOf tx] ]

  , "an empty field draws only the background, grid, Player and the meter group" ~:
      length (sceneOf defaultSettings (runTicks tinyCfg testWords 5 0.05 5)).sceneWorld @?= 4

  , "the scene is a fresh value for each frame (same state, any frame)" ~:
      buildScene defaultSettings frame stateWithBothTiers
        @?= buildScene defaultSettings frame { time = 99 } stateWithBothTiers

  , "letters: the first k of the Focused Word are typed-coloured, the rest default" ~:
      assertEqual "colours" [typed, typed, deflt, deflt] (focusColours (keys "ca" fourLetters) 0)

  , "letters: when Locked the expected letter is Lock-coloured, earlier ones typed, later default" ~:
      assertEqual "colours" [typed, typed, lock, deflt] (focusColours (keys "cax" fourLetters) 0)

  , "letters: a Locked Word at k = 1 shows letter 2 in the Lock colour" ~:
      assertEqual "colours" [typed, lock, deflt, deflt] (focusColours (keys "cx" fourLetters) 0)

  , "letters: only the Focused Enemy shows typed or Lock colours; others stay default" ~:
      assertEqual "colours" [deflt, deflt, deflt, deflt] (focusColours (keys "cax" fourLetters) 1)

  , "letters: with no Focus every letter is default; after Tab they return to default" ~: do
      assertEqual "idle" [deflt, deflt, deflt, deflt] (focusColours fourLetters 0)
      assertEqual "tab" [deflt, deflt, deflt, deflt] (focusColours (step tinyCfg testWords Tab (keys "cax" fourLetters)) 0)

  , "letters: the three colours come from the settings and differ" ~: do
      let cfg = defaultSettings { letterDefaultColour = "#010101", letterTypedColour = "#020202", letterLockColour = "#030303" }
          st = (keys "cax" fourLetters) { roundSettings = cfg }
          cols = case drop 4 (sceneOf cfg st).sceneWorld of
            _ : t : _ | Just (_, _, _, _, cs) <- textOf t -> cs
            _ -> []
      cols @?= map hexColour ["#020202", "#020202", "#030303", "#010101"]
      assertBool "the defaults differ" (deflt /= typed && typed /= lock && deflt /= lock)

  , "a Killed Enemy is no longer drawn" ~: do
      let st = keys "cats" fourLetters
      length (enemyPairs (sceneOf defaultSettings st)) @?= 1

  , "the meter group follows the Player: a dim 2 x 0.25 track 1.6 above its centre" ~:
      case meterOf (scoredRound tinyCfg emptySave []) of
        Just (Group (Transform p _ _) (track : _)) -> do
          p @?= V2 0 0
          squareAt track @?= Just (V2 0 1.6, V2 2 0.25, hexColour "#2a3140")
        other -> assertFailure ("no meter group: " <> show other)

  , "Streak 0: no fill node, and no \"+N\" label" ~: do
      meterFillWidth (scoredRound tinyCfg emptySave []) @?= 0
      meterLabel (scoredRound tinyCfg emptySave []) @?= Nothing

  , "the fill is (Streak mod group) / group of the 2-wide track, growing from its left end" ~: do
      meterFillSquare (scoredRound tinyCfg (carried 4) []) @?= Just (V2 (-0.6) 1.6, V2 0.8 0.25)
      meterFillWidth (scoredRound tinyCfg (carried 5) []) @?= 1
      meterFillWidth (scoredRound tinyCfg (carried 29) []) @?= 1.8

  , "the fill follows the group size setting" ~: do
      let cfg = tinyCfg { streakGroupSize = 4 }
      meterFillWidth (scoredRound cfg (carried 3) []) @?= 1.5
      meterFillWidth (scoredRound cfg (carried 4) []) @?= 0

  , "the fill is in the Shot colour of the Streak" ~: do
      meterFillColour (scoredRound tinyCfg (carried 5) []) @?= Just (hexColour "#4aa3ff")
      meterFillColour (scoredRound tinyCfg (carried 55) []) @?= Just (shotColour defaultSettings 55)
      meterFillColour (scoredRound tinyCfg (carried 55) []) /= meterFillColour (scoredRound tinyCfg (carried 5) []) @? "the colour moves along the ramp"

  , "the \"+N\" label is hidden at Bonus 0 and shown from Bonus 1, right of the bar" ~: do
      meterLabel (scoredRound tinyCfg (carried 9) []) @?= Nothing
      case meterLabel (scoredRound tinyCfg (carried 10) []) of
        Just (V2 x y, anchor, str) -> do
          assertBool "right of the bar" (x >= 1)
          y @?= 1.6
          anchor @?= AnchorLeft
          str @?= "+1"
        Nothing -> assertFailure "no label at Bonus 1"
      fmap (\(_, _, str) -> str) (meterLabel (scoredRound tinyCfg (carried 34) [])) @?= Just "+3"

  , "a Typo hides the label and empties the meter" ~: do
      let st = keys "cx" (scoredRound tinyCfg (carried 34) [enemyAt 0 (6, 0) "cat"])
      meterLabel st @?= Nothing
      meterFillWidth st @?= 0

  , "the HUD: top-right \"Points N\" and \"Total N\" lines, bottom-centre \"Streak N\"" ~: do
      let st = (scoredRound tinyCfg emptySave { Sv.totalPoints = 321, Sv.streak = 12 } []) { roundPoints = 8 }
          sc = sceneOf defaultSettings st
          hud = [ (p, a, str) | n <- sc.sceneOverlay, Just (p, a, _, str, _) <- [textOf n] ]
      map (\(_, _, str) -> str) hud @?= ["Points 8", "Total 321", "Streak 12"]
      case hud of
        [(V2 x1 y1, a1, _), (V2 x2 y2, a2, _), (V2 x3 y3, a3, _)] -> do
          (a1, a2, a3) @?= (AnchorRight, AnchorRight, AnchorCentre)
          assertBool "top-right" (x1 > 0 && y1 > 0 && x1 == x2 && y2 > 0 && y2 < y1)
          assertBool "bottom-centre" (x3 == 0 && y3 < 0)
          assertBool "inside the view" (x1 < 10 * 16 / 9 && y1 < 10 && y3 > -10)
        _ -> assertFailure "three HUD lines expected"

  , "the HUD text uses the letter default colour" ~:
      sequence_ [ cs @?= replicate (length str) (hexColour defaultSettings.letterDefaultColour)
                | n <- (sceneOf defaultSettings (scoredRound tinyCfg emptySave [])).sceneOverlay, Just (_, _, _, str, cs) <- [textOf n] ]

  , "shotColour: 11 stops from the ramp start at 0 to the ramp end at 100 and beyond" ~: do
      let c = shotColour defaultSettings
      c 0 @?= hexColour "#4aa3ff"
      c 9 @?= hexColour "#4aa3ff"
      c 100 @?= hexColour "#ff3b3b"
      c 200 @?= hexColour "#ff3b3b"
      c 100000 @?= hexColour "#ff3b3b"

  , "shotColour: the in-between stops step once per group and are linear between the colours" ~: do
      let c = shotColour defaultSettings
          Colour r0 g0 b0 _ = hexColour "#4aa3ff"
          Colour r1 g1 b1 _ = hexColour "#ff3b3b"
          mid = Colour ((r0 + r1) / 2) ((g0 + g1) / 2) ((b0 + b1) / 2) 1
      c 10 @?= shotColour defaultSettings 19
      assertBool "stops 1 and 2 differ" (c 10 /= c 20)
      assertBool "the halfway stop is the mean" (near4 (c 50) mid)
      assertEqual "11 distinct stops" 11 (length (nubOn [ c (10 * g) | g <- [0 .. 12 :: Int] ]))

  , "shotColour: the ramp spans 10 groups, so it follows the group size" ~: do
      let cfg = defaultSettings { streakGroupSize = 4 }
      shotColour cfg 40 @?= hexColour "#ff3b3b"
      shotColour cfg 39 /= hexColour "#ff3b3b" @? "39 is not yet at the end at group size 4"
      shotColour cfg 20 @?= shotColour defaultSettings 50

  , "shotColour: the ramp colours are settings" ~: do
      let cfg = defaultSettings { shotStartColour = "#000000", shotEndColour = "#ffffff" }
      shotColour cfg 0 @?= hexColour "#000000"
      shotColour cfg 100 @?= hexColour "#ffffff"

  , "hexColour reads #rrggbb and shows a bad value as magenta" ~: do
      hexColour "#ff8000" @?= Colour 1 (128 / 255) 0 1
      hexColour "nope" @?= Colour 1 0 1 1
  ]

-- Typing colours ------------------------------------------------------------

deflt, typed, lock :: Colour
deflt = hexColour "#e6e6e6"
typed = hexColour "#6fe08a"
lock = hexColour "#ff5c5c"

-- | Two Enemies (ids 0 and 1) with four-letter Words "cats" and "dust".
fourLetters :: GameState
fourLetters = roundWith [enemyAt 0 (6, 0) "cats", enemyAt 1 (0, 9) "dust"]

-- | The letter colours of the Word of Enemy number i (by spawn order).
focusColours :: GameState -> Int -> [Colour]
focusColours st i = case drop i (enemyPairs (sceneOf defaultSettings st)) of
  (_, t) : _ | Just (_, _, _, _, cs) <- textOf t -> cs
  _ -> []

-- Scoring display -------------------------------------------------------------

carried :: Int -> Save
carried n = emptySave { Sv.streak = n }

-- | The meter group: the node right after the Player.
meterOf :: GameState -> Maybe Node
meterOf st = case (sceneOf defaultSettings st).sceneWorld of
  _ : _ : _ : g@(Group {}) : _ -> Just g
  _ -> Nothing

-- | The squares and texts inside the meter group (track first).
meterKids :: GameState -> [Node]
meterKids st = case meterOf st of
  Just (Group _ kids) -> kids
  _ -> []

meterFillSquare :: GameState -> Maybe (V2, V2)
meterFillSquare st = case [ (p, sz) | n <- drop 1 (meterKids st), Just (p, sz, _) <- [squareAt n] ] of
  x : _ -> Just x
  [] -> Nothing

meterFillColour :: GameState -> Maybe Colour
meterFillColour st = case [ c | n <- drop 1 (meterKids st), Just (_, _, c) <- [squareAt n] ] of
  x : _ -> Just x
  [] -> Nothing

-- | The fill's width (0 when there is no fill node).
meterFillWidth :: GameState -> Float
meterFillWidth st = maybe 0 (\(_, V2 w _) -> w) (meterFillSquare st)

-- | The "+N" label: position, anchor, text.
meterLabel :: GameState -> Maybe (V2, Anchor, String)
meterLabel st = case [ (p, a, str) | n <- meterKids st, Just (p, a, _, str, _) <- [textOf n] ] of
  x : _ -> Just x
  [] -> Nothing

near4 :: Colour -> Colour -> Bool
near4 (Colour a b c d) (Colour a' b' c' d') = all (< (1e-5 :: Float)) [abs (a - a'), abs (b - b'), abs (c - c'), abs (d - d')]

nubOn :: Eq a => [a] -> [a]
nubOn = foldr (\x acc -> x : filter (/= x) acc) []
