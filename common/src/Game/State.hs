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
-- /not/ banked into 'totalPoints' here: that is the Round-end slice's job.
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
-- /Spawn timing./ The wait before Enemy @k@ of a Tier (counting from 1) is
-- measured from the previous spawn (from 'Start' for the first Enemy of the
-- Round) and runs linearly from 'intervalStart' at @k = 1@ to 'intervalEnd'
-- at @k = enemiesPerTier@; later Enemies of the last Tier hold at
-- 'intervalEnd'. After 'enemiesPerTier' spawns the Tier advances (up to
-- 'lastTier') and the next Tier's ramp starts again at 'intervalStart'.
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
    -- * Scoring
  , streakBonus
  , meterFill
  , progressSave
  ) where

import Control.Applicative ((<|>))
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Set qualified as Set
import Data.List (minimumBy)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import System.Random.SplitMix (SMGen, mkSMGen, nextDouble, unseedSMGen)

import Game.Layout (contactDistance, defaultAspect)
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
  , totalPoints :: Int -- ^ Total Points as carried in at 'Start' (banking is the Round-end slice's)
  , groupCompletedAt :: Maybe Double
    -- ^ 'roundTime' of the latest Kill that completed a group (the meter then
    -- reads empty again: full-then-clears). A Typo clears it. The animation
    -- reads it; the state itself only records it.
  , roundTime :: Double -- ^ seconds of Round time (sum of the clamped Tick steps)
  , firstKeyAt :: Maybe Double -- ^ 'roundTime' at the first Keystroke
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
  }

step :: Settings -> Words -> Input -> GameState -> GameState
step settings ws input st = case input of
  Start seed carried -> startRound settings seed carried st
  Tick now | st.phase == Running -> tick ws now st
  Key c | st.phase == Running, c >= 'a' && c <= 'z' -> keystroke c st
  Tab | st.phase == Running -> st { focus = NoFocus }
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
  , rng = Rng (mkSMGen seed)
  , viewAspect = st.viewAspect
  }

tick :: Words -> Double -> GameState -> GameState
tick ws now st = spawnDue ws st'
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
  , roundPoints = st.roundPoints + 1 + streak' `div` size
  , runKills = run
  , longestStreak = max st.longestStreak run
  , groupCompletedAt = if streak' `mod` size == 0 then Just st.roundTime else st.groupCompletedAt
  }
  where
    size = groupSize st
    streak' = st.streak + 1
    run = st.runKills + 1

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
  }

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
-- first Keystroke to now (the last Tick; the Round-end slice freezes it at
-- Round end). 0 before there is any time to divide by.
wpm :: GameState -> Double
wpm st = case st.firstKeyAt of
  Just t0 | st.roundTime > t0 -> (fromIntegral (correctChars st) / 5) / ((st.roundTime - t0) / 60)
  _ -> 0
