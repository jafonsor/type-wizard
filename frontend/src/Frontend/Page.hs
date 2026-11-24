-- | The three pages and the switch between them. The current page is a
-- 'Dynamic' held above the switch; there is no URL routing and no
-- @routeLink@ (spec section 8). Above the switch also sit the two pieces of
-- state that outlive a page: the 'Settings' record and the 'Save' (spec
-- sections 11 and 12), each one 'Dynamic' written whole on change.
module Frontend.Page
  ( Page (..)
  , pageSwitch
  ) where

import Control.Monad.Fix (MonadFix)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Language.Javascript.JSaddle (liftJSM)
import Reflex.Dom.Core
import Text.Read (readMaybe)

import Frontend.Game (gameCanvas)
import Frontend.Storage (loadSave, loadSettings, storeSave, storeSettings)
import Frontend.Words (allWords)
import Game.Save (Save (..), emptySave)
import Game.Settings qualified as S

data Page = Start | Game | Settings
  deriving stock (Eq, Show)

-- | What a page hands back to the switch: a page to go to, and edits to the
-- state above it.
data PageOut t = PageOut
  { pageRequest :: Event t Page
  , settingsEdit :: Event t (S.Settings -> S.Settings)
  , saveEdit :: Event t (Save -> Save)
  }

pageOnly :: Reflex t => Event t Page -> PageOut t
pageOnly p = PageOut p never never

-- | Runs the three pages. The 'S.Settings' and the 'Save' are read from
-- storage once the app runs in the browser (the exported page shows the
-- defaults until then), and each change is written back. A failing storage
-- leaves the in-memory values in charge.
pageSwitch
  :: (DomBuilder t m, PostBuild t m, MonadHold t m, MonadFix m, Prerender t m)
  => m ()
pageSwitch = mdo
  page <- holdDyn Start requested
  out <- dyn (pageWidget settings save <$> page)
  requested <- switchHold never (pageRequest <$> out)
  settingsEdits <- switchHold never (settingsEdit <$> out)
  saveEdits <- switchHold never (saveEdit <$> out)
  loaded <- fmap switchDyn $ prerender (pure never) do
    pb <- getPostBuild
    performEvent (liftJSM ((,) <$> loadSettings <*> loadSave) <$ pb)
  settings <- foldDyn ($) S.defaultSettings (leftmost [const . fst <$> loaded, settingsEdits])
  save <- foldDyn ($) emptySave (leftmost [const . snd <$> loaded, saveEdits])
  prerender_ blank do
    performEvent_ (liftJSM . storeSettings <$> updated settings)
    performEvent_ (liftJSM . storeSave <$> updated save)

pageWidget
  :: (DomBuilder t m, PostBuild t m, MonadHold t m, MonadFix m, Prerender t m)
  => Dynamic t S.Settings -> Dynamic t Save -> Page -> m (PageOut t)
pageWidget settings save = \case
  Start -> section "start" "Start" do
    el "p" $ text $ "Words: " <> T.pack (show (length allWords))
    stat "total-points" "Total Points" (.totalPoints)
    stat "streak" "Streak" (.streak)
    stat "bonus" "Bonus" (.bonus)
    play <- button "Play"
    settingsB <- button "Settings"
    pure $ pageOnly $ leftmost [Game <$ play, Settings <$ settingsB]
  Game -> section "game" "Game" do
    menu <- button "Menu"
    gameCanvas settings
    pure $ pageOnly $ Start <$ menu
  Settings -> section "settings" "Settings" do
    back <- button "Back"
    groupEdits <- traverse (settingsGroup settings) S.groups
    resetAll <- button "Reset all"
    progress <- savedProgress
    pure PageOut
      { pageRequest = Start <$ back
      , settingsEdit = leftmost ((S.resetAll <$ resetAll) : groupEdits)
      , saveEdit = progress
      }
  where
    stat key label get =
      elAttr "p" ("data-stat" =: key) do
        text (label <> ": ")
        dynText (T.pack . show . get <$> save)

-- | A page: a wrapper tagged with @data-page@ and a title.
section :: DomBuilder t m => Text -> Text -> m a -> m a
section key title body =
  elAttr "section" ("data-page" =: key) do
    el "h1" $ text title
    body

-- | One group of settings: its fields and its reset button.
settingsGroup
  :: (DomBuilder t m, MonadHold t m, MonadFix m)
  => Dynamic t S.Settings -> S.Group -> m (Event t (S.Settings -> S.Settings))
settingsGroup settings g =
  elAttr "fieldset" ("data-group" =: S.groupLabel g) do
    el "legend" $ text (S.groupLabel g)
    edits <- traverse (fieldWidget settings) (S.fieldsIn g)
    reset <- button ("Reset " <> S.groupLabel g)
    pure $ leftmost ((S.resetGroup g <$ reset) : edits)

fieldWidget
  :: (DomBuilder t m, MonadHold t m, MonadFix m)
  => Dynamic t S.Settings -> S.Field -> m (Event t (S.Settings -> S.Settings))
fieldWidget settings f = el "div" $ el "label" do
  text (f.fieldLabel <> " ")
  case f.fieldSpec of
    S.Num n -> numberField settings f.fieldKey n
    S.Colour c -> colourField settings f.fieldKey c

-- | A number control. It clamps while editing: every parsable keystroke edits
-- the record (so the stored value is always in range), a value above the
-- maximum is rewritten in the box at once, and one below the minimum is
-- rewritten when the edit is committed (so typing @0.8@ with a minimum of
-- @0.5@ is not cut short at the @0@). Changes that come from elsewhere (a
-- reset, a cross-field clamp) are written to the box too.
numberField
  :: forall t m. (DomBuilder t m, MonadHold t m, MonadFix m)
  => Dynamic t S.Settings -> Text -> S.NumSpec -> m (Event t (S.Settings -> S.Settings))
numberField settings key n = mdo
  s0 <- sample (current settings)
  let valueOf = n.getNum
      bounds = S.fieldBounds n <$> settings
      attrsOf (lo, hi) = Map.fromList
        [("min", Just (renderNum lo)), ("max", Just (renderNum hi))]
      (lo0, hi0) = S.fieldBounds n s0
      config = (def :: InputElementConfig EventResult t (DomBuilderSpace m))
        { _inputElementConfig_initialValue = renderNum (valueOf s0)
        , _inputElementConfig_setValue = Just (leftmost [overshoot, committed, external])
        , _inputElementConfig_elementConfig = elementCfg
            (Map.fromList
              [ ("type", "number"), ("data-key", key)
              , ("step", if n.integral then "1" else "any")
              , ("min", renderNum lo0), ("max", renderNum hi0)
              ])
            (Just (attrsOf <$> updated bounds))
        }
  ie <- inputElement config
  let typed = _inputElement_input ie
      parsed = fmapMaybe parseNum typed
      overshoot = attachWithMaybe
        (\s v -> let hi = snd (S.fieldBounds n s) in if v > hi then Just (renderNum hi) else Nothing)
        (current settings) parsed
      committed = tag (renderNum . valueOf <$> current settings) (domEvent Change (_inputElement_element ie))
      external = renderNum <$> difference (changed (valueOf <$> settings)) typed
  pure (S.setNumber n <$> parsed)

-- | A colour control, a plain @input type=color@.
colourField
  :: forall t m. (DomBuilder t m, MonadHold t m, MonadFix m)
  => Dynamic t S.Settings -> Text -> S.ColourSpec -> m (Event t (S.Settings -> S.Settings))
colourField settings key c = mdo
  s0 <- sample (current settings)
  let external = difference (changed (c.getColour <$> settings)) (_inputElement_input ie)
      config = (def :: InputElementConfig EventResult t (DomBuilderSpace m))
        { _inputElementConfig_initialValue = c.getColour s0
        , _inputElementConfig_setValue = Just external
        , _inputElementConfig_elementConfig = elementCfg
            (Map.fromList [("type", "color"), ("data-key", key)]) Nothing
        }
  ie <- inputElement config
  pure (S.setColour c <$> _inputElement_input ie)

-- | The "Saved progress" section: "Reset progress" needs a second click,
-- "Really reset?", and then clears Total Points, Streak and Bonus.
savedProgress
  :: (DomBuilder t m, MonadHold t m, MonadFix m, PostBuild t m)
  => m (Event t (Save -> Save))
savedProgress = elAttr "div" ("data-group" =: "Saved progress") do
  el "h2" $ text "Saved progress"
  rec armed <- holdDyn False (leftmost [True <$ arm, False <$ confirm])
      (b, _) <- el' "button" $ dynText (bool "Reset progress" "Really reset?" <$> armed)
      let click = domEvent Click b
          arm = gate (not <$> current armed) click
          confirm = gate (current armed) click
  pure (const emptySave <$ confirm)
  where
    bool no yes c = if c then yes else no :: Text

renderNum :: Double -> Text
renderNum x
  | x == fromIntegral r = T.pack (show r)
  | otherwise = T.pack (show x)
  where r = round x :: Int

parseNum :: Text -> Maybe Double
parseNum t = readMaybe (fixup (T.unpack (T.strip t)))
  where
    fixup s = case s of
      '.' : _ -> '0' : s
      _ | not (null s), last s == '.' -> s <> "0"
      _ -> s

-- | The updates of a 'Dynamic' that really change its value.
changed :: (Reflex t, Eq a) => Dynamic t a -> Event t a
changed d = attachWithMaybe (\old new -> if old == new then Nothing else Just new) (current d) (updated d)

elementCfg
  :: forall t s. (Reflex t, DomSpace s)
  => Map.Map AttributeName Text -> Maybe (Event t (Map.Map AttributeName (Maybe Text)))
  -> ElementConfig EventResult t s
elementCfg attrs modify = (def :: ElementConfig EventResult t s)
  { _elementConfig_initialAttributes = attrs
  , _elementConfig_modifyAttributes = modify
  }
