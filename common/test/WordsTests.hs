module WordsTests (wordsTests) where

import Data.List (sort, unfoldr)
import Data.Maybe (isNothing)
import Data.Text qualified as T
import Data.Set qualified as Set
import Data.Text (Text)
import System.Random.SplitMix (SMGen, mkSMGen)
import Test.HUnit

import Game.Words

-- | Draws n Words in a row with nothing on screen (each Word is "gone" at once).
drawN :: Int -> Int -> [Text] -> Bag -> SMGen -> [Text]
drawN lookahead n pool bag0 g0 = take n (unfoldr go (bag0, g0))
  where
    go (bag, g) = case drawWord lookahead pool Set.empty bag g of
      Nothing -> Nothing
      Just (w, bag', g') -> Just (w, (bag', g'))

pool4 :: [Text]
pool4 = ["ant", "bee", "cat", "dog"]

pool30 :: [Text]
pool30 = [ T.pack ('w' : show n) | n <- enumFromTo 10 39 :: [Int] ]

wordsTests :: Test
wordsTests = TestLabel "words" $ TestList
  [ "mkWords makes buckets by length, drops blanks and repeats" ~: do
      let ws = mkWords ["cat", "", "dog", "cat", "frog"]
      bucket ws 3 @?= ["cat", "dog"]
      bucket ws 4 @?= ["frog"]
      bucket ws 5 @?= []

  , "shuffle is a permutation and depends only on the generator" ~: do
      let xs = [1 .. 20 :: Int]
          (a, _) = shuffle (mkSMGen 7) xs
          (b, _) = shuffle (mkSMGen 7) xs
          (c, _) = shuffle (mkSMGen 8) xs
      sort a @?= xs
      a @?= b
      assertBool "another seed shuffles differently" (a /= c)

  , "one bag yields every Word exactly once before any repeats" ~: do
      let ds = drawN 0 4 pool4 emptyBag (mkSMGen 1)
      sort ds @?= pool4

  , "an empty bag reshuffles and keeps going" ~: do
      let ds = drawN 0 12 pool4 emptyBag (mkSMGen 2)
      length ds @?= 12
      -- three full bags, each a permutation
      mapM_ (\i -> sort (take 4 (drop (4 * i) ds)) @?= pool4) [0, 1, 2]

  , "the reshuffle keeps the recent draws away from the front of the new bag (n = 4)" ~:
      sequence_
        [ assertBool ("first draw of a new bag repeats one of the last 3, at " <> show i <> " seed " <> show seed) (w `notElem` take 3 (drop (i - 3) ds))
        | seed <- [1 .. 30]
        , let ds = drawN 0 40 pool4 emptyBag (mkSMGen seed)
        , (i, w) <- zip [0 ..] ds, i >= 4, i `mod` 4 == 0 ]

  , "no Word comes back within recentCap draws (30 Words, any seed)" ~:
      sequence_
        [ assertBool ("repeat within the last " <> show recentCap <> " draws at " <> show i <> " seed " <> show seed) (w `notElem` take recentCap (drop (i - recentCap) ds))
        | seed <- [1 .. 20]
        , let ds = drawN 0 150 pool30 emptyBag (mkSMGen seed)
        , (i, w) <- zip [0 ..] ds, i >= recentCap ]

  , "a one-Word bucket repeats instead of failing" ~:
      drawN 0 3 ["solo"] emptyBag (mkSMGen 3) @?= ["solo", "solo", "solo"]

  , "an empty bucket draws nothing" ~:
      assertBool "Nothing" (null (drawN 0 1 [] emptyBag (mkSMGen 3)))

  , "Words on screen are skipped and stay in the bag" ~: do
      let bag = Bag ["ant", "bee", "cat"] []
      case drawWord 0 pool4 (Set.fromList ["ant"]) bag (mkSMGen 1) of
        Just (w, bag', _) -> do
          w @?= "bee"
          bag'.bagQueue @?= ["ant", "cat"]
        Nothing -> assertFailure "should draw"

  , "when every Word is on screen the draw fails (the spawn is deferred)" ~:
      assertBool "Nothing" (isNothing (drawWord 10 pool4 (Set.fromList pool4) emptyBag (mkSMGen 1)))

  , "an exhausted bag whose rest is on screen reshuffles to find a free Word" ~: do
      let bag = Bag ["ant"] []
      case drawWord 0 pool4 (Set.fromList ["ant"]) bag (mkSMGen 5) of
        Just (w, _, _) -> assertBool "not the one on screen" (w /= "ant")
        Nothing -> assertFailure "should draw"

  , "lookahead: the next Word within the window with a new first letter wins" ~: do
      let bag = Bag ["ant", "apt", "bat", "cat"] []
          onScreen = Set.fromList ["ape"]
          pick la = fmap (\(w, _, _) -> w) (drawWord la ["ant", "apt", "bat", "cat", "ape"] onScreen bag (mkSMGen 1))
      pick 10 @?= Just "bat"
      pick 2 @?= Just "bat"
      pick 1 @?= Just "ant" -- window is [ant, apt]: none is new, so the first
      pick 0 @?= Just "ant" -- off

  , "lookahead: when no Word in the window has a new first letter the first is taken" ~: do
      let bag = Bag ["ant", "apt", "arm"] []
      fmap (\(w, _, _) -> w) (drawWord 10 ["ant", "apt", "arm", "ape"] (Set.fromList ["ape"]) bag (mkSMGen 1)) @?= Just "ant"

  , "the Word drawn past the first leaves the others in order" ~: do
      let bag = Bag ["ant", "apt", "bat"] []
      case drawWord 10 ["ant", "apt", "bat", "ape"] (Set.fromList ["ape"]) bag (mkSMGen 1) of
        Just (_, bag', _) -> bag'.bagQueue @?= ["ant", "apt"]
        Nothing -> assertFailure "should draw"

  , "draws are deterministic for a seed" ~:
      drawN 0 10 pool4 emptyBag (mkSMGen 9) @?= drawN 0 10 pool4 emptyBag (mkSMGen 9)
  ]
