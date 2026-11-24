-- | Saved progress (spec sections 8 and 12): Total Points, Streak and Bonus.
-- These are saved state, not settings, and have their own key and codec.
-- Pure: the @localStorage@ access is in the frontend.
module Game.Save
  ( Save (..)
  , emptySave
  , storageKey
  , currentVersion
  , clampSave
  , encodeSave
  , decodeSave
  , saveToValue
  , saveFromValue
  ) where

import Data.Aeson (Value (..), eitherDecodeStrict, encode, object, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.Scientific (toRealFloat)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8, encodeUtf8)

-- | All three are non-negative whole numbers. Bonus is stored, not derived:
-- it is the completed groups of the Streak at the group size in force when
-- each group completed, and that size is a setting that can change between
-- sessions, so it cannot be recomputed from the Streak on load.
data Save = Save
  { totalPoints :: Int
  , streak :: Int
  , bonus :: Int
  }
  deriving stock (Eq, Show)

emptySave :: Save
emptySave = Save {totalPoints = 0, streak = 0, bonus = 0}

storageKey :: Text
storageKey = "typewizard.save"

currentVersion :: Int
currentVersion = 1

-- | Negative values become 0.
clampSave :: Save -> Save
clampSave s = Save {totalPoints = max 0 s.totalPoints, streak = max 0 s.streak, bonus = max 0 s.bonus}

saveToValue :: Save -> Value
saveToValue s = object
  [ "version" .= currentVersion
  , "totalPoints" .= s.totalPoints
  , "streak" .= s.streak
  , "bonus" .= s.bonus
  ]

encodeSave :: Save -> Text
encodeSave = decodeUtf8 . LBS.toStrict . encode . saveToValue . clampSave

-- | Anything unreadable gives 'emptySave'.
decodeSave :: Text -> Save
decodeSave t = either (const emptySave) saveFromValue (eitherDecodeStrict (encodeUtf8 t))

-- | A version other than the current one gives 'emptySave' (no migration
-- exists yet). A missing, non-numeric or fractional field is 0; a negative
-- one is 0; one beyond the range of 'Int' is the largest 'Int'.
saveFromValue :: Value -> Save
saveFromValue = \case
  Object o
    | Just (Number v) <- KeyMap.lookup "version" o
    , toRealFloat v == (fromIntegral currentVersion :: Double) ->
        Save {totalPoints = field "totalPoints" o, streak = field "streak" o, bonus = field "bonus" o}
  _ -> emptySave
  where
    field k o = case KeyMap.lookup k o of
      Just (Number n) ->
        let d = toRealFloat n :: Double
        in if d >= 9.0e15 then 9_000_000_000_000_000
           else if d >= 0 && d == fromIntegral (floor d :: Int) then floor d
           else 0
      _ -> 0
