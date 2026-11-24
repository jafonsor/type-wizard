{-# LANGUAGE CPP #-}
{-# LANGUAGE ForeignFunctionInterface #-}

-- | The JS seam of the renderer: the calls into the executor in
-- @static/src/js/renderer.js@ (@window.TypeWizardRenderer@). Not exported from
-- the package.
--
-- Two kinds of call, by cost:
--
-- * Once per canvas, through jsaddle (JSON round trips, fine at this rate):
--   'create' and 'viewportOf'.
-- * Every frame, through the wasm JS FFI (a plain wasm to JS call): the
--   frame callback JS calls into Haskell ('startFrames', a @wrapper sync@
--   export, so it runs inside JS's rAF task), and the one draw call Haskell
--   makes back ('draw', @unsafe@, a pointer and an instance count over wasm
--   memory).
--
-- The FFI half exists only on wasm. Elsewhere (the native build that renders
-- the page on the server) the renderer is never started, and 'startFrames'
-- does nothing.
module Renderer.Js
  ( create
  , viewportOf
  , startFrames
  , draw
  , logError
  ) where

import Data.Text (Text)
import Foreign.Ptr (Ptr)
import Language.Javascript.JSaddle (JSM, jsg, valToBool, valToNumber, valToText, (!), (#))
import Language.Javascript.JSaddle qualified as JSaddle

#if defined(wasm32_HOST_ARCH)
import Control.Monad.IO.Class (liftIO)
import Data.Text qualified as T
import Foreign.C.String (CString)
import GHC.Foreign (withCStringLen)
import GHC.Wasm.Prim (JSVal)
import GHC.IO.Encoding (utf8)
#endif

-- | Sets up GL on the canvas. 'Left' carries the message to show.
create :: JSaddle.JSVal -> JSM (Either Text Int)
create canvas = do
  r <- jsg ("TypeWizardRenderer" :: Text) # ("create" :: Text) $ [canvas]
  ok <- r ! ("ok" :: Text) >>= valToBool
  if ok
    then Right . round <$> (r ! ("handle" :: Text) >>= valToNumber)
    else Left <$> (r ! ("error" :: Text) >>= valToText)

-- | CSS pixels: width, height.
viewportOf :: Int -> JSM (Double, Double)
viewportOf h = do
  r <- jsg ("TypeWizardRenderer" :: Text) # ("viewport" :: Text) $ [h]
  w <- r ! ("width" :: Text) >>= valToNumber
  ht <- r ! ("height" :: Text) >>= valToNumber
  pure (w, ht)

#if defined(wasm32_HOST_ARCH)

foreign import javascript "wrapper sync"
  mkFrameCallback :: (Double -> Double -> Double -> IO ()) -> IO JSVal

foreign import javascript unsafe "window.TypeWizardRenderer.start($1, $2)"
  jsStart :: Int -> JSVal -> IO ()

foreign import javascript unsafe "window.TypeWizardRenderer.draw($1, __exports.memory.buffer, $2, $3)"
  jsDraw :: Int -> Ptr Float -> Int -> IO ()

-- The message crosses as UTF-8 bytes in wasm memory, decoded in JS (as
-- jsaddle-wasm does for its own strings), not as a JSString.
foreign import javascript unsafe "console.error(new TextDecoder().decode(new Uint8Array(__exports.memory.buffer, $1, $2)))"
  jsConsoleError :: CString -> Int -> IO ()

-- | Hands JS the per-frame callback (rAF time in seconds, canvas width and
-- height in CSS pixels) and lets it start its rAF loop.
startFrames :: Int -> (Double -> Double -> Double -> IO ()) -> JSM ()
startFrames h cb = liftIO do
  f <- mkFrameCallback cb
  jsStart h f

-- | The one call per frame: the header and instances are at the pointer.
draw :: Int -> Ptr Float -> Int -> IO ()
draw = jsDraw

logError :: Text -> IO ()
logError msg = withCStringLen utf8 (T.unpack msg) (uncurry jsConsoleError)

#else

startFrames :: Int -> (Double -> Double -> Double -> IO ()) -> JSM ()
startFrames _ _ = pure ()

draw :: Int -> Ptr Float -> Int -> IO ()
draw _ _ _ = pure ()

logError :: Text -> IO ()
logError _ = pure ()

#endif
