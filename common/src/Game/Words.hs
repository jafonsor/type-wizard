-- | Word selection (spec section 10): the word list as per-length buckets, and
-- one shuffled bag per Tier. Pure: the shuffle runs on a splitmix generator
-- that the caller threads, so a fixed seed gives a fixed sequence.
--
-- Rules of 'drawWord', in order:
--
-- 1. Words already on screen are skipped (they stay in the bag for later).
-- 2. Among the next @1 + lookahead@ eligible Words, the first whose first
--    letter matches no on-screen Word wins; if none does, the first eligible
--    Word wins (best effort). @lookahead = 0@ turns this off.
-- 3. A bag with no eligible Word is reshuffled from the whole bucket. The
--    reshuffle moves the 'recentCap' most recent draws (at most the bucket
--    size less one) to the back, so a Word is not drawn again right away
--    (the guard is best effort: step 2 may still reach back into them).
-- 4. If even a fresh bag has no eligible Word (every Word of that length is
--    on screen, or there are none) the draw fails with 'Nothing' and the
--    caller defers the spawn. A duplicate on screen never happens.
module Game.Words
  ( Words
  , mkWords
  , bucket
  , Bag (..)
  , emptyBag
  , drawWord
  , shuffle
  , recentCap
  ) where

import Data.Foldable (find)
import Data.Maybe (fromMaybe)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (delete, mapAccumL, nub, partition, sortOn)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import System.Random.SplitMix (SMGen, nextWord64)

-- | The word list, as buckets by length (the Tier).
newtype Words = Words (IntMap [Text])
  deriving stock (Eq, Show)

-- | Builds the buckets. Blank entries and repeated Words are dropped; order
-- inside a bucket is the list's order.
mkWords :: [Text] -> Words
mkWords ws = Words (IntMap.fromListWith (flip (<>)) [ (T.length w, [w]) | w <- nub (filter (not . T.null) ws) ])

-- | The Words of one length (empty when there are none).
bucket :: Words -> Int -> [Text]
bucket (Words m) n = IntMap.findWithDefault [] n m

-- | The Words still to draw, in order, and the latest draws (most recent first).
data Bag = Bag { bagQueue :: [Text], bagRecent :: [Text] }
  deriving stock (Eq, Show)

emptyBag :: Bag
emptyBag = Bag [] []

-- | How many recent draws a reshuffle keeps away from the front.
recentCap :: Int
recentCap = 10

-- | A shuffle that depends only on the generator: each item gets a random key
-- and the list is sorted by key.
shuffle :: SMGen -> [a] -> ([a], SMGen)
shuffle g xs = (map snd (sortOn fst keyed), g')
  where
    (g', keyed) = mapAccumL (\gen x -> let (k, gen') = nextWord64 gen in (gen', (k, x))) g xs

-- | Draws a Word of the bucket for a Tier. Arguments: the lookahead
-- ('Settings.wordLookahead'), the bucket, the Words on screen, the bag.
drawWord :: Int -> [Text] -> Set Text -> Bag -> SMGen -> Maybe (Text, Bag, SMGen)
drawWord lookahead pool onScreen bag0 g0
  | null pool = Nothing
  | Just (w, bag') <- pick bag0 = Just (w, bag', g0)
  | otherwise =
      let (bag1, g1) = refill pool bag0 g0
      in (\(w, bag') -> (w, bag', g1)) <$> pick bag1
  where
    firsts = Set.map (T.take 1) onScreen
    pick bag = case filter (`Set.notMember` onScreen) bag.bagQueue of
      [] -> Nothing
      eligible@(e : _) ->
        let window = take (1 + max 0 lookahead) eligible
            chosen = fromMaybe e (find ((`Set.notMember` firsts) . T.take 1) window)
        in Just (chosen, Bag (delete chosen bag.bagQueue) (take recentCap (chosen : bag.bagRecent)))

-- | A new shuffled bag of the whole bucket, the recent draws at the back.
refill :: [Text] -> Bag -> SMGen -> (Bag, SMGen)
refill pool bag g = (Bag (fresh <> recent) bag.bagRecent, g')
  where
    (shuffled, g') = shuffle g pool
    guarded = take (min recentCap (length pool - 1)) bag.bagRecent
    (recent, fresh) = partition (`elem` guarded) shuffled
