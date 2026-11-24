-- | The Round Summary's rows (spec section 4, "Round Summary rows"): pure, so
-- the order and the formatting are tested. The page renders each as a table
-- row tagged with its key.
module Game.Summary
  ( summaryRows
  , fixed1
  ) where

import Data.Text (Text)
import Data.Text qualified as T

import Game.State (RoundResult (..))

-- | (key, label, value) in the spec's order: Points (this Round), Total
-- Points (banked), WPM, Accuracy, Kills, Longest Streak, Streak (current,
-- carried out).
summaryRows :: RoundResult -> [(Text, Text, Text)]
summaryRows r =
  [ ("points", "Points", num r.resPoints)
  , ("total", "Total Points", num r.resTotalPoints)
  , ("wpm", "WPM", fixed1 r.resWpm)
  , ("accuracy", "Accuracy", fixed1 r.resAccuracy <> "%")
  , ("kills", "Kills", num r.resKills)
  , ("longest", "Longest Streak", num r.resLongestStreak)
  , ("streak", "Streak", num r.resStreak)
  ]
  where
    num = T.pack . show

-- | One decimal, rounded half up (non-negative values: "12.3", "100.0").
fixed1 :: Double -> Text
fixed1 x = T.pack (show (n `div` 10) <> "." <> show (n `mod` 10))
  where
    n = round (max 0 x * 10) :: Int
