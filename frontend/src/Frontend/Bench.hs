{-# LANGUAGE CPP #-}
{-# LANGUAGE ForeignFunctionInterface #-}

-- | A dev-only measurement of the cost of crossing the wasm/JS boundary
-- (ticket 15, spec section 15). It runs only when the page URL has a
-- @bench@ query parameter (@.../?bench@), after the renderer has started, and
-- writes its numbers to @window.TypeWizardBench@ (milliseconds). Nothing else
-- in the game calls it.
--
-- * @ffiCalls@ / @ffiMs@: 100,000 trivial @unsafe@ JS FFI calls from Haskell,
--   timed with @performance.now()@.
-- * @callbacks@ / @callbackMs@: 100,000 calls from JS into a @wrapper sync@
--   Haskell callback, the direction the per-frame callback takes.
-- * @jsaddleCalls@ / @jsaddleMs@: 1,000 calls through jsaddle
--   (@jsg "performance" # "now"@), the route the game does not use per frame.
--
-- The per-frame cost of the renderer itself (the Haskell callback: pull,
-- flatten, pack, the draw call) is counted in JS under @?bench@ too:
-- @TypeWizardRenderer.stats.callbackMs@ over @.frames@.
module Frontend.Bench (runBench) where

import Language.Javascript.JSaddle (JSM)

#if defined(wasm32_HOST_ARCH)
import Control.Monad (replicateM_)
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import Data.Text qualified as T
import Foreign.C.String (CString)
import GHC.Foreign (withCStringLen)
import GHC.IO.Encoding (utf8)
import GHC.Wasm.Prim (JSVal)
import Language.Javascript.JSaddle (jsg, (#))

foreign import javascript unsafe "performance.now()"
  jsNow :: IO Double

foreign import javascript unsafe "$1 + 1"
  jsInc :: Int -> IO Int

foreign import javascript unsafe "window.TypeWizardBench = window.TypeWizardBench || {}; window.TypeWizardBench[new TextDecoder().decode(new Uint8Array(__exports.memory.buffer, $1, $2))] = $3"
  jsRecordRaw :: CString -> Int -> Double -> IO ()

jsRecord :: T.Text -> Double -> IO ()
jsRecord name v = withCStringLen utf8 (T.unpack name) \(p, n) -> jsRecordRaw p n v

foreign import javascript "wrapper sync"
  mkCallback :: (Int -> IO ()) -> IO JSVal

foreign import javascript unsafe "(() => { const t = performance.now(); for (let i = 0; i < $2; i++) $1(i); return performance.now() - t; })()"
  jsCallMany :: JSVal -> Int -> IO Double

runBench :: JSM ()
runBench = do
  liftIO do
    let n = 100_000
    t0 <- jsNow
    let loop :: Int -> Int -> IO Int
        loop i acc | i >= n = pure acc
                   | otherwise = jsInc acc >>= loop (i + 1)
    _ <- loop 0 0
    t1 <- jsNow
    jsRecord "ffiCalls" (fromIntegral n)
    jsRecord "ffiMs" (t1 - t0)
    cb <- mkCallback (\_ -> pure ())
    ms <- jsCallMany cb n
    jsRecord "callbacks" (fromIntegral n)
    jsRecord "callbackMs" ms
  a <- liftIO jsNow
  replicateM_ 1000 (jsg ("performance" :: Text) # ("now" :: Text) $ ([] :: [Int]))
  b <- liftIO jsNow
  liftIO do
    jsRecord "jsaddleCalls" 1000
    jsRecord "jsaddleMs" (b - a)

#else

runBench :: JSM ()
runBench = pure ()

#endif
