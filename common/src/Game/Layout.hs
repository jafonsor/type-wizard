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
  , hintTextHeight
  , lifeSize
  , lifeGap
  , shotLength
  , shotWidth
  , plusSize
  , plusBarThickness
  , plusMaxDelay
  , plusShrinkTime
  , plusShrinkScale
  , blinkPeriod
  , blinkDimAlpha
  , hitFlashAlpha
  , hitFlashTime
  , meterGrowTime
  , meterFlashTime
  , meterEmptyTime
  , labelPopTime
  , labelPopScale
  , typoFadeTime
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

-- | The "Esc: menu" hint's text height (smaller than the HUD lines).
hintTextHeight :: Double
hintTextHeight = 0.6

-- | A Life square's side (spec section 9) and the gap between two.
lifeSize, lifeGap :: Double
lifeSize = 0.4
lifeGap = 0.2

-- | The Shot is a triangle this long (spec section 9) and this wide.
shotLength, shotWidth :: Double
shotLength = 0.5
shotWidth = 0.3

-- | A Plus Sign is this big (both bars' length) and each bar is this thick,
-- as a fraction of that size.
plusSize, plusBarThickness :: Double
plusSize = 0.5
plusBarThickness = 0.2

-- | Each Plus Sign's random extra wait before it flies is 0 to this many
-- seconds (spec section 9; fixed, not a setting).
plusMaxDelay :: Double
plusMaxDelay = 0.15

-- | Over the last 'plusShrinkTime' seconds of its flight a Plus Sign shrinks
-- to 'plusShrinkScale' times its size and fades out.
plusShrinkTime, plusShrinkScale :: Double
plusShrinkTime = 0.15
plusShrinkScale = 0.3

-- | Hit feedback (spec section 9). The Player alternates full opacity and
-- 'blinkDimAlpha' every 'blinkPeriod' seconds for the whole Grace Period
-- (full first); a full-screen red overlay starts at 'hitFlashAlpha' and
-- decays linearly to 0 over 'hitFlashTime'. Fixed, not settings.
blinkPeriod, blinkDimAlpha, hitFlashAlpha, hitFlashTime :: Double
blinkPeriod = 0.1
blinkDimAlpha = 0.25
hitFlashAlpha = 0.3
hitFlashTime = 0.3

-- | Streak Meter animations (spec section 9), all linear: the fill grows over
-- 'meterGrowTime' per Kill; a group-completing Kill shows the bar full and
-- white for 'meterFlashTime', then empties it over 'meterEmptyTime', while the
-- "+N" label scales from 'labelPopScale' to 1 over 'labelPopTime'; a Typo
-- empties the bar and fades the label over 'typoFadeTime'.
meterGrowTime, meterFlashTime, meterEmptyTime, labelPopTime, labelPopScale, typoFadeTime :: Double
meterGrowTime = 0.1
meterFlashTime = 0.15
meterEmptyTime = 0.25
labelPopTime = 0.2
labelPopScale = 1.4
typoFadeTime = 0.2
