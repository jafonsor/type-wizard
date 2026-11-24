-- | The game's state and its one pure step (spec sections 4 and 7). No
-- renderer, no Reflex, no IO: 'step' takes the 'Settings' (read at 'Start'
-- only, where they are snapshotted), the word list, an 'Input' and the state,
-- and returns the next state. The random generator is a field, seeded by
-- 'Start', so a fixed seed gives a fixed game.
--
-- This slice holds spawning and movement only. 'Key' and 'Tab' are accepted
-- and ignored until typing is built.
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
  ) where

import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Word (Word64)
import System.Random.SplitMix (SMGen, mkSMGen, nextDouble, unseedSMGen)

import Game.Layout (contactDistance, defaultAspect)
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
  }
  deriving stock (Eq, Show)

data Input
  = Key Char -- ^ accepted, ignored for now
  | Tab -- ^ accepted, ignored for now
  | Tick Double -- ^ the frame time in seconds (the rAF clock)
  | Start Seed
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
  }

step :: Settings -> Words -> Input -> GameState -> GameState
step settings ws input st = case input of
  Start seed -> startRound settings seed st
  Tick now | st.phase == Running -> tick ws now st
  Aspect a | a > 0 && not (isInfinite a) -> st { viewAspect = a }
  _ -> st

-- | Round start (spec section 4): first Tier, empty field, counters 0. The
-- view aspect carries over.
startRound :: Settings -> Seed -> GameState -> GameState
startRound settings seed st = initialState
  { phase = Running
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
