-- | The embedded word list. @words/words.txt@ is compiled into the binary
-- by Template Haskell, so the page needs no network request for it.
--
-- Build rules (spec section 10, each learned from a failed build):
--
--   1. the file is tracked by git and is not under the gitignored @data/@;
--   2. @frontend.cabal@ lists it under @extra-source-files@;
--   3. it is embedded through 'makeRelativeToProject', and @file-embed@ and
--      @bytestring@ sit in the library's main @build-depends@.
module Frontend.Words
  ( wordsBytes
  , parseWords
  , allWords
  , gameWords
  ) where

import Data.ByteString (ByteString)
import Data.FileEmbed (embedFile, makeRelativeToProject)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8)

import Game.Words qualified as Game

wordsBytes :: ByteString
wordsBytes = $(makeRelativeToProject "words/words.txt" >>= embedFile)

-- | One word per line; blank lines are skipped.
parseWords :: ByteString -> [Text]
parseWords = filter (not . T.null) . map T.strip . T.lines . decodeUtf8

allWords :: [Text]
allWords = parseWords wordsBytes

-- | The embedded list as the length buckets 'Game.Words' draws from; a
-- top-level value, so it is built once.
gameWords :: Game.Words
gameWords = Game.mkWords allWords
