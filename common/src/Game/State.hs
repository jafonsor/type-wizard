-- | The game's state and its one pure step (spec sections 4 and 7). No
-- renderer, no Reflex, no IO: 'step' takes the 'Settings' (read at 'Start'
-- only, where they are snapshotted), the word list, an 'Input' and the state,
-- and returns the next state. The random generator is a field, seeded by
-- 'Start', so a fixed seed gives a fixed game.
--
-- This slice holds spawning, movement, typing (spec section 4's table: Focus,
-- Typo, Lock, Tab, Kill) and scoring ('onTypo' and 'onKill', below).
--
-- /Scoring./ A Kill increments the Streak first, then pays @1 + floor
-- (Streak / group size)@ Points (group size is the Round's snapshot of the
-- @streakGroupSize@ setting; no cap). A Typo clears the Streak at once; Tab
-- and wrong letters while Locked do not touch it. 'streakBonus' and 'meterFill'
-- are derived from the Streak, so a Typo clears them with it. 'longestStreak'
-- counts only this Round's consecutive Kills (from 0 at 'Start', whatever
-- Streak was carried in). 'Start' carries the saved progress in (its Streak
-- and Total Points; the saved Bonus is ignored and re-derived). Points are
-- banked into 'totalPoints' only when the Round ends (see /Hits and Round end/).
--
-- /Typing./ Input is handled only while the Phase is Running. Only a-z
-- letters are Keystrokes ('Key' with anything else is ignored). The Focus is
-- one of 'NoFocus' (the table's Idle), 'Focused' or 'Locked', each carrying
-- the Enemy's id and the typed count k; a Tab or a Kill drops it (so the Word
-- is back at k = 0 and every Word shows default letters).
--
-- /Counters./ @correctKeys@ and @wrongKeys@ feed 'accuracy'; the correct
-- characters of 'wpm' are the correct Keystrokes (every correct Keystroke
-- types one character of a Word). 'roundTime' is the sum of the clamped Tick
-- steps, so a blur never counts as typing time.
--
-- /Hits and Round end./ After the Enemies move in a Tick, an Enemy touching
-- the Player (distance within 'contactDistance', plus rounding slack) with no
-- Grace Period active is a Hit: one Life lost, and a Grace Period of
-- @gracePeriod@ seconds starts. Several touching Enemies are still one Hit per
-- moment. 'graceStart' is the 'roundTime' at which the Grace began (Grace is
-- active while @roundTime < graceStart + gracePeriod@; Round time is the
-- clamped Tick sum, so it never counts a blur). When Grace ends and an Enemy
-- still touches, the next Hit comes at once and its Grace starts at the
-- scheduled end of the last one (not at the Tick that noticed it), so a parked
-- Enemy costs a Life every Grace Period without drift. A Hit never touches the
-- Streak and an Enemy is not removed by touching. At 0 Lives 'endRound' makes
-- the Phase 'Over': Focus and Lock drop, the Enemies are discarded with no
-- Points, 'totalPoints' becomes the banked value (carried-in plus Round
-- Points) and 'roundResult' holds the 'RoundResult'. Over ignores every
-- input but 'Start' (and 'Aspect'), so the counters, 'roundTime' and so WPM
-- and Accuracy are final. 'roundEnded' derives the one-shot result from a
-- Running to Over transition; 'bankRound' adds the Round Points to a 'Save'.
--
-- /Blur./ 'Blur' sets 'paused' (Running only): Ticks then only move
-- 'lastTime' forward (dt 0, no spawn, no movement, no Grace progress). 'Focus'
-- marks the window focused again; the next 'Key', 'Tab' or 'Click' while paused
-- and focused resumes and is swallowed (it is not a Keystroke). Anything
-- before 'Focus' is ignored. The scene builder's own clock is not paused.
--
-- /Spawn timing./ The wait before Enemy @k@ of a Tier (counting from 1) is
-- measured from the previous spawn (from 'Start' for the first Enemy of the
-- Round) and runs linearly from 'intervalStart' at @k = 1@ to 'intervalEnd'
-- at @k = enemiesPerTier@; later Enemies of the last Tier hold at
-- 'intervalEnd'. After 'enemiesPerTier' spawns the Tier advances (up to
-- 'lastTier') and the next Tier's ramp starts again at 'intervalStart'.
--
-- /Kill animations./ A Kill also appends one 'KillAnim' record (the Shot and
-- the Plus Signs of that Kill) to 'killAnims'. A record is a start time plus
-- the endpoints, durations and per-sign random parameters, all fixed at the
-- Kill; the scene builder evaluates and eases it at its own @Frame.time@. The
-- step only creates records (at a Kill) and drops expired ones (on a Tick).
--
-- /Time base./ The record's start is 'lastTime', the previous Tick's raw
-- timestamp: the same clock as the builder's @Frame.time@ (both are the rAF
-- timestamp in seconds; 'roundTime' is a different, clamped clock and is not
-- used). A Kill comes from a key event between two frames, so it starts up
-- to one frame early (0 before any Tick). Expiry compares the Tick's raw
-- timestamp with the record's end, in every Phase, so a blur (Ticks still
-- arrive and move 'lastTime'), the paused state and Round end ('Over') all
-- keep expiring records; 'Over' ignores everything else on a Tick. Records
-- survive 'endRound' and finish behind the Summary; only 'Start' (a new
-- Round) clears them.
--
-- /Camera./ The Camera is a start-time record too ('CameraAnim': start time,
-- start centre, target, time constant), in the same time base as the Kill
-- records (the raw rAF timestamp, 'lastTime'). The builder evaluates
-- @centre(t) = target + (start - target) * exp (-(t - t0) / tau)@ at its
-- @Frame.time@, so the Camera is never mutated per Tick. 'step' creates a new
-- record only when the /target/ changes, which happens only when the Focused
-- Enemy changes (Focus starts, a Kill, a Tab, Round end) and starts the new
-- record from the Camera's centre evaluated at 'lastTime', so a retarget in
-- the middle of a pan is continuous with the last frame drawn. The target of
-- a Focus is computed once, at the moment of Focus, from the Enemy's position
-- then ('cameraTarget'), and /held/ while the Word is typed (the Enemy
-- keeps moving toward the Player, which is inside the view, so it stays
-- visible: the segment from a visible point to the Player is inside the
-- rectangle). A Kill, a Tab or Round end ('Over' drops Focus) retarget to the
-- Player and the Camera eases back, behind the Summary too (Ticks in 'Over'
-- still arrive at the builder's clock). Like a Kill record, a retarget
-- starts up to one frame early (the key event is between two frames). 'Start'
-- resets the Camera to rest on the Player. The spawn ring does not read the
-- Camera.
--
-- /Hit and Streak feedback./ Two more start-time records on the same clock
-- ('lastTime'). 'hitAt' is the Tick clock of the latest Hit (the Tick that
-- noticed it, so a re-Hit at the scheduled Grace end is up to one frame late;
-- the fatal Hit sets it too). The builder evaluates 'playerAlphaAt' (blink:
-- full for 'blinkPeriod', dim for 'blinkPeriod', ..., full first, only while
-- 'graceActive' so it stops with the Grace Period, at Round end and in
-- 'Over'; while paused the Grace is frozen so the blink goes on) and
-- 'hitFlashAt' (0.3 at the Hit, linear to 0 over 'hitFlashTime', which
-- finishes behind the Summary). 'meterAnim' is one 'MeterAnim' record (the
-- latest Kill or Typo event; 'Nothing' at rest, where the meter is the static
-- 'meterFill' of the Streak). Its 'maFrom' is the 'MeterView' /displayed/ at
-- the event ('meterViewAt' at 'lastTime'), so back-to-back events continue
-- from what was on screen: Kill after Kill grows from the shown fill to the
-- new fill; any event during a group-completion flash or emptying starts from
-- the shown fill (the white drops); a Typo fades the label from its shown
-- scale and alpha. A Grow keeps a pop in progress, finishing it at the pop's
-- own speed. 'expire' drops 'hitAt' once its Grace and flash are over and
-- 'meterAnim' once it ends, so neither grows. 'groupCompletedAt' stays the
-- 'roundTime' record of the completing Kill; the builder uses the raw-clock
-- 'MeterKind' 'MeterComplete' record instead.
--
-- /Order inside a Tick./ Existing Enemies move first, then due Enemies spawn
-- at the ring, so an Enemy is on the ring exactly in the Tick it appears.
module Game.State
  ( Phase (..)
  , Vec2 (..)
  , Enemy (..)
  , GameState (..)
  , Rng (..)
  , Focus (..)
  , focusInfo
  , Input (..)
  , RoundResult (..)
  , Seed
  , initialState
  , step
    -- * Pieces the tests and the scene use
  , spawnInterval
  , spawnRingRadius
  , distanceToPlayer
  , spawnedIn
  , totalSpawned
  , accuracy
  , wpm
  , correctChars
  , focusedEnemy
    -- * Kill animations
  , KillAnim (..)
  , PlusSign (..)
  , killAnimEnd
  , shotArrival
  , signFlyStart
  , signEnd
  , activeShots
  , activePlusSigns
    -- * Camera
  , CameraAnim (..)
  , cameraTarget
  , cameraCentreAt
  , cameraNow
  , restingCamera
    -- * Hit and Streak feedback
  , MeterKind (..)
  , MeterView (..)
  , LabelView (..)
  , MeterAnim (..)
  , meterViewAt
  , meterAnimEnd
  , playerAlphaAt
  , hitFlashAt
    -- * Scoring
  , streakBonus
  , meterFill
  , progressSave
    -- * Hits and Round end
  , graceActive
  , graceRemaining
  , roundEnded
  , bankRound
  ) where

import Control.Applicative ((<|>))
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Set qualified as Set
import Data.List (minimumBy)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Bits (xor)
import Data.Maybe (fromMaybe, isNothing)
import Data.Word (Word64)
import System.Random.SplitMix (SMGen, mkSMGen, nextDouble, unseedSMGen)

import Game.Layout
  ( blinkDimAlpha, blinkPeriod, contactDistance, defaultAspect, hitFlashAlpha, hitFlashTime
  , labelPopScale, labelPopTime, meterEmptyTime, meterFlashTime, meterGrowTime, plusMaxDelay
  , typoFadeTime )
import Game.Save (Save)
import Game.Save qualified as Save
import Game.Settings (Settings (..), defaultSettings)
import Game.Words (Bag, Words, bucket, drawWord, emptyBag)

type Seed = Word64

-- | The generator, comparable (splitmix's own has no 'Eq'): two are equal when
-- they are at the same point of the same stream.
newtype Rng = Rng { unRng :: SMGen }
  deriving stock (Show)

instance Eq Rng where
  Rng a == Rng b = unseedSMGen a == unseedSMGen b

data Phase = Idle | Running | Over
  deriving stock (Eq, Show)

data Vec2 = Vec2 { vx :: Double, vy :: Double }
  deriving stock (Eq, Show)

-- | An Enemy. @enemyId@ is its place in the spawn order (0, 1, 2, ... over the
-- Round), which is also the tie-break for Focus later.
data Enemy = Enemy
  { enemyId :: Int
  , enemyPos :: Vec2
  , enemyWord :: Text
  , enemyTier :: Int
  }
  deriving stock (Eq, Show)

-- | Who is being typed (the table's Idle, Focused and Locked). k is the number
-- of letters typed; the expected letter is Word index k.
data Focus
  = NoFocus
  | Focused Int Int -- ^ Enemy id, k
  | Locked Int Int -- ^ Enemy id, k (the letter expected next is Word index k)
  deriving stock (Eq, Show)

-- | The Enemy id and the typed count k, when there is a Focus.
focusInfo :: Focus -> Maybe (Int, Int)
focusInfo = \case
  NoFocus -> Nothing
  Focused i k -> Just (i, k)
  Locked i k -> Just (i, k)

data GameState = GameState
  { phase :: Phase
  , roundSettings :: Settings -- ^ snapshot taken at 'Start'
  , enemies :: [Enemy] -- ^ in spawn order
  , spawnCounts :: IntMap Int -- ^ Enemies spawned so far, per Tier
  , nextEnemyId :: Int
  , currentTier :: Int
  , sinceSpawn :: Double -- ^ seconds since the last spawn (or since 'Start')
  , bags :: IntMap Bag -- ^ one Word bag per Tier, made on first use
  , rng :: Rng
  , playerPos :: Vec2 -- ^ the Player does not move
  , lastTime :: Maybe Double -- ^ the previous Tick's time; 'Nothing' until the first
  , viewAspect :: Double -- ^ width over height of the view, from 'Aspect'
  , focus :: Focus
  , correctKeys :: Int -- ^ correct Keystrokes this Round
  , wrongKeys :: Int -- ^ Focused Typos plus wrong letters while Locked
  , typos :: Int -- ^ Typos this Round (not the wrong letters while Locked)
  , kills :: Int
  , streak :: Int -- ^ consecutive Kills, carried in at 'Start'; a Typo clears it
  , roundPoints :: Int -- ^ Points earned this Round
  , runKills :: Int -- ^ consecutive Kills this Round (0 at 'Start', cleared by a Typo)
  , longestStreak :: Int -- ^ the longest 'runKills' this Round
  , totalPoints :: Int -- ^ Total Points as carried in at 'Start' (plus the Round Points once the Round is Over)
  , groupCompletedAt :: Maybe Double
    -- ^ 'roundTime' of the latest Kill that completed a group (the meter then
    -- reads empty again: full-then-clears). A Typo clears it. The animation
    -- reads it; the state itself only records it.
  , roundTime :: Double -- ^ seconds of Round time (sum of the clamped Tick steps)
  , firstKeyAt :: Maybe Double -- ^ 'roundTime' at the first Keystroke
  , lives :: Int -- ^ Lives left; the Round's @startingLives@ at 'Start'
  , graceStart :: Maybe Double -- ^ 'roundTime' at which the running Grace Period began
  , paused :: Bool -- ^ the window lost focus; the Round logic is frozen
  , windowFocused :: Bool -- ^ the window has focus (after a 'Blur', until 'Focus')
  , roundResult :: Maybe RoundResult -- ^ set when the Round ends ('Over')
  , killAnims :: [KillAnim] -- ^ the Shots and Plus Signs in flight, oldest first
  , camera :: CameraAnim -- ^ the Camera's current easing record
  , hitAt :: Maybe Double
    -- ^ the Tick clock at the latest Hit (start-time record of the Hit feedback:
    -- the Player's blink and the red flash are evaluated from it)
  , meterAnim :: Maybe MeterAnim
    -- ^ the Streak Meter's current animation record (see /Hit and Streak feedback/)
  , animRng :: Rng
    -- ^ the generator for the Plus Signs' random parameters, derived from the
    -- Round's seed; separate from 'rng' so animations never change the Words
    -- or spawn angles of a seed
  }
  deriving stock (Eq, Show)

-- | The animations of one Kill (spec sections 6 and 9): a Shot from the Player
-- to the Enemy's position, then, when it arrives, the Plus Signs. Everything
-- is fixed at the Kill; only the builder's clock moves.
data KillAnim = KillAnim
  { kaStart :: Double -- ^ the Tick clock (@Frame.time@ base) at the Kill
  , kaFrom :: Vec2 -- ^ the Player's centre
  , kaTo :: Vec2 -- ^ the Enemy's position at the Kill
  , kaTier :: Int -- ^ the Enemy's Tier (colour of the dying square drawn until the Shot arrives)
  , kaStreak :: Int -- ^ the Streak /after/ the Kill: the Shot colour and the Plus Signs' colour
  , kaPoints :: Int -- ^ the Points paid (1 + Bonus), which may exceed the signs drawn
  , kaShotDur :: Double
  , kaHold :: Double
  , kaFly :: Double -- ^ the three durations, from the Round's settings snapshot
  , kaSigns :: [PlusSign] -- ^ one per Point, at most @plusDrawCap@
  }
  deriving stock (Eq, Show)

-- | One Plus Sign: where it starts around the Enemy and how long it waits
-- after its hold before flying.
data PlusSign = PlusSign
  { psOffset :: Vec2
  , psDelay :: Double
  }
  deriving stock (Eq, Show)

-- | When the Shot arrives: the Enemy square goes and the Plus Signs appear.
shotArrival :: KillAnim -> Double
shotArrival k = k.kaStart + k.kaShotDur

-- | When a sign leaves its hold and starts to fly.
signFlyStart :: KillAnim -> PlusSign -> Double
signFlyStart k p = shotArrival k + k.kaHold + p.psDelay

-- | When a sign reaches the Player and is removed.
signEnd :: KillAnim -> PlusSign -> Double
signEnd k p = signFlyStart k p + k.kaFly

-- | When the whole record is over: its last sign has reached the Player (the
-- Shot's own end if there are no signs).
killAnimEnd :: KillAnim -> Double
killAnimEnd k = maximum (shotArrival k : map (signEnd k) k.kaSigns)

-- | Shots in flight at a time (the Dev hook's count).
activeShots :: Double -> GameState -> Int
activeShots t st = length [ () | k <- st.killAnims, t < shotArrival k ]

-- | Plus Signs on show at a time (arrived, not yet at the Player).
activePlusSigns :: Double -> GameState -> Int
activePlusSigns t st = length [ () | k <- st.killAnims, p <- k.kaSigns, t >= shotArrival k, t < signEnd k p ]

-- | What a finished Round reports (the Round Summary's rows and the payload
-- of @RoundEnded@). 'resTotalPoints' is the Total Points after banking.
data RoundResult = RoundResult
  { resPoints :: Int
  , resTotalPoints :: Int
  , resWpm :: Double
  , resAccuracy :: Double
  , resKills :: Int
  , resLongestStreak :: Int
  , resStreak :: Int
  }
  deriving stock (Eq, Show)

data Input
  = Key Char -- ^ a lowercase a-z Keystroke (the JS shim filters; anything else is ignored)
  | Tab -- ^ clears Focus and Lock
  | Tick Double -- ^ the frame time in seconds (the rAF clock)
  | Start Seed Save
    -- ^ the seed, and the saved progress carried in: the Streak (the Bonus
    -- and the meter follow from it) and the Total Points. The page reads it
    -- from the app's @Dynamic Save@ when it fires this.
  | Aspect Double
    -- ^ the view's width over height; the spawn ring depends on it. It is an
    -- input (not carried by 'Tick') so 'Tick' keeps the spec's shape, and it
    -- survives 'Start'. Until one arrives the state assumes 16:9.
  | Blur -- ^ the window lost focus: freeze the Round
  | Focus -- ^ the window has focus again (it does not resume by itself)
  | Click -- ^ a pointer press; resumes a paused Round that has its focus back
  deriving stock (Eq, Show)

-- | Before the first 'Start'.
initialState :: GameState
initialState = GameState
  { phase = Idle
  , roundSettings = defaultSettings
  , enemies = []
  , spawnCounts = IntMap.empty
  , nextEnemyId = 0
  , currentTier = defaultSettings.firstTier
  , sinceSpawn = 0
  , bags = IntMap.empty
  , rng = Rng (mkSMGen 0)
  , playerPos = Vec2 0 0
  , lastTime = Nothing
  , viewAspect = defaultAspect
  , focus = NoFocus
  , correctKeys = 0
  , wrongKeys = 0
  , typos = 0
  , kills = 0
  , streak = 0
  , roundPoints = 0
  , runKills = 0
  , longestStreak = 0
  , totalPoints = 0
  , groupCompletedAt = Nothing
  , roundTime = 0
  , firstKeyAt = Nothing
  , lives = defaultSettings.startingLives
  , graceStart = Nothing
  , paused = False
  , windowFocused = True
  , roundResult = Nothing
  , killAnims = []
  , camera = restingCamera defaultSettings.cameraTimeConstant (Vec2 0 0)
  , hitAt = Nothing
  , meterAnim = Nothing
  , animRng = Rng (mkSMGen 0)
  }

-- | One input. The rules are 'stepRules'; afterwards the Camera is retargeted
-- if the Focused Enemy changed (see /Camera/ above).
step :: Settings -> Words -> Input -> GameState -> GameState
step settings ws input st = retarget st (stepRules settings ws input st)

stepRules :: Settings -> Words -> Input -> GameState -> GameState
stepRules settings ws input st = case input of
  Start seed carried -> startRound settings seed carried st
  Tick now | st.phase == Running, st.paused -> expire now st { lastTime = Just now }
  Tick now | st.phase == Running -> expire now (tick ws now st)
  Tick now | st.phase == Over -> expire now st -- finish the animations behind the Summary, nothing else
  Key _ | st.phase == Running, st.paused -> wake st
  Tab | st.phase == Running, st.paused -> wake st
  Click | st.phase == Running, st.paused -> wake st
  Key c | st.phase == Running, c >= 'a' && c <= 'z' -> keystroke c st
  Tab | st.phase == Running -> st { focus = NoFocus }
  Blur | st.phase == Running -> st { paused = True, windowFocused = False }
  Focus -> st { windowFocused = True }
  Aspect a | a > 0 && not (isInfinite a) -> st { viewAspect = a }
  _ -> st

-- | Round start (spec section 4): first Tier, empty field, counters 0. The
-- view aspect carries over.
startRound :: Settings -> Seed -> Save -> GameState -> GameState
startRound settings seed carried st = initialState
  { phase = Running
  , streak = max 0 carried.streak
  , totalPoints = max 0 carried.totalPoints
  , roundSettings = settings
  , currentTier = settings.firstTier
  , lives = max 1 settings.startingLives
  , rng = Rng (mkSMGen seed)
  , animRng = Rng (mkSMGen (seed `xor` 0x9e3779b97f4a7c15))
  , viewAspect = st.viewAspect
  , camera = restingCamera settings.cameraTimeConstant (Vec2 0 0)
  }

-- Camera ----------------------------------------------------------------------

-- | The Camera's easing record: from 'caFrom' at 'caStart' (the Tick clock)
-- toward 'caTarget' with time constant 'caTau' (a snapshot of the Round's setting).
data CameraAnim = CameraAnim
  { caStart :: Double
  , caFrom :: Vec2
  , caTarget :: Vec2
  , caTau :: Double
  }
  deriving stock (Eq, Show)

-- | A Camera at rest on a point.
restingCamera :: Double -> Vec2 -> CameraAnim
restingCamera tau p = CameraAnim { caStart = 0, caFrom = p, caTarget = p, caTau = tau }

-- | The Camera centre at time t: exponential smoothing,
-- @target + (from - target) * exp (-(t - start) / tau)@; before the start it is
-- the start centre, and with a time constant of 0 or less it is the target.
cameraCentreAt :: Double -> CameraAnim -> Vec2
cameraCentreAt t c
  | c.caTau <= 0 = c.caTarget
  | otherwise = Vec2 (mix c.caFrom.vx c.caTarget.vx) (mix c.caFrom.vy c.caTarget.vy)
  where
    k = exp (negate (max 0 (t - c.caStart)) / c.caTau)
    mix a b = b + (a - b) * k

-- | The Camera centre as of the last Tick ('Nothing' time reads as 0): where the
-- last frame drawn had it.
cameraNow :: GameState -> Vec2
cameraNow st = cameraCentreAt (fromMaybe 0 st.lastTime) st.camera

-- | Where the Camera should rest for an Enemy at a position (spec section 9).
-- The default view is the Camera centred on the Player: half-height
-- @worldHeight / 2@, half-width that times the aspect. An Enemy inside it
-- leaves the target on the Player. Outside it, each axis is shifted by the
-- smallest amount that puts the Enemy inside the visible rectangle inset by
-- @cameraInset@ (an axis already inside the inset is not shifted), then the
-- shift is clamped per axis so the Player stays at least @playerMargin@ from
-- every edge (the margin wins over the inset when they conflict; the Enemy
-- may then stay outside its inset, or even off the screen for a very far one).
cameraTarget :: Settings -> Double -> Vec2 -> Vec2 -> Vec2
cameraTarget cfg aspect player p
  | abs dx <= hw && abs dy <= hh = player
  | otherwise = Vec2 (player.vx + axis hw dx) (player.vy + axis hh dy)
  where
    hh = cfg.worldHeight / 2
    hw = hh * aspect
    dx = p.vx - player.vx
    dy = p.vy - player.vy
    axis half d = max (negate lim) (min lim (signum d * max 0 (abs d - max 0 (half - cfg.cameraInset))))
      where lim = max 0 (half - cfg.playerMargin)

-- | After an input: when the Focused Enemy (its id, not the typed count)
-- differs from the one before, point the Camera at the new target, starting
-- from where it is now. No change of Focus, no new record.
retarget :: GameState -> GameState -> GameState
retarget old new
  | focusId old /= focusId new && target /= new.camera.caTarget = new { camera = anim }
  | otherwise = new
  where
    focusId = fmap fst . focusInfo . (.focus)
    cfg = new.roundSettings
    target = case focusedEnemy new of
      Just e -> cameraTarget cfg new.viewAspect new.playerPos e.enemyPos
      Nothing -> new.playerPos
    -- a Start has just reset the record, so evaluating the old one is moot there
    t0 = fromMaybe 0 new.lastTime
    anim = CameraAnim
      { caStart = t0
      , caFrom = cameraCentreAt t0 new.camera
      , caTarget = target
      , caTau = cfg.cameraTimeConstant
      }

-- | Drops the records that are over at this Tick's timestamp.
expire :: Double -> GameState -> GameState
expire now st = st
  { killAnims = filter ((> now) . killAnimEnd) st.killAnims
  , hitAt = case st.hitAt of
      Just h | graceActive st || now < h + hitFlashTime -> Just h
      _ -> Nothing
  , meterAnim = case st.meterAnim of
      Just a | now < meterAnimEnd a -> Just a
      _ -> Nothing
  }

-- | A 'Key', 'Tab' or 'Click' while paused: resumes if the window has its focus
-- back; either way the input is swallowed (never a Keystroke).
wake :: GameState -> GameState
wake st = if st.windowFocused then st { paused = False } else st

tick :: Words -> Double -> GameState -> GameState
tick ws now st = case resolveHit st' of
  hit | hit.phase == Running -> spawnDue ws hit
      | otherwise -> hit
  where
    cfg = st.roundSettings
    dt = case st.lastTime of
      Nothing -> 0
      Just prev -> max 0 (min cfg.maxTickDt (now - prev))
    st' = st
      { lastTime = Just now
      , roundTime = st.roundTime + dt
      , sinceSpawn = st.sinceSpawn + dt
      , enemies = map (advance cfg dt st.playerPos) st.enemies
      }

-- Hits and Round end ----------------------------------------------------------

-- | Is an Enemy touching the Player? (Parked Enemies sit at 'contactDistance'
-- up to rounding.)
touching :: GameState -> Enemy -> Bool
touching st e = distanceToPlayer st e <= contactDistance + 1e-6

-- | The Grace Period is running.
graceActive :: GameState -> Bool
graceActive st = case st.graceStart of
  Just t0 -> st.roundTime < t0 + st.roundSettings.gracePeriod
  Nothing -> False

-- | Seconds of Grace left, 'Nothing' when none is running.
graceRemaining :: GameState -> Maybe Double
graceRemaining st = case st.graceStart of
  Just t0 | graceActive st -> Just (t0 + st.roundSettings.gracePeriod - st.roundTime)
  _ -> Nothing

-- | The Hit rule, once per Tick after movement: an ended Grace is cleared,
-- then, with no Grace running, any touching Enemy is one Hit.
resolveHit :: GameState -> GameState
resolveHit st = case st.graceStart of
  Just t0
    | graceActive st -> st
    | otherwise -> hitIfTouching (t0 + st.roundSettings.gracePeriod) st { graceStart = Nothing }
  Nothing -> hitIfTouching st.roundTime st

-- | One Life lost (however many Enemies touch) and a Grace Period starting at
-- the given Round time; the last Life ends the Round.
hitIfTouching :: Double -> GameState -> GameState
hitIfTouching startAt st
  | not (any (touching st) st.enemies) = st
  | st.lives <= 1 = endRound st { lives = 0, hitAt = st.lastTime }
  | otherwise = st { lives = st.lives - 1, graceStart = Just startAt, hitAt = st.lastTime }

-- | Lives are 0: Over. Focus and Lock drop, the Enemies are discarded with no
-- Points, the Round Points are banked into 'totalPoints' and the result is kept.
endRound :: GameState -> GameState
endRound st = st
  { phase = Over
  , focus = NoFocus
  , enemies = []
  , graceStart = Nothing
  , paused = False
  , totalPoints = banked
  , roundResult = Just RoundResult
      { resPoints = st.roundPoints
      , resTotalPoints = banked
      , resWpm = wpm st
      , resAccuracy = accuracy st
      , resKills = st.kills
      , resLongestStreak = st.longestStreak
      , resStreak = st.streak
      }
  }
  where
    banked = st.totalPoints + st.roundPoints

-- | The 'RoundResult' of a Running to Over transition (old state, new state)
-- and nothing for any other pair, so a state re-emitted while Over cannot end
-- the Round (or bank) twice.
roundEnded :: GameState -> GameState -> Maybe RoundResult
roundEnded old new
  | old.phase == Running, new.phase == Over = new.roundResult
  | otherwise = Nothing

-- | Banking: the Round Points join the saved Total Points. The Streak and
-- Bonus are already saved per Kill or Typo.
bankRound :: RoundResult -> Save -> Save
bankRound r sv = sv { Save.totalPoints = sv.totalPoints + r.resPoints }

-- | Moves an Enemy toward the Player by @enemySpeed * dt@, stopping at
-- 'contactDistance' (an Enemy at or inside it stays put).
advance :: Settings -> Double -> Vec2 -> Enemy -> Enemy
advance cfg dt player e
  | d <= contactDistance = e
  | otherwise = e { enemyPos = Vec2 (player.vx + dx * k) (player.vy + dy * k) }
  where
    dx = e.enemyPos.vx - player.vx
    dy = e.enemyPos.vy - player.vy
    d = sqrt (dx * dx + dy * dy)
    d' = max contactDistance (d - cfg.enemySpeed * dt)
    k = d' / d

distanceToPlayer :: GameState -> Enemy -> Double
distanceToPlayer st e = sqrt (dx * dx + dy * dy)
  where
    dx = e.enemyPos.vx - st.playerPos.vx
    dy = e.enemyPos.vy - st.playerPos.vy

-- | Spawns every Enemy that is due. A Tick is at most @maxTickDt@ long and an
-- interval at least 0.2 s, so this rarely loops; it stops at the first spawn
-- that cannot be made (no Word available), leaving the time owed.
spawnDue :: Words -> GameState -> GameState
spawnDue ws st
  | st.sinceSpawn < wait = st
  | otherwise = case spawnOne ws st of
      Nothing -> st
      Just st' -> spawnDue ws st' { sinceSpawn = st.sinceSpawn - wait }
  where
    wait = spawnInterval st.roundSettings (spawnedIn st st.currentTier + 1)

-- | The wait before Enemy @k@ (from 1) of a Tier.
spawnInterval :: Settings -> Int -> Double
spawnInterval cfg k
  | n <= 1 = cfg.intervalStart
  | otherwise = cfg.intervalStart + (cfg.intervalEnd - cfg.intervalStart) * (fromIntegral (min k n - 1) / fromIntegral (n - 1))
  where
    n = cfg.enemiesPerTier

-- | Half the diagonal of the view (world height, current aspect) plus
-- @spawnRadius@: the distance from the Player at which Enemies appear.
spawnRingRadius :: Settings -> Double -> Double
spawnRingRadius cfg aspect = sqrt (w * w + h * h) / 2 + cfg.spawnRadius
  where
    h = cfg.worldHeight
    w = h * aspect

-- | Draws a Word and an angle, adds the Enemy and advances the Tier counters.
-- 'Nothing' when no Word can be drawn.
spawnOne :: Words -> GameState -> Maybe GameState
spawnOne ws st = do
  let cfg = st.roundSettings
      tier = st.currentTier
      onScreen = Set.fromList (map (.enemyWord) st.enemies)
      bag = IntMap.findWithDefault emptyBag tier st.bags
  (word, bag', g1) <- drawWord cfg.wordLookahead (bucket ws tier) onScreen bag (unRng st.rng)
  let (u, g2) = nextDouble g1
      angle = 2 * pi * u
      r = spawnRingRadius cfg st.viewAspect
      enemy = Enemy
        { enemyId = st.nextEnemyId
        , enemyPos = Vec2 (st.playerPos.vx + r * cos angle) (st.playerPos.vy + r * sin angle)
        , enemyWord = word
        , enemyTier = tier
        }
      count = spawnedIn st tier + 1
      tier' = if count >= cfg.enemiesPerTier && tier < cfg.lastTier then tier + 1 else tier
  pure st
    { enemies = st.enemies <> [enemy]
    , spawnCounts = IntMap.insert tier count st.spawnCounts
    , nextEnemyId = st.nextEnemyId + 1
    , currentTier = tier'
    , bags = IntMap.insert tier bag' st.bags
    , rng = Rng g2
    }

-- | Enemies spawned so far in a Tier.
spawnedIn :: GameState -> Int -> Int
spawnedIn st tier = IntMap.findWithDefault 0 tier st.spawnCounts

totalSpawned :: GameState -> Int
totalSpawned = sum . IntMap.elems . (.spawnCounts)

-- Typing ----------------------------------------------------------------------

-- | The Enemy being typed, if any.
focusedEnemy :: GameState -> Maybe Enemy
focusedEnemy st = focusInfo st.focus >>= \(i, _) -> findEnemy i st

findEnemy :: Int -> GameState -> Maybe Enemy
findEnemy i st = case filter ((== i) . (.enemyId)) st.enemies of
  e : _ -> Just e
  [] -> Nothing

-- | One a-z Keystroke, by the table of spec section 4.
keystroke :: Char -> GameState -> GameState
keystroke c st = case st.focus of
  NoFocus -> case closestMatching c st of
    Nothing -> st -- matches no Word: not a Keystroke, not a Typo
    Just e -> advanceWord e 1 (correct st)
  Focused i k -> withEnemy i \e ->
    if expected e k == c then advanceWord e (k + 1) (correct st) else onTypo i k (wrong st)
  Locked i k -> withEnemy i \e ->
    if expected e k == c then advanceWord e (k + 1) (correct st) else wrong st
  where
    -- A Focus on an Enemy that is gone cannot happen (only a Kill removes an
    -- Enemy, and it drops the Focus); if it ever did, drop it.
    withEnemy i f = maybe st { focus = NoFocus } f (findEnemy i st)

expected :: Enemy -> Int -> Char
expected e k = T.index e.enemyWord k

-- | The Enemy whose Word starts with the letter and whose centre is nearest
-- the Player; a tie goes to the earlier spawn (the smaller id). Distances
-- are compared to a millionth of a unit: parked Enemies sit at 'contactDistance'
-- up to rounding, and that is a tie, not a win for whichever rounded lower.
closestMatching :: Char -> GameState -> Maybe Enemy
closestMatching c st = case filter ((== Just c) . fmap fst . T.uncons . (.enemyWord)) st.enemies of
  [] -> Nothing
  es -> Just (minimumBy (comparing (\e -> (round (distanceToPlayer st e * 1e6) :: Int, e.enemyId))) es)

-- | k letters of the Enemy's Word are typed: at the Word's length it is a
-- Kill, otherwise it is Focused.
advanceWord :: Enemy -> Int -> GameState -> GameState
advanceWord e k st
  | k >= T.length e.enemyWord = onKill e st
  | otherwise = st { focus = Focused e.enemyId k }

-- | The Kill: the Enemy goes, the Focus drops, the Streak goes up by one and
-- /then/ the Kill pays @1 + floor (new Streak / group size)@ Points.
onKill :: Enemy -> GameState -> GameState
onKill e st = st
  { enemies = filter ((/= e.enemyId) . (.enemyId)) st.enemies
  , focus = NoFocus
  , kills = st.kills + 1
  , streak = streak'
  , roundPoints = st.roundPoints + points
  , runKills = run
  , longestStreak = max st.longestStreak run
  , groupCompletedAt = if streak' `mod` size == 0 then Just st.roundTime else st.groupCompletedAt
  , killAnims = st.killAnims <> [anim]
  , animRng = Rng g'
  , meterAnim = Just MeterAnim
      { maStart = t0
      , maKind = if streak' `mod` size == 0 then MeterComplete else MeterGrow
      , maFrom = meterViewAt st t0
      , maStreak = streak'
      }
  }
  where
    t0 = fromMaybe 0 st.lastTime
    size = groupSize st
    streak' = st.streak + 1
    points = 1 + streak' `div` size
    run = st.runKills + 1
    cfg = st.roundSettings
    (signs, g') = drawSigns cfg.plusSpreadRadius (min points (max 0 cfg.plusDrawCap)) (unRng st.animRng)
    anim = KillAnim
      { kaStart = fromMaybe 0 st.lastTime
      , kaFrom = st.playerPos
      , kaTo = e.enemyPos
      , kaTier = e.enemyTier
      , kaStreak = streak'
      , kaPoints = points
      , kaShotDur = cfg.shotDuration
      , kaHold = cfg.plusHold
      , kaFly = cfg.plusFlyDuration
      , kaSigns = signs
      }

-- | n signs: an offset uniform in the disc of the spread radius and a delay
-- uniform in 0 to 'plusMaxDelay', three draws each.
drawSigns :: Double -> Int -> SMGen -> ([PlusSign], SMGen)
drawSigns radius n g0 = go n g0 []
  where
    go 0 g acc = (reverse acc, g)
    go i g acc =
      let (a, g1) = nextDouble g
          (b, g2) = nextDouble g1
          (c, g3) = nextDouble g2
          r = radius * sqrt b
          ang = 2 * pi * a
      in go (i - 1 :: Int) g3 (PlusSign (Vec2 (r * cos ang) (r * sin ang)) (c * plusMaxDelay) : acc)

-- | A Typo at letter k of Enemy i: the Word locks, expecting the same letter,
-- and the Streak (so the Bonus and the meter) clears at once. 'longestStreak'
-- keeps the best run so far.
onTypo :: Int -> Int -> GameState -> GameState
onTypo i k st = st
  { focus = Locked i k
  , typos = st.typos + 1
  , streak = 0
  , runKills = 0
  , groupCompletedAt = Nothing
  , meterAnim = if shown.mvFill <= 0 && not shown.mvWhite && isNothing shown.mvLabel
      then Nothing
      else Just MeterAnim { maStart = t0, maKind = MeterTypo, maFrom = shown, maStreak = 0 }
  }
  where
    t0 = fromMaybe 0 st.lastTime
    shown = meterViewAt st t0

-- Hit and Streak feedback ------------------------------------------------------

-- | What a 'MeterAnim' does.
data MeterKind
  = MeterGrow -- ^ a Kill: the fill moves to the new fill over 'meterGrowTime'
  | MeterComplete -- ^ a group-completing Kill: full and white, then empties; the label pops
  | MeterTypo -- ^ a Typo: the bar empties and the label fades over 'typoFadeTime'
  deriving stock (Eq, Show)

-- | The "+N" label as drawn: its Bonus, scale (1 at rest) and alpha (1 at rest).
data LabelView = LabelView { lvBonus :: Int, lvScale :: Double, lvAlpha :: Double }
  deriving stock (Eq, Show)

-- | The Streak Meter as drawn at one time: the fill (0 to 1; 1 only during a
-- completion's flash and the start of its emptying), whether the bar is white,
-- the Streak whose 'Game.Scene.shotColour' colours it, and the label (hidden
-- at Bonus 0).
data MeterView = MeterView
  { mvFill :: Double
  , mvWhite :: Bool
  , mvStreak :: Int
  , mvLabel :: Maybe LabelView
  }
  deriving stock (Eq, Show)

-- | The meter's animation record: the event, its time, the view shown at that
-- moment, and the Streak after it.
data MeterAnim = MeterAnim
  { maStart :: Double
  , maKind :: MeterKind
  , maFrom :: MeterView
  , maStreak :: Int
  }
  deriving stock (Eq, Show)

-- | The meter at rest: the static view of the state's Streak.
restView :: GameState -> MeterView
restView st = MeterView
  { mvFill = meterFill st
  , mvWhite = False
  , mvStreak = st.streak
  , mvLabel = if streakBonus st >= 1 then Just (LabelView (streakBonus st) 1 1) else Nothing
  }

-- | How long a Grow keeps going: the fill, or a pop it inherited, whichever is longer.
meterAnimEnd :: MeterAnim -> Double
meterAnimEnd a = a.maStart + case a.maKind of
  MeterGrow -> max meterGrowTime (popRemaining a.maFrom)
  MeterComplete -> max labelPopTime (meterFlashTime + meterEmptyTime)
  MeterTypo -> typoFadeTime

-- | Time for a label at its shown scale to settle to 1 at the pop's own speed.
popRemaining :: MeterView -> Double
popRemaining v = case v.mvLabel of
  Just l -> max 0 (l.lvScale - 1) * labelPopTime / (labelPopScale - 1)
  Nothing -> 0

-- | The meter evaluated at time t (the builder's clock, 'lastTime' base): the
-- record's animation, or the rest view when there is none or it is over. All
-- ramps are linear.
meterViewAt :: GameState -> Double -> MeterView
meterViewAt st t = case st.meterAnim of
  Just a | t < meterAnimEnd a -> animView st a (max 0 (t - a.maStart))
  _ -> restView st

animView :: GameState -> MeterAnim -> Double -> MeterView
animView st a u = case a.maKind of
  MeterGrow -> MeterView
    { mvFill = a.maFrom.mvFill + (target - a.maFrom.mvFill) * ramp meterGrowTime
    , mvWhite = False
    , mvStreak = a.maStreak
    , mvLabel = if bonus >= 1
        then Just (LabelView bonus (max 1 (maybe 1 (.lvScale) a.maFrom.mvLabel - u * (labelPopScale - 1) / labelPopTime)) 1)
        else Nothing
    }
  MeterComplete -> MeterView
    { mvFill = if u < meterFlashTime then 1 else 1 - clamp01' ((u - meterFlashTime) / meterEmptyTime)
    , mvWhite = u < meterFlashTime
    , mvStreak = a.maStreak
    , mvLabel = Just (LabelView bonus (labelPopScale + (1 - labelPopScale) * ramp labelPopTime) 1)
    }
  MeterTypo -> MeterView
    { mvFill = a.maFrom.mvFill * (1 - ramp typoFadeTime)
    , mvWhite = False
    , mvStreak = a.maFrom.mvStreak
    , mvLabel = fmap (\l -> l { lvAlpha = l.lvAlpha * (1 - ramp typoFadeTime) }) a.maFrom.mvLabel
    }
  where
    size = groupSize st
    bonus = a.maStreak `div` size
    target = fromIntegral (a.maStreak `mod` size) / fromIntegral size
    ramp d = clamp01' (u / d)

clamp01' :: Double -> Double
clamp01' = max 0 . min 1

-- | The Player's opacity at time t: 'blinkDimAlpha' on the odd 'blinkPeriod's
-- after the latest Hit while the Grace Period lasts, else 1.
playerAlphaAt :: GameState -> Double -> Double
playerAlphaAt st t = case st.hitAt of
  Just h | graceActive st, t >= h, odd (floor ((t - h) / blinkPeriod) :: Int) -> blinkDimAlpha
  _ -> 1

-- | The red full-screen overlay's alpha at time t: 'hitFlashAlpha' at the
-- latest Hit, linear to 0 over 'hitFlashTime', 0 before and after.
hitFlashAt :: GameState -> Double -> Double
hitFlashAt st t = case st.hitAt of
  Just h | t >= h, t < h + hitFlashTime -> hitFlashAlpha * (1 - (t - h) / hitFlashTime)
  _ -> 0

-- | The Round's group size (at least 1, so a hand-made state cannot divide by 0).
groupSize :: GameState -> Int
groupSize st = max 1 st.roundSettings.streakGroupSize

-- | Bonus: the completed groups of the Streak, @floor (Streak / group size)@.
streakBonus :: GameState -> Int
streakBonus st = st.streak `div` groupSize st

-- | The Streak Meter's fill, 0 up to (not including) 1: progress through the
-- current group, @(Streak mod group size) / group size@. A Kill that completes
-- a group leaves 0 (see 'groupCompletedAt' for the full-then-clears moment).
meterFill :: GameState -> Double
meterFill st = fromIntegral (st.streak `mod` groupSize st) / fromIntegral (groupSize st)

-- | The saved progress after the state's latest change: the Streak and its
-- Bonus (derived with the Round's group size, so the stored pair is
-- consistent), the Total Points left as they were.
progressSave :: GameState -> Save -> Save
progressSave st sv = sv { Save.streak = st.streak, Save.bonus = streakBonus st }

correct, wrong :: GameState -> GameState
correct st = (stamp st) { correctKeys = st.correctKeys + 1 }
wrong st = (stamp st) { wrongKeys = st.wrongKeys + 1 }

-- | Notes the Round time of the first Keystroke.
stamp :: GameState -> GameState
stamp st = st { firstKeyAt = st.firstKeyAt <|> Just st.roundTime }

-- | Accuracy in percent: correct / (correct + wrong) Keystrokes, 100 when
-- there are none.
accuracy :: GameState -> Double
accuracy st
  | total == 0 = 100
  | otherwise = 100 * fromIntegral st.correctKeys / fromIntegral total
  where
    total = st.correctKeys + st.wrongKeys

-- | Correct characters typed: one per correct Keystroke.
correctChars :: GameState -> Int
correctChars = (.correctKeys)

-- | Words per minute: (correct characters / 5) over the minutes from the
-- first Keystroke to now (the last Tick; Round end freezes it, as no Tick
-- advances an Over state). 0 before there is any time to divide by.
wpm :: GameState -> Double
wpm st = case st.firstKeyAt of
  Just t0 | st.roundTime > t0 -> (fromIntegral (correctChars st) / 5) / ((st.roundTime - t0) / 60)
  _ -> 0
