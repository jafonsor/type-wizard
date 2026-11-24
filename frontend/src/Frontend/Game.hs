-- | The Game page's canvas and the game network on it (spec sections 5 to 8).
-- Reflex creates a fresh @canvas@ on each visit; once it is in the page the
-- renderer takes it over. Leaving the page removes the canvas, and the render
-- loop stops by itself on its next frame, so nothing here tears anything down
-- (the network lives in the page's widget and goes with it).
--
-- The network, per visit:
--
-- * the render pull (which the JS-owned rAF loop calls once per frame) fires
--   one @Tick@ with the frame time through @newTriggerEvent@, and an @Aspect@
--   when the viewport's aspect ratio changes;
-- * entering the page fires @Start seed save@ with a clock-derived seed and
--   the app's current 'Save' (the carried-in Streak and Total Points);
-- * the key shim (@static/src/js/keys.js@) listens to @keydown@ on @window@
--   while this canvas is attached and fires one @Key c@ or @Tab@ per
--   Keystroke through @newTriggerEvent@ (Tab's default is prevented in JS);
-- * the inputs are merged into one event and folded with 'step';
-- * every new state is written to an 'IORef' (the handoff cell, never an
--   @MVar@: the pull only peeks and never blocks);
-- * the pull returns @Nothing@ until the first state exists, then a freshly
--   built 'Scene' on every frame.
--
-- Scoring is persisted from here: each new state in which a Kill or a Typo
-- just happened fires one @Save -> Save@ edit (the Streak and its Bonus) that
-- the page switch applies to the app's @Dynamic Save@ and stores. Total Points
-- are not touched (the Round-end slice banks them).
--
-- Dev hook: with @?hook@ in the page URL each new state also writes a JSON
-- summary to @window.TypeWizardGame.json@ (@TypeWizardGame.state()@ parses
-- it), for the browser check. Without @?hook@ nothing is built.
module Frontend.Game
  ( gameCanvas
  ) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import Language.Javascript.JSaddle (JSM, function, jsg, liftJSM, toJSVal, valToNumber, valToText, (!), (#), (<#))
import Reflex.Dom.Core

import Frontend.Bench (runBench)
import Game.Debug (stateSummaryText)
import Game.Save (Save)
import Game.Scene (buildScene)
import Game.Settings (Settings)
import Game.State (GameState (..), initialState, step)
import Game.State qualified as S
import Game.Words (Words)
import Renderer

-- | The canvas, filling the window behind the page's controls, with the game
-- on it. If the renderer cannot start (no WebGL), the page shows the reason
-- in place of a blank canvas. The Settings are snapshotted by @Start@ as the
-- page opens, so editing them elsewhere never changes a Round.
gameCanvas
  :: (DomBuilder t m, Prerender t m)
  => Words -> Dynamic t Settings -> Dynamic t Save -> m (Event t (Save -> Save))
gameCanvas ws settings save = fmap switchDyn $ prerender (pure never) do
  (canvas, _) <- elAttr' "canvas" ("class" =: "game-canvas") blank
  pb <- getPostBuild
  (tickE, fireTick) <- newTriggerEvent
  (aspectE, fireAspect) <- newTriggerEvent
  (keyE, fireKey) <- newTriggerEvent
  cell <- liftIO (newIORef Nothing)
  hookOn <- liftIO (newIORef False)
  lastAspect <- liftIO (newIORef Nothing)

  -- Inputs of one batch are merged, never dropped: Start, Tick and Aspect
  -- are different events and may fire together.
  seedE <- performEvent (liftJSM clockSeed <$ pb)
  let inputs = mergeWith (<>)
        [ pure <$> attachWith (\sv sd -> S.Start sd sv) (current save) seedE
        , pure . S.Tick <$> tickE
        , pure . S.Aspect <$> aspectE
        , pure <$> keyE
        ]
  gameState <- foldDyn (\(s, is) st -> foldl' (flip (step s ws)) st is) initialState
    (attachWith (,) (current settings) inputs)

  -- A Kill or a Typo just happened: persist the Streak (and its Bonus).
  let progress = attachWithMaybe
        (\old new -> if new.kills > old.kills || new.typos > old.typos then Just (S.progressSave new) else Nothing)
        (current gameState) (updated gameState)

  -- The only writer of the handoff cell.
  performEvent_ $ ffor (updated gameState) \st -> do
    liftIO (writeIORef cell (Just st))
    on <- liftIO (readIORef hookOn)
    when on $ liftJSM do
      hook <- jsg ("TypeWizardGame" :: Text)
      hook <# ("json" :: Text) $ stateSummaryText st

  started <- performEvent $ ffor pb \() -> liftJSM do
    raw <- toJSVal (_element_raw canvas)
    initRenderer raw >>= \case
      Left err -> pure (Just err)
      Right r -> do
        search <- jsg ("location" :: Text) >>= (! ("search" :: Text)) >>= valToText
        liftIO (writeIORef hookOn ("hook" `T.isInfixOf` search))
        raw' <- toJSVal (_element_raw canvas)
        cb <- function \_ _ args -> case args of
          a : _ -> valToText a >>= liftIO . fireKey . keyInput
          [] -> pure ()
        _ <- jsg ("TypeWizardKeys" :: Text) # ("attach" :: Text) $ (raw', cb)
        startRenderLoop r (pullScene cell lastAspect fireTick fireAspect)
        when ("bench" `T.isInfixOf` search) runBench
        pure Nothing
  failure <- holdDyn Nothing started
  dyn_ $ ffor failure \case
    Nothing -> blank
    Just err -> elAttr "p" ("class" =: "game-error" <> "data-error" =: "renderer") (text err)
  pure progress

-- | What the key shim sends: @"Tab"@ or one lowercase letter.
keyInput :: Text -> S.Input
keyInput t = case T.unpack t of
  "Tab" -> S.Tab
  [c] -> S.Key c
  _ -> S.Key ' ' -- ignored by 'step'

-- | The render pull, run by JS's rAF task once per frame: fire the Tick (and
-- the aspect when it changed), then peek the cell. It never blocks.
pullScene
  :: IORef (Maybe GameState) -> IORef (Maybe Double) -> (Double -> IO ()) -> (Double -> IO ())
  -> Frame -> IO (Maybe Scene)
pullScene cell lastAspect fireTick fireAspect frame = do
  let ratio = realToFrac frame.viewport.aspect
  seen <- readIORef lastAspect
  when (seen /= Just ratio) do
    writeIORef lastAspect (Just ratio)
    fireAspect ratio
  fireTick frame.time
  fmap (\st -> buildScene st.roundSettings frame st) <$> readIORef cell

-- | A seed from the clock: the wall clock in microseconds plus the
-- high-resolution timer's fraction, so two visits in one millisecond differ.
clockSeed :: JSM Word64
clockSeed = do
  d <- valToNumber =<< (jsg ("Date" :: Text) # ("now" :: Text)) ([] :: [Int])
  p <- valToNumber =<< (jsg ("performance" :: Text) # ("now" :: Text)) ([] :: [Int])
  pure (fromIntegral (round (d * 1000 + p * 1000) :: Integer))
