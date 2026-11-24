-- | The three pages and the switch between them. The current page is a
-- 'Dynamic' held above the switch; there is no URL routing and no
-- @routeLink@ (spec section 8).
module Frontend.Page
  ( Page (..)
  , pageSwitch
  ) where

import Control.Monad.Fix (MonadFix)
import Data.Text (Text)
import Data.Text qualified as T
import Reflex.Dom.Core

import Frontend.Words (allWords)

data Page = Start | Game | Settings
  deriving stock (Eq, Show)

-- | Runs the three pages. Each page widget returns the 'Event' that asks for
-- another page; the 'Dynamic' that remembers the current one sits here, above
-- the switch.
pageSwitch
  :: (DomBuilder t m, PostBuild t m, MonadHold t m, MonadFix m)
  => m ()
pageSwitch = mdo
  page <- holdDyn Start requested
  requested <- switchHold never =<< dyn (pageWidget <$> page)
  pure ()

pageWidget :: DomBuilder t m => Page -> m (Event t Page)
pageWidget = \case
  Start -> section "start" "Start" do
    el "p" $ text $ "Words: " <> T.pack (show (length allWords))
    play <- button "Play"
    settings <- button "Settings"
    pure $ leftmost [Game <$ play, Settings <$ settings]
  Game -> section "game" "Game" do
    menu <- button "Menu"
    pure $ Start <$ menu
  Settings -> section "settings" "Settings" do
    back <- button "Back"
    pure $ Start <$ back

-- | A page: a wrapper tagged with @data-page@ and a title.
section :: DomBuilder t m => Text -> Text -> m a -> m a
section key title body =
  elAttr "section" ("data-page" =: key) do
    el "h1" $ text title
    body
