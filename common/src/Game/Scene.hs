-- | The pure scene builder (spec section 6): a 'GameState' and the 'Frame'
-- become the renderer's 'Scene'. Called once per frame by the render pull.
--
-- The Camera stays on the Player (the pan comes later), at the world height
-- of the Round's settings. The world is, in draw order: the background, the
-- dot grid, the Player, then each Enemy (a square in its Tier colour) followed
-- by its Word.
--
-- /Player side./ Right after the Player (before the Enemies) comes one
-- 'Group' at the Player: the Streak Meter (a dim track and a fill, in the
-- 'shotColour' of the Streak, @(Streak mod group) / group@ of the track wide,
-- left-aligned; no fill node at 0) and, from Bonus 1, the "+N" label. These
-- are static: the grow, flash and pop animations belong to a later slice.
--
-- /HUD./ The overlay (screen-fixed, in world-height units): top-right
-- "Points N" (this Round) and "Total N" (Total Points) as two lines,
-- bottom-centre "Streak N". Top-left is the Lives row: one 0.4 square per
-- starting Life, white while kept and dim (the meter track's grey) once lost.
-- Bottom-left is the small "Esc: menu" hint. (The DOM Menu control is at the
-- top-centre, so nothing overlaps the Lives.) The Hit feedback animations
-- belong to a later slice.
module Game.Scene
  ( buildScene
  , shotColour
  , tierColour
  , hexColour
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Numeric (readHex)
import Renderer

import Game.Layout
import Game.Settings (Settings (..))
import Game.State
  ( Enemy (..), Focus (..), GameState (..), KillAnim (..), PlusSign (..), Vec2 (..)
  , meterFill, shotArrival, signEnd, signFlyStart, streakBonus )

buildScene :: Settings -> Frame -> GameState -> Scene
buildScene cfg frame st = Scene
  { sceneCamera = Camera (v2 st.playerPos) worldH
  , sceneWorld =
      [ Square (at (v2 st.playerPos) (worldH * frame.viewport.aspect + 4) (worldH + 4)) (hexColour cfg.backgroundColour)
      , DotGrid (realToFrac dotSpacing) (realToFrac dotRadius) (hexColour cfg.dotGridColour)
      , Square (at (v2 st.playerPos) (realToFrac playerSize) (realToFrac playerSize)) (hexColour cfg.playerColour)
      , meterNodes cfg st
      ] <> concatMap (enemyNodes cfg st.focus) st.enemies
        <> concatMap (killNodes cfg frame.time) st.killAnims
  , sceneOverlay = hudNodes cfg frame st
  }
  where
    worldH = realToFrac cfg.worldHeight

-- | The animations of one Kill at time @t@ (the frame time; the builder's
-- clock is the records' clock, see "Game.State"), in draw order: the dying
-- Enemy's square (no Word) until the Shot arrives, the Shot, then the Plus
-- Signs. Nothing before the record's own parts begin or after they end.
--
-- The Shot is a triangle 'shotLength' long (its centre travels from the
-- Player to the Enemy's position with quadratic ease-out, pointing along
-- travel) in the 'shotColour' of the Streak after the Kill. When it arrives
-- the Enemy square goes and the signs appear at the Enemy's position plus
-- their offset, hold, then fly to the Player with quadratic ease-in after
-- their own delay, shrinking to 'plusShrinkScale' and fading over the last
-- 'plusShrinkTime' of the flight, and go on reaching the Player.
killNodes :: Settings -> Double -> KillAnim -> [Node]
killNodes cfg t k = dying <> shot <> concatMap sign k.kaSigns
  where
    shotCol = shotColour cfg k.kaStreak
    arrival = shotArrival k
    from = v2 k.kaFrom
    to = v2 k.kaTo
    V2 fx fy = from
    V2 tx ty = to
    (dx, dy) = (tx - fx, ty - fy)
    dying =
      [ Square (at to (realToFrac enemySize) (realToFrac enemySize)) (tierColour cfg k.kaTier) | t < arrival ]
    shot =
      [ Triangle (Transform (lerpV from to (realToFrac (easeOut p))) (atan2 dy dx) (V2 (realToFrac shotLength) (realToFrac shotWidth))) shotCol
      | t < arrival
      , let p = clamp01 ((t - k.kaStart) / k.kaShotDur) ]
    sign p
      | t < arrival || t >= signEnd k p = []
      | otherwise = [Group (Transform pos 0 (V2 sz sz)) [bar 1 th, bar th 1]]
      where
        fly = clamp01 ((t - signFlyStart k p) / k.kaFly)
        start = v2 (Vec2 (k.kaTo.vx + p.psOffset.vx) (k.kaTo.vy + p.psOffset.vy))
        pos = lerpV start from (realToFrac (fly * fly))
        end = signEnd k p
        u = clamp01 ((t - (end - shrink)) / shrink)
        shrink = min plusShrinkTime k.kaFly
        sz = realToFrac (plusSize * (1 - (1 - plusShrinkScale) * u))
        th = realToFrac plusBarThickness
        Colour r g b _ = shotCol
        bar w h = Square (Transform (V2 0 0) 0 (V2 w h)) (Colour r g b (realToFrac (1 - u)))

easeOut :: Double -> Double
easeOut p = 1 - (1 - p) * (1 - p)

clamp01 :: Double -> Double
clamp01 = max 0 . min 1

lerpV :: V2 -> V2 -> Float -> V2
lerpV (V2 ax ay) (V2 bx bY) f = V2 (ax + (bx - ax) * f) (ay + (bY - ay) * f)

-- | The Streak Meter and the Bonus label, one 'Group' at the Player.
meterNodes :: Settings -> GameState -> Node
meterNodes cfg st = Group (at (v2 st.playerPos) 1 1) (track : fill <> label)
  where
    (mw, mh) = (realToFrac (fst meterSize), realToFrac (snd meterSize))
    y = realToFrac meterOffset
    c = shotColour cfg st.streak
    w = mw * realToFrac (meterFill st)
    track = Square (at (V2 0 y) mw mh) trackColour
    fill = [ Square (at (V2 (negate mw / 2 + w / 2) y) w mh) c | w > 0 ]
    label =
      [ Text (Transform (V2 (realToFrac bonusLabelOffset) y) 0 (V2 1 1)) AnchorLeft (realToFrac bonusLabelHeight)
          [ (ch, c) | ch <- '+' : show (streakBonus st) ]
      | streakBonus st >= 1 ]

-- | The dim colour of the meter's track (the dot-grid grey, spec section 9).
trackColour :: Colour
trackColour = hexColour "#2a3140"

-- | The HUD text: top-right Points and Total (right-anchored lines), bottom-centre Streak.
hudNodes :: Settings -> Frame -> GameState -> [Node]
hudNodes cfg frame st =
  livesNodes cfg frame st <>
  [ line AnchorRight (halfW - m) (halfH - m - h / 2) ("Points " <> show st.roundPoints)
  , line AnchorRight (halfW - m) (halfH - m - h * 1.75) ("Total " <> show st.totalPoints)
  , line AnchorCentre 0 (negate halfH + m + h / 2) ("Streak " <> show st.streak)
  , Text (Transform (V2 (negate halfW + m) (negate halfH + m + hh / 2)) 0 (V2 1 1)) AnchorLeft hh
      [ (ch, hintColour) | ch <- escHint ]
  ]
  where
    halfH = realToFrac cfg.worldHeight / 2
    halfW = halfH * frame.viewport.aspect
    m = realToFrac hudMargin
    h = realToFrac hudTextHeight
    hh = realToFrac hintTextHeight
    line anchor x y str =
      Text (Transform (V2 x y) 0 (V2 1 1)) anchor h [ (ch, hexColour cfg.letterDefaultColour) | ch <- str ]

-- | The text of the bottom-left hint.
escHint :: String
escHint = "Esc: menu"

-- | The hint's colour: a muted grey, so it never competes with the HUD.
hintColour :: Colour
hintColour = hexColour "#7d8590"

-- | The Lives row, top-left: one square per Life of the Round's @startingLives@
-- (a hand-made state with more Lives than that shows them all), the first
-- 'lives' white and the rest dim.
livesNodes :: Settings -> Frame -> GameState -> [Node]
livesNodes cfg frame st =
  [ Square (at (V2 (x0 + fromIntegral i * (sz + gap)) y) sz sz) (if i < st.lives then lifeColour else trackColour)
  | i <- [0 .. total - 1] ]
  where
    total = max st.lives (max 1 st.roundSettings.startingLives) :: Int
    halfH = realToFrac cfg.worldHeight / 2
    halfW = halfH * frame.viewport.aspect
    sz = realToFrac lifeSize
    gap = realToFrac lifeGap
    x0 = negate halfW + realToFrac hudMargin + sz / 2
    y = halfH - realToFrac hudMargin - sz / 2

-- | A kept Life: white.
lifeColour :: Colour
lifeColour = Colour 1 1 1 1

-- | The Shot colour for a Streak (spec section 9): the ramp has 11 stops, one
-- per completed group of the Streak, from the settings' start colour at 0 to
-- the end colour at 10 groups (100 by default) and beyond. It spans 10 groups
-- whatever the group size, so it follows it. Each channel is interpolated
-- linearly between the two colours' @#rrggbb@ values (not in linear light).
shotColour :: Settings -> Int -> Colour
shotColour cfg strk = Colour (lerp r0 r1) (lerp g0 g1) (lerp b0 b1) 1
  where
    Colour r0 g0 b0 _ = hexColour cfg.shotStartColour
    Colour r1 g1 b1 _ = hexColour cfg.shotEndColour
    stop = max 0 (min 10 (strk `div` max 1 cfg.streakGroupSize))
    t = fromIntegral stop / 10 :: Float
    lerp a b = a * (1 - t) + b * t

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
