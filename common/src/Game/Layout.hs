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
