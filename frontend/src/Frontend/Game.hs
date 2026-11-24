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
-- the page switch applies to the app's @Dynamic Save@ and stores.
--
-- /Round end./ 'S.roundEnded' compares each new state with the one before it
-- and yields the 'S.RoundResult' on the Running to Over transition only, so the
-- one @RoundEnded@ event per Round goes out of the page ('goRoundEnded'); the
-- app root banks it ('S.bankRound') and saves. While the Phase is Over the
-- page shows the Round Summary (a DOM panel over the frozen canvas). "Play
-- again" and Enter (Over only) re-fire @Start@ with a fresh seed and the
-- current 'Save'; "Back to start" and Escape leave ('goLeave'). Leaving a
-- Round that is not Over banks nothing.
--
-- /Blur./ The key shim reports window @blur@, @focus@ and any pointer press
-- as inputs; 'step' keeps the pause (see "Game.State"), and a DOM overlay
-- says "Paused, click or press any key to resume" while @paused@ is set.
--
-- Dev hook: with @?hook@ in the page URL each new state also writes a JSON
-- summary to @window.TypeWizardGame.json@ (@TypeWizardGame.state()@ parses
-- it), for the browser check. Without @?hook@ nothing is built.
module Frontend.Game
  ( GameOut (..)
  , gameCanvas
  ) where

import Control.Monad (when)
import Data.Foldable (for_)
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
import Game.State (GameState (..), Phase (..), RoundResult, initialState, step)
import Game.State qualified as S
import Game.Summary (summaryRows)
import Game.Words (Words)
import Renderer

-- | What the page hands out: edits of the app's 'Save' (the Streak after a
-- Kill or Typo), the one 'RoundResult' of each finished Round, and a request
-- to leave to Start (Escape, "Back to start").
data GameOut t = GameOut
  { goSave :: Event t (Save -> Save)
  , goRoundEnded :: Event t RoundResult
  , goLeave :: Event t ()
  }

-- | A choice on the Round Summary.
data Choice = PlayAgain | BackToStart
  deriving stock (Eq)

-- | The canvas, filling the window behind the page's controls, with the game
-- on it. If the renderer cannot start (no WebGL), the page shows the reason
-- in place of a blank canvas. The Settings are snapshotted by @Start@ as the
-- page opens, so editing them elsewhere never changes a Round.
gameCanvas
  :: (DomBuilder t m, Prerender t m)
  => Words -> Dynamic t Settings -> Dynamic t Save -> m (GameOut t)
gameCanvas ws settings save = do
  out <- gameCanvas' ws settings save
  pure GameOut
    { goSave = switchDyn (goSave <$> out)
    , goRoundEnded = switchDyn (goRoundEnded <$> out)
    , goLeave = switchDyn (goLeave <$> out)
    }

gameCanvas'
  :: (DomBuilder t m, Prerender t m)
  => Words -> Dynamic t Settings -> Dynamic t Save -> m (Dynamic t (GameOut t))
gameCanvas' ws settings save = prerender (pure (GameOut never never never)) $ mdo
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
  seedE <- performEvent (liftJSM clockSeed <$ leftmost [pb, playAgain])
  let inputs = mergeWith (<>)
        [ pure <$> attachWith (\sv sd -> S.Start sd sv) (current save) seedE
        , pure . S.Tick <$> tickE
        , pure . S.Aspect <$> aspectE
        , pure . keyInput <$> keyE
        ]
  gameState <- foldDyn (\(s, is) st -> foldl' (flip (step s ws)) st is) initialState
    (attachWith (,) (current settings) inputs)

  -- Enter plays again, but only while the Round Summary shows.
  let isOver = (\st -> st.phase == Over) <$> current gameState
      enterPlay = () <$ gate isOver (ffilter (== "Enter") keyE)
      escapeE = () <$ ffilter (== "Escape") keyE

  -- The Round Summary (Phase Over) and the Paused overlay (blur).
  overDyn <- holdUniqDyn (S.roundResult <$> gameState)
  panels <- dyn $ ffor overDyn \case
    Nothing -> pure never
    Just r -> summaryPanel r
  choice <- switchHold never panels
  pausedDyn <- holdUniqDyn (S.paused <$> gameState)
  dyn_ $ ffor pausedDyn \p -> when p $
    elAttr "div" ("class" =: "paused-overlay" <> "data-paused" =: "") (text "Paused, click or press any key to resume")
  let playAgain = leftmost [() <$ ffilter (== PlayAgain) choice, enterPlay]
      backToStart = () <$ ffilter (== BackToStart) choice

  -- A Kill or a Typo just happened: persist the Streak (and its Bonus).
  let progress = attachWithMaybe
        (\old new -> if new.kills > old.kills || new.typos > old.typos then Just (S.progressSave new) else Nothing)
        (current gameState) (updated gameState)

  -- The Running to Over transition, once per Round.
  let roundEndedE = attachWithMaybe S.roundEnded (current gameState) (updated gameState)

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
          a : _ -> valToText a >>= liftIO . fireKey
          [] -> pure ()
        _ <- jsg ("TypeWizardKeys" :: Text) # ("attach" :: Text) $ (raw', cb)
        startRenderLoop r (pullScene cell lastAspect fireTick fireAspect)
        when ("bench" `T.isInfixOf` search) runBench
        pure Nothing
  failure <- holdDyn Nothing started
  dyn_ $ ffor failure \case
    Nothing -> blank
    Just err -> elAttr "p" ("class" =: "game-error" <> "data-error" =: "renderer") (text err)
  pure GameOut { goSave = progress, goRoundEnded = roundEndedE, goLeave = leftmost [backToStart, escapeE] }

-- | What the key shim sends: @"Tab"@, one lowercase letter, @"Blur"@,
-- @"Focus"@, @"Click"@, or @"Enter"@, @"Escape"@, @"Other"@ (a key that is no
-- Keystroke).
keyInput :: Text -> S.Input
keyInput t = case T.unpack t of
  "Tab" -> S.Tab
  "Blur" -> S.Blur
  "Focus" -> S.Focus
  "Click" -> S.Click
  [c] -> S.Key c
  _ -> S.Key ' ' -- ignored by 'step' unless the Round is paused (any key resumes)

-- | The Round Summary: a DOM panel with the seven rows in order and the two
-- buttons. Each row is @tr[data-row=key]@ (points, total, wpm, accuracy,
-- kills, longest, streak) with its value in the @td@.
summaryPanel :: DomBuilder t m => RoundResult -> m (Event t Choice)
summaryPanel r = elAttr "div" ("class" =: "round-summary" <> "data-summary" =: "round") do
  el "h2" (text "Round over")
  el "table" $ el "tbody" $ for_ (summaryRows r) \(rowKey, label, cell) ->
    elAttr "tr" ("data-row" =: rowKey) do
      el "th" (text label)
      el "td" (text cell)
  elAttr "div" ("class" =: "actions") do
    again <- button "Play again"
    back <- button "Back to start"
    pure (leftmost [PlayAgain <$ again, BackToStart <$ back])

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
