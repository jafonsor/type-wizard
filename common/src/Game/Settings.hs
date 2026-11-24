-- | Every tunable of the game (spec section 11) as one record, with a field
-- table that gives each field its default, minimum and maximum, a clamp that
-- keeps a record valid, versioned JSON, and group resets. Pure: no IO, no
-- Reflex. The settings page and the JSON codec are both driven by 'fields'.
module Game.Settings
  ( Settings (..)
  , defaultSettings
    -- * The field table
  , Group (..)
  , groups
  , groupLabel
  , Field (..)
  , Spec (..)
  , NumSpec (..)
  , ColourSpec (..)
  , fields
  , fieldsIn
  , fieldBounds
    -- * Editing and clamping
  , clampSettings
  , setNumber
  , setColour
  , resetGroup
  , resetAll
  , validColour
    -- * Storage format
  , storageKey
  , currentVersion
  , encodeSettings
  , decodeSettings
  , settingsToValue
  , settingsFromValue
  , migrateWith
  ) where

import Data.Aeson (Object, Value (..), eitherDecodeStrict, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isHexDigit)
import Data.Scientific (toRealFloat)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)

-- | Seconds unless stated; distances in world units.
data Settings = Settings
  { -- Rules
    startingLives :: Int
  , gracePeriod :: Double
  , enemiesPerTier :: Int
  , firstTier :: Int
  , lastTier :: Int
  , streakGroupSize :: Int
    -- Spawning
  , intervalStart :: Double
  , intervalEnd :: Double
  , spawnRadius :: Double
  , enemySpeed :: Double
  , wordLookahead :: Int
    -- Camera
  , worldHeight :: Double
  , cameraTimeConstant :: Double
  , cameraInset :: Double
  , playerMargin :: Double
    -- Animation
  , shotDuration :: Double
  , plusFlyDuration :: Double
  , plusHold :: Double
  , plusSpreadRadius :: Double
  , plusDrawCap :: Int
    -- Timing
  , maxTickDt :: Double
    -- Colours, as @#rrggbb@
  , tier3Colour :: Text
  , tier4Colour :: Text
  , tier5Colour :: Text
  , tier6Colour :: Text
  , tier7Colour :: Text
  , tier8Colour :: Text
  , playerColour :: Text
  , backgroundColour :: Text
  , dotGridColour :: Text
  , letterDefaultColour :: Text
  , letterTypedColour :: Text
  , letterLockColour :: Text
  , shotStartColour :: Text
  , shotEndColour :: Text
  }
  deriving stock (Eq, Show)

-- | Defaults from spec sections 9 and 11.
defaultSettings :: Settings
defaultSettings = Settings
  { startingLives = 3
  , gracePeriod = 2
  , enemiesPerTier = 50
  , firstTier = 3
  , lastTier = 8
  , streakGroupSize = 10
  , intervalStart = 3
  , intervalEnd = 1
  , spawnRadius = 1
  , enemySpeed = 1
  , wordLookahead = 10
  , worldHeight = 20
  , cameraTimeConstant = 0.25
  , cameraInset = 2
  , playerMargin = 3
  , shotDuration = 0.12
  , plusFlyDuration = 0.5
  , plusHold = 0.1
  , plusSpreadRadius = 0.6
  , plusDrawCap = 30
  , maxTickDt = 0.1
  , tier3Colour = "#5ec8e5"
  , tier4Colour = "#6fd68a"
  , tier5Colour = "#d6e06a"
  , tier6Colour = "#f2b45a"
  , tier7Colour = "#ee7f5c"
  , tier8Colour = "#e0577f"
  , playerColour = "#f5f5f5"
  , backgroundColour = "#0e1117"
  , dotGridColour = "#2a3140"
  , letterDefaultColour = "#e6e6e6"
  , letterTypedColour = "#6fe08a"
  , letterLockColour = "#ff5c5c"
  , shotStartColour = "#4aa3ff"
  , shotEndColour = "#ff3b3b"
  }

-- | The reset groups, in page order.
data Group = Rules | Spawning | Camera | Animation | Timing | Colours
  deriving stock (Eq, Ord, Show, Enum, Bounded)

groups :: [Group]
groups = [minBound .. maxBound]

groupLabel :: Group -> Text
groupLabel = \case
  Rules -> "Rules"
  Spawning -> "Spawning"
  Camera -> "Camera"
  Animation -> "Animation"
  Timing -> "Timing"
  Colours -> "Colours"

data Field = Field
  { fieldKey :: Text -- ^ the JSON key
  , fieldLabel :: Text
  , fieldGroup :: Group
  , fieldSpec :: Spec
  }

data Spec = Num NumSpec | Colour ColourSpec

-- | A number. Whole-number fields have @integral@; their value is held as a
-- 'Double' here and rounded when stored. The bounds may depend on other fields
-- (the cross-field rules).
data NumSpec = NumSpec
  { integral :: Bool
  , numDefault :: Double
  , numMin :: Settings -> Double
  , numMax :: Settings -> Double
  , getNum :: Settings -> Double
  , putNum :: Double -> Settings -> Settings
  }

-- | A colour, @#rrggbb@.
data ColourSpec = ColourSpec
  { colourDefault :: Text
  , getColour :: Settings -> Text
  , putColour :: Text -> Settings -> Settings
  }

real :: Text -> Text -> Group -> (Settings -> Double) -> (Double -> Settings -> Settings)
     -> (Settings -> Double) -> (Settings -> Double) -> Field
real key label grp get put lo hi =
  Field key label grp (Num (NumSpec False (get defaultSettings) lo hi get put))

whole :: Text -> Text -> Group -> (Settings -> Int) -> (Int -> Settings -> Settings)
      -> (Settings -> Double) -> (Settings -> Double) -> Field
whole key label grp get put lo hi =
  Field key label grp
    (Num (NumSpec True (fromIntegral (get defaultSettings)) lo hi (fromIntegral . get) (put . round)))

colour :: Text -> Text -> (Settings -> Text) -> (Text -> Settings -> Settings) -> Field
colour key label get put =
  Field key label Colours (Colour (ColourSpec (get defaultSettings) get put))

-- | Every field, in an order that puts a field after the one its bounds read
-- ('firstTier' before 'lastTier', 'intervalStart' before 'intervalEnd'), so one
-- pass of 'clampSettings' settles the cross-field rules.
fields :: [Field]
fields =
  [ whole "startingLives" "Starting Lives" Rules (.startingLives) (\v s -> s {startingLives = v}) (const 1) (const 10)
  , real "gracePeriod" "Grace Period (s)" Rules (.gracePeriod) (\v s -> s {gracePeriod = v}) (const 0.5) (const 10)
  , whole "enemiesPerTier" "Enemies per Tier" Rules (.enemiesPerTier) (\v s -> s {enemiesPerTier = v}) (const 10) (const 200)
  , whole "firstTier" "First Tier" Rules (.firstTier) (\v s -> s {firstTier = v}) (const 3) (const 8)
  , whole "lastTier" "Last Tier" Rules (.lastTier) (\v s -> s {lastTier = v}) (fromIntegral . (.firstTier)) (const 8)
  , whole "streakGroupSize" "Streak group size" Rules (.streakGroupSize) (\v s -> s {streakGroupSize = v}) (const 2) (const 50)

  , real "intervalStart" "Spawn interval at start (s)" Spawning (.intervalStart) (\v s -> s {intervalStart = v}) (const 0.5) (const 10)
  , real "intervalEnd" "Spawn interval at end (s)" Spawning (.intervalEnd) (\v s -> s {intervalEnd = v}) (const 0.2) (.intervalStart)
  , real "spawnRadius" "Spawn radius beyond the view" Spawning (.spawnRadius) (\v s -> s {spawnRadius = v}) (const 0) (const 5)
  , real "enemySpeed" "Enemy speed (units/s)" Spawning (.enemySpeed) (\v s -> s {enemySpeed = v}) (const 0.2) (const 5)
  , whole "wordLookahead" "Word lookahead" Spawning (.wordLookahead) (\v s -> s {wordLookahead = v}) (const 0) (const 50)

  , real "worldHeight" "World height (units)" Camera (.worldHeight) (\v s -> s {worldHeight = v}) (const 8) (const 60)
  , real "cameraTimeConstant" "Camera time constant (s)" Camera (.cameraTimeConstant) (\v s -> s {cameraTimeConstant = v}) (const 0.05) (const 2)
  , real "cameraInset" "Camera inset (units)" Camera (.cameraInset) (\v s -> s {cameraInset = v}) (const 0) (const 6)
  , real "playerMargin" "Player margin (units)" Camera (.playerMargin) (\v s -> s {playerMargin = v}) (const 1) (const 8)

  , real "shotDuration" "Shot duration (s)" Animation (.shotDuration) (\v s -> s {shotDuration = v}) (const 0.05) (const 1)
  , real "plusFlyDuration" "Plus Sign fly duration (s)" Animation (.plusFlyDuration) (\v s -> s {plusFlyDuration = v}) (const 0.1) (const 2)
  , real "plusHold" "Plus Sign hold (s)" Animation (.plusHold) (\v s -> s {plusHold = v}) (const 0) (const 1)
  , real "plusSpreadRadius" "Plus Sign spread radius (units)" Animation (.plusSpreadRadius) (\v s -> s {plusSpreadRadius = v}) (const 0) (const 2)
  , whole "plusDrawCap" "Plus Sign draw cap" Animation (.plusDrawCap) (\v s -> s {plusDrawCap = v}) (const 1) (const 200)

  , real "maxTickDt" "Longest tick (s)" Timing (.maxTickDt) (\v s -> s {maxTickDt = v}) (const 0.02) (const 0.5)

  , colour "tier3Colour" "Tier 3" (.tier3Colour) (\v s -> s {tier3Colour = v})
  , colour "tier4Colour" "Tier 4" (.tier4Colour) (\v s -> s {tier4Colour = v})
  , colour "tier5Colour" "Tier 5" (.tier5Colour) (\v s -> s {tier5Colour = v})
  , colour "tier6Colour" "Tier 6" (.tier6Colour) (\v s -> s {tier6Colour = v})
  , colour "tier7Colour" "Tier 7" (.tier7Colour) (\v s -> s {tier7Colour = v})
  , colour "tier8Colour" "Tier 8" (.tier8Colour) (\v s -> s {tier8Colour = v})
  , colour "playerColour" "Player" (.playerColour) (\v s -> s {playerColour = v})
  , colour "backgroundColour" "Background" (.backgroundColour) (\v s -> s {backgroundColour = v})
  , colour "dotGridColour" "Dot grid" (.dotGridColour) (\v s -> s {dotGridColour = v})
  , colour "letterDefaultColour" "Letter" (.letterDefaultColour) (\v s -> s {letterDefaultColour = v})
  , colour "letterTypedColour" "Letter typed" (.letterTypedColour) (\v s -> s {letterTypedColour = v})
  , colour "letterLockColour" "Letter Lock-expected" (.letterLockColour) (\v s -> s {letterLockColour = v})
  , colour "shotStartColour" "Shot ramp start" (.shotStartColour) (\v s -> s {shotStartColour = v})
  , colour "shotEndColour" "Shot ramp end" (.shotEndColour) (\v s -> s {shotEndColour = v})
  ]

fieldsIn :: Group -> [Field]
fieldsIn g = filter ((== g) . fieldGroup) fields

-- | The bounds a number field has right now, given the other fields.
fieldBounds :: NumSpec -> Settings -> (Double, Double)
fieldBounds n s = (n.numMin s, n.numMax s)

-- | Is it @#rrggbb@ (either case)?
validColour :: Text -> Bool
validColour t = case T.uncons t of
  Just ('#', hex) -> T.length hex == 6 && T.all isHexDigit hex
  _ -> False

clampNum :: NumSpec -> Settings -> Double -> Double
clampNum n s x
  | isNaN x = n.numDefault
  | otherwise = max (n.numMin s) (min (n.numMax s) x')
  where
    x' = if n.integral && not (isInfinite x) then fromIntegral (round x :: Integer) else x

clampField :: Field -> Settings -> Settings
clampField f s = case f.fieldSpec of
  Num n -> n.putNum (clampNum n s (n.getNum s)) s
  Colour c
    | validColour v -> c.putColour (T.toLower v) s
    | otherwise -> c.putColour c.colourDefault s
    where v = c.getColour s

-- | Brings every field inside its bounds, including the cross-field rules
-- (@intervalEnd <= intervalStart@, @lastTier >= firstTier@; the dependent
-- field moves). Idempotent.
clampSettings :: Settings -> Settings
clampSettings s0 = foldl' (flip clampField) s0 fields

-- | Sets a number field (a user edit), clamped, and re-settles the others.
setNumber :: NumSpec -> Double -> Settings -> Settings
setNumber n v s = clampSettings (n.putNum v s)

-- | Sets a colour field; an invalid value leaves it at its default.
setColour :: ColourSpec -> Text -> Settings -> Settings
setColour c v s = clampSettings (c.putColour v s)

-- | Puts every field of the group back to its default.
resetGroup :: Group -> Settings -> Settings
resetGroup g s = clampSettings (foldl' reset s (fieldsIn g))
  where
    reset acc f = case f.fieldSpec of
      Num n -> n.putNum n.numDefault acc
      Colour c -> c.putColour c.colourDefault acc

resetAll :: Settings -> Settings
resetAll = const defaultSettings

-- * Storage format

storageKey :: Text
storageKey = "typewizard.settings"

currentVersion :: Int
currentVersion = 1

settingsToValue :: Settings -> Value
settingsToValue s = object (("version" .= currentVersion) : map pair fields)
  where
    pair f = Key.fromText f.fieldKey .= case f.fieldSpec of
      Num n
        | n.integral -> Number (fromIntegral (round (n.getNum s) :: Int))
        | otherwise -> Number (realToFrac (n.getNum s))
      Colour c -> String (c.getColour s)

encodeSettings :: Settings -> Text
encodeSettings = decodeUtf8 . LBS.toStrict . encode . settingsToValue

-- | Anything unreadable gives the defaults.
decodeSettings :: Text -> Settings
decodeSettings t = case eitherDecodeStrict (encodeUtf8 t) of
  Right v -> settingsFromValue v
  Left _ -> defaultSettings

-- | The version check and the field-by-field read. A missing or wrong-typed
-- field keeps its default; a number out of range is clamped. A version that is
-- not the current one is migrated if 'migrations' reach the current one, and
-- otherwise gives the defaults.
settingsFromValue :: Value -> Settings
settingsFromValue = \case
  Object o
    | Just (Number n) <- KeyMap.lookup "version" o
    , let v = toRealFloat n :: Double
    , v == fromIntegral (round v :: Int)
    , Just o' <- migrateWith migrations (round v) o -> fromObject o'
  _ -> defaultSettings

-- | Migrations, each taking an object of version @n@ to version @n + 1@. None
-- exists yet: version 1 is the first.
migrations :: [(Int, Object -> Object)]
migrations = []

-- | Walks an object from @from@ up to 'currentVersion' through the steps;
-- 'Nothing' if a step is missing or the version is newer than this build.
migrateWith :: [(Int, Object -> Object)] -> Int -> Object -> Maybe Object
migrateWith steps from o
  | from == currentVersion = Just o
  | from > currentVersion = Nothing
  | otherwise = do
      step <- lookup from steps
      migrateWith steps (from + 1) (step o)

fromObject :: Object -> Settings
fromObject o = foldl' readField defaultSettings fields
  where
    readField s f = clampField f case (f.fieldSpec, KeyMap.lookup (Key.fromText f.fieldKey) o) of
      (Num n, Just (Number x))
        | not n.integral || isInfinite d || d == fromIntegral (round d :: Int) -> n.putNum d s
        where d = toRealFloat x
      (Colour c, Just (String v)) -> c.putColour v s
      _ -> s
