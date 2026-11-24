-- | The @localStorage@ seam (spec section 12): a thin wrapper over the JS shim
-- @static/src/js/storage.js@ (@window.TypeWizardStorage@). Every call also
-- tolerates the shim being absent or throwing, so a failure means defaults
-- on load and a dropped write on store. The pure codecs are in
-- "Game.Settings" and "Game.Save".
--
-- The interface is @JSM@ rather than the spec's bare @IO@, because the
-- calls go through the JavaScript context.
module Frontend.Storage
  ( loadSave
  , storeSave
  , loadSettings
  , storeSettings
  ) where

import Control.Exception (SomeException)
import Control.Monad (void)
import Data.Text (Text)
import Language.Javascript.JSaddle

import Game.Save (Save, decodeSave, emptySave, encodeSave)
import Game.Save qualified as Save
import Game.Settings (Settings, decodeSettings, defaultSettings, encodeSettings)
import Game.Settings qualified as Settings

loadSave :: JSM Save
loadSave = maybe emptySave decodeSave <$> load Save.storageKey

storeSave :: Save -> JSM ()
storeSave = store Save.storageKey . encodeSave

loadSettings :: JSM Settings
loadSettings = maybe defaultSettings decodeSettings <$> load Settings.storageKey

storeSettings :: Settings -> JSM ()
storeSettings = store Settings.storageKey . encodeSettings

-- | The stored text, or 'Nothing' if there is none or storage failed.
load :: Text -> JSM (Maybe Text)
load key = attempt Nothing do
  v <- jsg ("TypeWizardStorage" :: Text) # ("load" :: Text) $ [key]
  fromJSVal v

store :: Text -> Text -> JSM ()
store key value = attempt () do
  void $ jsg ("TypeWizardStorage" :: Text) # ("store" :: Text) $ (key, value)

attempt :: a -> JSM a -> JSM a
attempt fallback act = act `catch` \(_ :: SomeException) -> pure fallback
