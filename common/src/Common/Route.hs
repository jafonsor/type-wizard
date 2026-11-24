module Common.Route where

import Data.Functor.Identity (Identity)
import Data.Kind (Type)
import Data.Text (Text)
import Obelisk.Route
import Obelisk.Route.TH



data BackendRoute :: Type -> Type where
  BackendRoute_Api :: BackendRoute ()

-- | The app has no URL routing: one frontend route, one exported
-- @index.html@. The page the player is on (@Frontend.Page@) is ordinary
-- state, not a route.
data FrontendRoute :: Type -> Type where
  FrontendRoute_Main :: FrontendRoute ()



concat <$> mapM deriveRouteComponent
  [ ''BackendRoute
  , ''FrontendRoute
  ]



checkedFullRouteEncoder :: Encoder Identity Identity (R (FullRoute BackendRoute FrontendRoute)) PageName
checkedFullRouteEncoder = case checkEncoder fullRouteEncoder of
  Left e -> error $ show e
  Right x -> x

-- | Any path no route matches is the main route, so the page also decodes
-- when GitHub Pages serves it under @/type-wizard/@.
fullRouteEncoder
  :: Encoder (Either Text) Identity (R (FullRoute BackendRoute FrontendRoute)) PageName
fullRouteEncoder = mkFullRouteEncoder
  (FullRoute_Frontend (ObeliskRoute_App FrontendRoute_Main) :/ ())
  (\case BackendRoute_Api -> PathSegment "api" $ unitEncoder mempty)
  (\case FrontendRoute_Main -> PathEnd $ unitEncoder mempty)
