-- | The pure scene builder (spec section 6): a 'GameState' and the 'Frame'
-- become the renderer's 'Scene'. Called once per frame by the render pull.
--
-- The Camera stays on the Player (the pan comes later), at the world height
-- of the Round's settings. The world is, in draw order: the background, the
-- dot grid, the Player, then each Enemy (a square in its Tier colour) followed
-- by its Word. The overlay is empty until the HUD exists.
module Game.Scene
  ( buildScene
  , tierColour
  , hexColour
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Numeric (readHex)
import Renderer

import Game.Layout
import Game.Settings (Settings (..))
import Game.State (Enemy (..), Focus (..), GameState (..), Vec2 (..))

buildScene :: Settings -> Frame -> GameState -> Scene
buildScene cfg frame st = Scene
  { sceneCamera = Camera (v2 st.playerPos) worldH
  , sceneWorld =
      [ Square (at (v2 st.playerPos) (worldH * frame.viewport.aspect + 4) (worldH + 4)) (hexColour cfg.backgroundColour)
      , DotGrid (realToFrac dotSpacing) (realToFrac dotRadius) (hexColour cfg.dotGridColour)
      , Square (at (v2 st.playerPos) (realToFrac playerSize) (realToFrac playerSize)) (hexColour cfg.playerColour)
      ] <> concatMap (enemyNodes cfg st.focus) st.enemies
  , sceneOverlay = []
  }
  where
    worldH = realToFrac cfg.worldHeight

-- | An Enemy square in its Tier colour and its Word centred 'wordOffset'
-- below the Enemy's centre. Letters are default-coloured, except on the
-- Focused Enemy: its first k are typed-coloured and, when Locked, letter k
-- (the expected one) is Lock-coloured.
enemyNodes :: Settings -> Focus -> Enemy -> [Node]
enemyNodes cfg foc e =
  [ Square (at (v2 e.enemyPos) (realToFrac enemySize) (realToFrac enemySize)) (tierColour cfg e.enemyTier)
  , Text (Transform (V2 x (y - realToFrac wordOffset)) 0 (V2 1 1)) AnchorCentre (realToFrac wordCapHeight)
      [ (c, letterColour i) | (i, c) <- zip [0 ..] (T.unpack e.enemyWord) ]
  ]
  where
    V2 x y = v2 e.enemyPos
    letterColour :: Int -> Colour
    letterColour i = hexColour $ case foc of
      Focused i' k | i' == e.enemyId, i < k -> cfg.letterTypedColour
      Locked i' k
        | i' == e.enemyId, i < k -> cfg.letterTypedColour
        | i' == e.enemyId, i == k -> cfg.letterLockColour
      _ -> cfg.letterDefaultColour

v2 :: Vec2 -> V2
v2 p = V2 (realToFrac p.vx) (realToFrac p.vy)

at :: V2 -> Float -> Float -> Transform
at p w h = Transform p 0 (V2 w h)

-- | The settings colour of a Tier (3 to 8; others clamp to the nearest).
tierColour :: Settings -> Int -> Colour
tierColour cfg t = hexColour $ case max 3 (min 8 t) of
  3 -> cfg.tier3Colour
  4 -> cfg.tier4Colour
  5 -> cfg.tier5Colour
  6 -> cfg.tier6Colour
  7 -> cfg.tier7Colour
  _ -> cfg.tier8Colour

-- | @#rrggbb@ to opaque 'Colour'. Settings keep colours valid; anything else
-- reads as magenta so a bad value is visible.
hexColour :: Text -> Colour
hexColour t = case T.unpack t of
  ['#', a, b, c, d, e, f] | Just r <- byte a b, Just g <- byte c d, Just bl <- byte e f -> Colour r g bl 1
  _ -> Colour 1 0 1 1
  where
    byte h l = case readHex [h, l] of
      [(n :: Int, "")] -> Just (fromIntegral n / 255)
      _ -> Nothing
