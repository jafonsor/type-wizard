-- | The Game page's canvas (spec sections 5 and 8). Reflex creates a fresh
-- @canvas@ on each visit; once it is in the page the renderer takes it over.
-- Leaving the page removes the canvas, and the render loop stops by itself on
-- its next frame, so nothing here tears anything down.
--
-- For now it draws a demo scene (the Player, the dot grid, two lines of
-- overlay text) from a trivial pure function. The real @buildScene@ comes with
-- the game logic.
module Frontend.Game
  ( gameCanvas
  , demoScene
  ) where

import Control.Monad (when)
import Data.Text (Text)
import Data.Text qualified as T
import Language.Javascript.JSaddle (jsg, liftJSM, toJSVal, valToText, (!))
import Reflex.Dom.Core

import Frontend.Bench (runBench)
import Game.Settings (Settings (..))
import Renderer

-- | The canvas, filling the window behind the page's controls, and the
-- renderer on it. If the renderer cannot start (no WebGL), the page shows the
-- reason in place of a blank canvas. The world height is read from the
-- Settings as the page opens.
gameCanvas
  :: (DomBuilder t m, Prerender t m)
  => Dynamic t Settings -> m ()
gameCanvas settings = prerender_ blank do
  (canvas, _) <- elAttr' "canvas" ("class" =: "game-canvas") blank
  pb <- getPostBuild
  started <- performEvent $ ffor (attachWith const (current settings) pb) \s -> liftJSM do
    raw <- toJSVal (_element_raw canvas)
    initRenderer raw >>= \case
      Left err -> pure (Just err)
      Right r -> do
        let worldH = realToFrac s.worldHeight
        startRenderLoop r \frame -> pure (Just (demoScene worldH frame))
        search <- jsg ("location" :: Text) >>= (! ("search" :: Text)) >>= valToText
        when ("bench" `T.isInfixOf` search) runBench
        pure Nothing
  failure <- holdDyn Nothing started
  dyn_ $ ffor failure \case
    Nothing -> blank
    Just err -> elAttr "p" ("class" =: "game-error" <> "data-error" =: "renderer") (text err)

-- | A frame of the demo: background, dot grid and the Player in the world, a
-- title at the top (right of the Menu control) and the Esc hint bottom-left on
-- the overlay.
demoScene :: Float -> Frame -> Scene
demoScene worldH frame = Scene
  { sceneCamera = Camera (V2 0 0) worldH
  , sceneWorld =
      [ Square (at 0 0 (worldH * vp.aspect + 4) (worldH + 4)) (hex 0x0e1117)
      , DotGrid 2 0.08 (hex 0x2a3140)
      , Square (at 0 0 1.2 1.2) (hex 0xf5f5f5)
      ]
  , sceneOverlay =
      [ line AnchorLeft (V2 (-halfW + menuClear) (halfH - margin)) "Type Wizard renderer demo"
      , line AnchorLeft (V2 (-halfW + margin) (-halfH + margin)) "Esc: menu"
      ]
  }
  where
    vp = frame.viewport
    halfH = worldH / 2
    halfW = halfH * vp.aspect
    margin = 0.9
    -- Clear of the Menu control, which sits in the top-left corner.
    menuClear = 3.0
    at x y w h = Transform (V2 x y) 0 (V2 w h)
    line anchor pos str = Text (Transform pos 0 (V2 1 1)) anchor 0.9 [(c, hex 0xe6e6e6) | c <- str]
    hex :: Int -> Colour
    hex n = Colour (chan 16) (chan 8) (chan 0) 1
      where chan sh = fromIntegral ((n `div` (2 ^ sh)) `mod` 256) / 255
