module Frontend where

import Obelisk.Frontend
import Obelisk.Generated.Static
import Obelisk.Route
import Obelisk.Route.Frontend
import Reflex.Dom

import Common.Route
import Frontend.Page (pageSwitch)



frontend :: Frontend (R FrontendRoute)
frontend = Frontend
  { _frontend_head = frontendHead
  , _frontend_body = frontendBody
  }

frontendHead :: ObeliskWidget t route m => RoutedT t route m ()
frontendHead = do
  el "title" $ text "Type Wizard"
  elAttr "meta" ("name" =: "viewport" <> "content" =: "width=device-width, initial-scale=1") blank
  elAttr "link" ("rel" =: "stylesheet" <> "href" =: static @"css/app.css") blank
  -- The localStorage shim (Frontend.Storage), loaded before the app starts.
  elAttr "script" ("src" =: static @"js/storage.js") blank
  -- The renderer's JS executor (the renderer package), also loaded first.
  elAttr "script" ("src" =: static @"js/renderer.js") blank
  -- The Game page's key shim (Frontend.Game), loaded first as well.
  elAttr "script" ("src" =: static @"js/keys.js") blank

frontendBody :: ObeliskWidget t (R FrontendRoute) m => RoutedT t (R FrontendRoute) m ()
frontendBody = elClass "main" "app" pageSwitch
