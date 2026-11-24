-- | A JSON summary of the state for the browser check
-- (@window.TypeWizardGame.state()@, dev only: it is written only when the
-- page URL has @?hook@). Not used by the game.
module Game.Debug
  ( stateSummary
  , stateSummaryText
  ) where

import Data.Aeson (Value (Null), encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as LBS
import Data.IntMap.Strict qualified as IntMap
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8)

import Game.State

stateSummary :: GameState -> Value
stateSummary st = object
  [ "phase" .= show st.phase
  , "tier" .= st.currentTier
  , "spawned" .= object [ Key.fromString (show t) .= n | (t, n) <- IntMap.toList st.spawnCounts ]
  , "totalSpawned" .= totalSpawned st
  , "enemyCount" .= length st.enemies
  , "aspect" .= st.viewAspect
  , "player" .= object ["x" .= st.playerPos.vx, "y" .= st.playerPos.vy]
  , "focus" .= case focusInfo st.focus of
      Nothing -> Null
      Just (i, k) -> object ["enemy" .= i, "k" .= k]
  , "locked" .= case st.focus of { Locked {} -> True; _ -> False }
  , "correct" .= st.correctKeys
  , "wrong" .= st.wrongKeys
  , "typos" .= st.typos
  , "kills" .= st.kills
  , "streak" .= st.streak
  , "bonus" .= streakBonus st
  , "roundPoints" .= st.roundPoints
  , "longestStreak" .= st.longestStreak
  , "meter" .= meterFill st
  , "totalPoints" .= st.totalPoints
  , "groupCompletedAt" .= st.groupCompletedAt
  , "accuracy" .= accuracy st
  , "wpm" .= wpm st
  , "enemies" .=
      [ object
          [ "id" .= e.enemyId, "word" .= e.enemyWord, "tier" .= e.enemyTier
          , "x" .= e.enemyPos.vx, "y" .= e.enemyPos.vy, "distance" .= distanceToPlayer st e ]
      | e <- st.enemies ]
  ]

-- | The summary as JSON text.
stateSummaryText :: GameState -> Text
stateSummaryText = decodeUtf8 . LBS.toStrict . encode . stateSummary
