module SceneTests (sceneTests) where

import Data.Text qualified as T
import Renderer
import Test.HUnit hiding (Node)

import Game.Scene
import Game.Settings (Settings (..), defaultSettings)
import Game.State
import StateTests (runTicks, testWords, tinyCfg)

frame :: Frame
frame = Frame (Viewport 1600 900 (16 / 9)) 12.5

-- | A Round long enough to have Enemies of Tier 3 and 4.
stateWithBothTiers :: GameState
stateWithBothTiers = runTicks tinyCfg testWords 5 0.05 700

sceneOf :: Settings -> GameState -> Scene
sceneOf cfg = buildScene cfg frame

-- Query helpers ---------------------------------------------------------------

-- | The Enemy part of the world: after the background, the dot grid and the
-- Player, each Enemy is a Square then a Text.
enemyPairs :: Scene -> [(Node, Node)]
enemyPairs sc = pairs (drop 3 sc.sceneWorld)
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

  , "the overlay is empty (no HUD yet)" ~: (sceneOf defaultSettings stateWithBothTiers).sceneOverlay @?= []

  , "there is one Square and one Text per Enemy" ~: do
      let sc = sceneOf defaultSettings stateWithBothTiers
      length (enemyPairs sc) @?= length stateWithBothTiers.enemies
      length sc.sceneWorld @?= 3 + 2 * length stateWithBothTiers.enemies
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

  , "an empty field draws only the background, grid and Player" ~:
      length (sceneOf defaultSettings (runTicks tinyCfg testWords 5 0.05 5)).sceneWorld @?= 3

  , "the scene is a fresh value for each frame (same state, any frame)" ~:
      buildScene defaultSettings frame stateWithBothTiers
        @?= buildScene defaultSettings frame { time = 99 } stateWithBothTiers

  , "hexColour reads #rrggbb and shows a bad value as magenta" ~: do
      hexColour "#ff8000" @?= Colour 1 (128 / 255) 0 1
      hexColour "nope" @?= Colour 1 0 1 1
  ]
