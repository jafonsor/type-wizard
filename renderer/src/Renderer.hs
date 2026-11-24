-- | A small 2D renderer (spec section 5): the game describes a frame as a
-- 'Scene', a tree of nodes; the renderer flattens it, packs one buffer of
-- instances and hands it to a JS executor that owns WebGL.
--
-- > canvas <- (the canvas Reflex created, as a JSVal)
-- > Right r <- initRenderer canvas
-- > startRenderLoop r \frame -> pure (Just (buildTheScene frame))
--
-- The loop runs from the browser's @requestAnimationFrame@, once per frame
-- calls the pull function, and makes one draw call. It stops by itself the
-- first frame after the canvas is no longer in the document, so there is no
-- stop function: leaving the page is the teardown, and a fresh canvas starts
-- a fresh loop.
--
-- The pull function runs inside the browser's rAF task. It must return
-- without blocking: read an 'Data.IORef.IORef', never take an @MVar@.
-- 'Nothing' keeps the last scene (redrawn at the current size).
module Renderer
  ( -- * Describing a frame
    Scene (..)
  , Camera (..)
  , Node (..)
  , Anchor (..)
  , Transform (..)
  , Colour (..)
  , V2 (..)
    -- * Running
  , Viewport (..)
  , Frame (..)
  , Renderer
  , initRenderer
  , getViewport
  , startRenderLoop
  ) where

import Control.Monad.IO.Class (liftIO)
import Control.Exception (SomeAsyncException, SomeException, fromException, throwIO, try)
import Data.Foldable (for_)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Foreign.ForeignPtr (ForeignPtr, mallocForeignPtrBytes, withForeignPtr)
import Foreign.Marshal.Array (pokeArray)
import Foreign.Storable (sizeOf)
import Language.Javascript.JSaddle (JSM, JSVal)

import Renderer.Internal
import Renderer.Js qualified as Js

-- | A renderer bound to one canvas.
data Renderer = Renderer
  { handle :: Int
  , buffer :: IORef Buffer
  , lastScene :: IORef (Maybe Scene)
  }

-- | The packed frame: pinned memory, GC-managed, and its size in floats.
data Buffer = Buffer (ForeignPtr Float) Int

-- | Creates the WebGL context on the canvas, sizes its backing store from the
-- CSS size times @devicePixelRatio@ and keeps it sized as the canvas
-- resizes. 'Left' carries a message for the player when WebGL is
-- unavailable.
initRenderer :: JSVal -> JSM (Either Text Renderer)
initRenderer canvas =
  Js.create canvas >>= \case
    Left e -> pure (Left e)
    Right h -> liftIO do
      let cap = 4096
      fp <- mallocForeignPtrBytes (cap * sizeOf (0 :: Float))
      Right <$> (Renderer h <$> newIORef (Buffer fp cap) <*> newIORef Nothing)

-- | The canvas size in CSS pixels, as of now.
getViewport :: Renderer -> JSM Viewport
getViewport r = do
  (w, h) <- Js.viewportOf r.handle
  pure (viewportOf w h)

-- | Starts the loop. Each frame the pull function gets the 'Frame' and
-- returns the 'Scene' to draw, or 'Nothing' to keep the last one. A frame
-- that fails is reported with @console.error@ and the next is tried; a
-- thread kill is rethrown.
startRenderLoop :: Renderer -> (Frame -> IO (Maybe Scene)) -> JSM ()
startRenderLoop r pull = Js.startFrames r.handle (onFrame r pull)

viewportOf :: Double -> Double -> Viewport
viewportOf w h = Viewport (realToFrac w) (realToFrac h) (if h > 0 then realToFrac (w / h) else 1)

onFrame :: Renderer -> (Frame -> IO (Maybe Scene)) -> Double -> Double -> Double -> IO ()
onFrame r pull ts w h =
  try (frame r pull ts (viewportOf w h)) >>= \case
    Right () -> pure ()
    Left (e :: SomeException)
      | Just (a :: SomeAsyncException) <- fromException e -> throwIO a
      | otherwise -> Js.logError ("Could not draw a frame: " <> T.pack (show e))

frame :: Renderer -> (Frame -> IO (Maybe Scene)) -> Double -> Viewport -> IO ()
frame r pull ts vp = do
  fresh <- pull (Frame vp ts)
  for_ fresh (writeIORef r.lastScene . Just)
  readIORef r.lastScene >>= \case
    Nothing -> pure ()
    Just scene -> do
      let (n, floats) = packScene vp.aspect scene
          needed = length floats
      Buffer fp cap <- readIORef r.buffer
      Buffer fp' _ <-
        if needed <= cap
          then pure (Buffer fp cap)
          else do
            let cap' = max needed (cap * 2)
            fp2 <- mallocForeignPtrBytes (cap' * sizeOf (0 :: Float))
            let b = Buffer fp2 cap'
            writeIORef r.buffer b
            pure b
      withForeignPtr fp' \p -> do
        pokeArray p floats
        Js.draw r.handle p n
