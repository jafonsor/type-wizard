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
  , "lives" .= st.lives
  , "graceActive" .= graceActive st
  , "graceRemaining" .= graceRemaining st
  , "paused" .= st.paused
  , "windowFocused" .= st.windowFocused
  , "roundTime" .= st.roundTime
  , "lastTime" .= st.lastTime
  , "killAnims" .= length st.killAnims
  , "shots" .= maybe 0 (\t -> activeShots t st) st.lastTime
  , "plusSigns" .= maybe 0 (\t -> activePlusSigns t st) st.lastTime
  , "anims" .=
      [ object
          [ "start" .= k.kaStart, "from" .= vec k.kaFrom, "to" .= vec k.kaTo, "streak" .= k.kaStreak
          , "points" .= k.kaPoints, "signs" .= length k.kaSigns, "end" .= killAnimEnd k ]
      | k <- st.killAnims ]
  , "camera" .= object
      [ "start" .= st.camera.caStart, "from" .= vec st.camera.caFrom
      , "target" .= vec st.camera.caTarget, "tau" .= st.camera.caTau
      , "centre" .= vec (cameraNow st) ]
  , "roundResult" .= fmap resultSummary st.roundResult
  , "enemies" .=
      [ object
          [ "id" .= e.enemyId, "word" .= e.enemyWord, "tier" .= e.enemyTier
          , "x" .= e.enemyPos.vx, "y" .= e.enemyPos.vy, "distance" .= distanceToPlayer st e ]
      | e <- st.enemies ]
  ]

vec :: Vec2 -> Value
vec p = object ["x" .= p.vx, "y" .= p.vy]

resultSummary :: RoundResult -> Value
resultSummary r = object
  [ "points" .= r.resPoints, "totalPoints" .= r.resTotalPoints, "wpm" .= r.resWpm
  , "accuracy" .= r.resAccuracy, "kills" .= r.resKills
  , "longestStreak" .= r.resLongestStreak, "streak" .= r.resStreak ]

-- | The summary as JSON text.
stateSummaryText :: GameState -> Text
stateSummaryText = decodeUtf8 . LBS.toStrict . encode . stateSummary
