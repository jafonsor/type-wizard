-- | The sizes of the visual spec (section 9) that the rules also depend on,
-- in world units. 'Game.State' needs them for contact (an Enemy parks where
-- it touches the Player) and 'Game.Scene' for drawing; both import them from
-- here so the picture and the rule cannot disagree.
module Game.Layout
  ( playerSize
  , enemySize
  , contactDistance
  , wordOffset
  , wordCapHeight
  , dotSpacing
  , dotRadius
  , defaultAspect
  , meterSize
  , meterOffset
  , bonusLabelOffset
  , bonusLabelHeight
  , hudMargin
  , hudTextHeight
  ) where

-- | The Player is a square of this side.
playerSize :: Double
playerSize = 1.2

-- | An Enemy is a square of this side.
enemySize :: Double
enemySize = 1.0

-- | Centre to centre distance at which the two squares touch (half of each
-- side: 0.6 + 0.5).
contactDistance :: Double
contactDistance = (playerSize + enemySize) / 2

-- | A Word is centred this far below its Enemy's centre.
wordOffset :: Double
wordOffset = 1.0

-- | The Word's text height (cap height) argument.
wordCapHeight :: Double
wordCapHeight = 0.9

-- | Dot grid spacing and dot radius.
dotSpacing, dotRadius :: Double
dotSpacing = 2
dotRadius = 0.08

-- | The aspect ratio (width over height) assumed until the page reports the
-- real one: 16:9.
defaultAspect :: Double
defaultAspect = 16 / 9

-- | The Streak Meter: a bar of this width and height ...
meterSize :: (Double, Double)
meterSize = (2, 0.25)

-- | ... centred this far above the Player's centre.
meterOffset :: Double
meterOffset = 1.6

-- | The "+N" label: its left edge sits this far to the right of the Player's
-- centre (past the bar's right end) at the bar's height; its text height.
bonusLabelOffset, bonusLabelHeight :: Double
bonusLabelOffset = 1.4
bonusLabelHeight = 0.8

-- | The HUD's distance from the screen edges and its text height, in world
-- height units (the overlay's units).
hudMargin, hudTextHeight :: Double
hudMargin = 0.6
hudTextHeight = 0.8
