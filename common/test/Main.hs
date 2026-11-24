module Main (main) where

import Control.Monad (unless)
import Data.Aeson (Value (..), decode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Data.ByteString.Lazy qualified as LBS
import Test.HUnit

import Game.Save qualified as Save
import Game.Settings
import SceneTests (sceneTests)
import ScoringTests (scoringTests)
import StateTests (stateTests)
import TypingTests (typingTests)
import WordsTests (wordsTests)

main :: IO ()
main = do
  result <- runTestTT (TestList [settingsTests, saveTests, wordsTests, stateTests, typingTests, scoringTests, sceneTests])
  unless (errors result == 0 && failures result == 0) (ioError (userError "tests failed"))

field :: Text -> Field
field k = case filter ((== k) . (.fieldKey)) fields of
  f : _ -> f
  [] -> error ("no field " <> T.unpack k)

num :: Text -> NumSpec
num k = case (field k).fieldSpec of
  Num n -> n
  Colour _ -> error "not a number"

col :: Text -> ColourSpec
col k = case (field k).fieldSpec of
  Colour c -> c
  Num _ -> error "not a colour"

-- | Edit a number field the way the page does.
edit :: Text -> Double -> Settings -> Settings
edit k = setNumber (num k)

settingsTests :: Test
settingsTests = TestLabel "settings" $ TestList
  [ "defaults are inside their bounds" ~: clampSettings defaultSettings @?= defaultSettings
  , "every number field's default is within its min and max" ~:
      sequence_ [ assertBool (T.unpack f.fieldKey) (lo <= n.numDefault && n.numDefault <= hi)
                | f <- fields, Num n <- [f.fieldSpec], let (lo, hi) = fieldBounds n defaultSettings ]
  , "there are 21 numbers and 14 colours (spec section 11)" ~:
      (length [ () | f <- fields, Num _ <- [f.fieldSpec] ], length [ () | f <- fields, Colour _ <- [f.fieldSpec] ]) @?= (21, 14)
  , "field keys are unique" ~: length (uniq (map (.fieldKey) fields)) @?= length fields
  , "defaults match spec sections 9 and 11" ~: do
      defaultSettings.startingLives @?= 3
      defaultSettings.shotDuration @?= 0.12
      defaultSettings.maxTickDt @?= 0.1
      defaultSettings.wordLookahead @?= 10
      defaultSettings.tier3Colour @?= "#5ec8e5"
      defaultSettings.shotEndColour @?= "#ff3b3b"

  , "an edit above the max clamps to the max" ~: (edit "startingLives" 99 defaultSettings).startingLives @?= 10
  , "an edit below the min clamps to the min" ~: (edit "gracePeriod" 0 defaultSettings).gracePeriod @?= 0.5
  , "a whole-number field rounds" ~: (edit "enemiesPerTier" 20.6 defaultSettings).enemiesPerTier @?= 21
  , "clamping is idempotent" ~:
      let s = clampSettings defaultSettings {startingLives = 500, intervalEnd = 9, lastTier = 1}
      in clampSettings s @?= s

  , "intervalEnd is clamped to intervalStart when intervalStart drops" ~:
      let s = edit "intervalStart" 0.5 (edit "intervalEnd" 1 defaultSettings)
      in (s.intervalStart, s.intervalEnd) @?= (0.5, 0.5)
  , "intervalEnd cannot be set above intervalStart" ~:
      (edit "intervalEnd" 9 defaultSettings).intervalEnd @?= 3
  , "intervalEnd's max follows intervalStart" ~:
      snd (fieldBounds (num "intervalEnd") (edit "intervalStart" 7 defaultSettings)) @?= 7
  , "lastTier is raised to firstTier when firstTier rises past it" ~:
      let s = edit "firstTier" 8 (edit "lastTier" 5 defaultSettings)
      in (s.firstTier, s.lastTier) @?= (8, 8)
  , "lastTier cannot be set below firstTier" ~:
      (edit "lastTier" 3 (edit "firstTier" 6 defaultSettings)).lastTier @?= 6
  , "an invalid colour edit falls back to the default" ~:
      (setColour (col "playerColour") "red" defaultSettings).playerColour @?= "#f5f5f5"
  , "a colour edit is lower-cased" ~:
      (setColour (col "playerColour") "#ABCDEF" defaultSettings).playerColour @?= "#abcdef"

  , "reset Rules touches only Rules" ~:
      let s = edit "startingLives" 7 (edit "enemySpeed" 4 defaultSettings)
          r = resetGroup Rules s
      in (r.startingLives, r.enemySpeed) @?= (3, 4)
  , "reset Spawning touches only Spawning" ~:
      let s = edit "startingLives" 7 (edit "enemySpeed" 4 defaultSettings)
          r = resetGroup Spawning s
      in (r.startingLives, r.enemySpeed) @?= (7, 1)
  , "reset Camera, Animation, Timing, Colours" ~: do
      let s = edit "worldHeight" 30 $ edit "shotDuration" 0.9 $ edit "maxTickDt" 0.4
                $ setColour (col "dotGridColour") "#123456" defaultSettings
      (resetGroup Camera s).worldHeight @?= 20
      (resetGroup Camera s).shotDuration @?= 0.9
      (resetGroup Animation s).shotDuration @?= 0.12
      (resetGroup Timing s).maxTickDt @?= 0.1
      (resetGroup Colours s).dotGridColour @?= "#2a3140"
      (resetGroup Colours s).worldHeight @?= 30
  , "every group reset, applied to a fully edited record, gives the defaults back" ~:
      let wild = foldr (\f s -> case f.fieldSpec of
                                  Num n -> setNumber n 1e9 s
                                  Colour c -> setColour c "#010203" s) defaultSettings fields
      in foldr resetGroup wild groups @?= defaultSettings
  , "reset all" ~: resetAll (edit "startingLives" 7 defaultSettings) @?= defaultSettings

  , "codec round trip, defaults" ~: decodeSettings (encodeSettings defaultSettings) @?= defaultSettings
  , "codec round trip, edited" ~:
      let s = edit "intervalStart" 4.25 $ edit "wordLookahead" 0 $ edit "plusDrawCap" 77
                $ setColour (col "tier5Colour") "#102030" defaultSettings
      in decodeSettings (encodeSettings s) @?= s
  , "the stored JSON carries version 1" ~:
      lookupKey "version" (encodeSettings defaultSettings) @?= Just (Number 1)
  , "whole-number fields are stored as integers" ~:
      T.isInfixOf "\"startingLives\":3," (encodeSettings defaultSettings) @?= True

  , "garbage text gives the defaults" ~: decodeSettings "not json{" @?= defaultSettings
  , "a non-object gives the defaults" ~: decodeSettings "[1,2]" @?= defaultSettings
  , "an empty object (no version) gives the defaults" ~: decodeSettings "{}" @?= defaultSettings
  , "a missing field falls back to its default" ~:
      let s = decodeSettings "{\"version\":1,\"startingLives\":5}"
      in (s.startingLives, s.gracePeriod, s.playerColour) @?= (5, 2, "#f5f5f5")
  , "a wrong-typed number falls back to its default" ~:
      (decodeSettings "{\"version\":1,\"startingLives\":\"five\",\"gracePeriod\":true,\"enemySpeed\":null}")
        `seq` let s = decodeSettings "{\"version\":1,\"startingLives\":\"five\",\"gracePeriod\":true,\"enemySpeed\":null}"
              in (s.startingLives, s.gracePeriod, s.enemySpeed) @?= (3, 2, 1)
  , "a wrong-typed colour falls back to its default" ~:
      (decodeSettings "{\"version\":1,\"playerColour\":12,\"tier3Colour\":\"blue\"}").playerColour @?= "#f5f5f5"
  , "an invalid colour string falls back to its default" ~:
      (decodeSettings "{\"version\":1,\"tier3Colour\":\"blue\"}").tier3Colour @?= "#5ec8e5"
  , "a fractional value in a whole-number field falls back" ~:
      (decodeSettings "{\"version\":1,\"startingLives\":4.5}").startingLives @?= 3
  , "an out-of-range stored value is clamped" ~:
      let s = decodeSettings "{\"version\":1,\"startingLives\":99,\"gracePeriod\":-3,\"worldHeight\":1e999}"
      in (s.startingLives, s.gracePeriod, s.worldHeight) @?= (10, 0.5, 60)
  , "a stored cross-field violation clamps the dependent field" ~:
      let s = decodeSettings "{\"version\":1,\"intervalStart\":2,\"intervalEnd\":5,\"firstTier\":7,\"lastTier\":4}"
      in (s.intervalEnd, s.lastTier) @?= (2, 7)
  , "an upper-case stored colour is normalised" ~:
      (decodeSettings "{\"version\":1,\"playerColour\":\"#ABCDEF\"}").playerColour @?= "#abcdef"
  , "version mismatch (older, no migration) gives defaults, ignoring the fields" ~:
      decodeSettings "{\"version\":0,\"startingLives\":5}" @?= defaultSettings
  , "version mismatch (newer) gives defaults" ~:
      decodeSettings "{\"version\":2,\"startingLives\":5}" @?= defaultSettings
  , "a non-numeric version gives defaults" ~:
      decodeSettings "{\"version\":\"1\",\"startingLives\":5}" @?= defaultSettings

  , "migrateWith: current version passes through" ~:
      migrateWith [] 1 KeyMap.empty @?= Just KeyMap.empty
  , "migrateWith: a known step runs" ~:
      fmap (KeyMap.member "migrated") (migrateWith [(0, KeyMap.insert "migrated" Null)] 0 KeyMap.empty) @?= Just True
  , "migrateWith: a missing step gives Nothing" ~:
      fmap (const ()) (migrateWith [] 0 KeyMap.empty) @?= Nothing
  , "migrateWith: a newer version gives Nothing" ~:
      fmap (const ()) (migrateWith [] 2 KeyMap.empty) @?= Nothing
  ]
  where
    uniq = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

lookupKey :: Text -> Text -> Maybe Value
lookupKey k t = case decode (LBS.fromStrict (T.encodeUtf8 t)) of
  Just (Object o) -> KeyMap.lookup (Key.fromText k) o
  _ -> Nothing

saveTests :: Test
saveTests = TestLabel "save" $ TestList
  [ "round trip" ~:
      let s = Save.Save {Save.totalPoints = 1234, Save.streak = 17, Save.bonus = 1}
      in Save.decodeSave (Save.encodeSave s) @?= s
  , "round trip, empty" ~: Save.decodeSave (Save.encodeSave Save.emptySave) @?= Save.emptySave
  , "stored with version 1" ~: lookupKey "version" (Save.encodeSave Save.emptySave) @?= Just (Number 1)
  , "garbage gives the empty save" ~: Save.decodeSave "%%%" @?= Save.emptySave
  , "a non-object gives the empty save" ~: Save.decodeSave "5" @?= Save.emptySave
  , "a version mismatch gives the empty save" ~:
      Save.decodeSave "{\"version\":2,\"totalPoints\":9,\"streak\":9,\"bonus\":9}" @?= Save.emptySave
  , "no version gives the empty save" ~:
      Save.decodeSave "{\"totalPoints\":9}" @?= Save.emptySave
  , "missing fields are 0" ~:
      Save.decodeSave "{\"version\":1,\"totalPoints\":9}" @?= Save.Save 9 0 0
  , "wrong-typed fields are 0" ~:
      Save.decodeSave "{\"version\":1,\"totalPoints\":\"9\",\"streak\":null,\"bonus\":[1]}" @?= Save.emptySave
  , "negative fields are 0" ~:
      Save.decodeSave "{\"version\":1,\"totalPoints\":-5,\"streak\":-1,\"bonus\":2}" @?= Save.Save 0 0 2
  , "fractional fields are 0" ~:
      Save.decodeSave "{\"version\":1,\"totalPoints\":2.5,\"streak\":3,\"bonus\":0}" @?= Save.Save 0 3 0
  , "huge fields cap instead of overflowing" ~:
      (Save.decodeSave "{\"version\":1,\"totalPoints\":1e999,\"streak\":3,\"bonus\":0}").totalPoints @?= 9_000_000_000_000_000
  , "encoding clamps negatives" ~:
      Save.decodeSave (Save.encodeSave (Save.Save (-1) (-2) (-3))) @?= Save.emptySave
  ]
