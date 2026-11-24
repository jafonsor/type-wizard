# Research 03: word list source for the dictionary

Date: 2026-11-24. Counts below were measured by me on downloaded copies (kept outside the repo, treated as data only; nothing from them was executed). Licence and behaviour claims cite the owning project.

## Recommendation (short)

- Primary source: **SCOWL / ESDB (en-wl/wordlist, v2)**, extracted at size 50 or 60, US spelling, abbreviations excluded, then filtered to `[a-z]{3,8}` and with its own `offensive-*`/`vulgar-*` tags removed. Permissive MIT-like licence, redistribution of derived lists explicitly allowed, first-party offensive tagging, no manual blocklist needed to start.
- Fallback / frequency-ordered alternative: **first20hours/google-10000-english (usa)**, but its licence is awkward (see below) and it has web junk (`www`, `pdf`, `http`, `gif`, `isbn`...). It is also too small for the longer Tiers.
- Profanity: use SCOWL's own tags as the first filter, then apply the **LDNOOBW English list** (CC BY 4.0) as a second pass for belt and braces. Keep a project-owned `exclude` file for manual additions.
- Embedding: build-time embedding with `file-embed` is feasible under the GHC wasm backend. A 20-30k word list is about 150-250 KB raw, well under 100 KB gzipped, so load impact is small. Needs confirmation by a spike in the actual Obelisk wasm build (no first-party end-to-end example found).

## 1. Candidate lists

### 1a. SCOWL / ESDB (Kevin Atkinson), https://github.com/en-wl/wordlist (branch v2)

- Licence: README says "freely available under an MIT-like license"; the `Copyright` file grants "Permission to use, copy, modify, distribute, and sell any part of the English Speller Database (ESDB, previously known as SCOWLv2), or word lists created from it, ... without fee provided that the above copyright notice appears in all copies and ... in supporting documentation", "as is". Sources: https://github.com/en-wl/wordlist/blob/v2/README.md and https://raw.githubusercontent.com/en-wl/wordlist/v2/Copyright
- Caveat from the same Copyright file: some underlying sources have their own notices (COCA under NDA terms for data use, UKACD notice that applies to generated lists **larger than size 80**, WordNet and others permissive with notice). Staying at size 60 or below avoids the UKACD condition; ship the Copyright text anyway to be safe.
- Selection: `./scowl --db scowl.db word-list 60 A 1 --wo-poses=abbr` (size, spelling codes, variant level; `A` = US). Sizes: 35 small, 50 medium, 60 default spell-check size, 70 large, 80/85 rare. `make` builds `scowl.db` first. (README above.)
- Filtering caveats from the README: proper noun classes are inconsistent, so do not rely on tags; but a `[a-z]` regex discards capitalised proper nouns anyway because SCOWL keeps case. Also may contain Roman numerals and slang by default (`--categories=` to exclude).
- Measured (my own approximate parse of the raw `data/scowl-pre.txt`, headwords plus listed derived forms, lowercase `[a-z]{3,8}`, abbr and `upper`-tagged entries dropped, US/GB variant duplication not resolved so treat as an upper bound by a few percent). Not the output of the official `scowl` tool; re-run it for the final numbers.

| size cutoff | total | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|
| 35 | 19,036 | 313 | 1,250 | 2,473 | 4,066 | 5,526 | 5,408 |
| 50 | 26,665 | 386 | 1,570 | 3,187 | 5,434 | 7,798 | 8,290 |
| 60 | 31,885 | 455 | 1,771 | 3,648 | 6,374 | 9,383 | 10,254 |
| 70 | 48,431 | 607 | 2,452 | 5,291 | 9,441 | 14,214 | 16,426 |

- Fairness concern: SCOWL size 50+ is "known to a spell checker", not "common". Length 7-8 words at size 60 include many obscure inflections. If fairness matters, use size 35 or 50 for the pool and optionally weight by frequency (see wordfreq below). 3-letter words are the scarce bucket everywhere (313-455), still plenty for 50 spawns without repeats if a tier's pool is >= 100.
- Offensive tagging: entries carry usage notes `offensive-1`, `offensive-2`, `vulgar-1`, `vulgar-3` (README). The README says the first three are NOSUGGEST in Hunspell output. In the data I counted 61 tagged headwords overall, 28 of them `[a-z]{3,8}` at size <= 50 (e.g. `fuck`, `shit`, `piss`, `dick`, `crap`, `nigger`, `coon`, `bugger`, `fart`, `bullshit`). Tagged words are a small set; the tags do **not** cover everything LDNOOBW does (e.g. `sex`, `porn`, `nude`, `anal`), so a second pass is needed.

### 1b. google-10000-english (first20hours), https://github.com/first20hours/google-10000-english

- Derived from Norvig's counts of the Google Web Trillion Word Corpus. Variants: `google-10000-english-usa.txt`, `-no-swears.txt`, length lists.
- Licence: the repo's LICENSE.md says the data is derived from the LDC-distributed Google corpus, and "Educational and personal/research use ... is permitted under the LDC license, Norvig's MIT license for his contributions, and US fair use doctrine. I do not recommend using this data for commercial purposes without licensing it from the Linguistic Data Consortium." Not a clean open licence; fine for a hobby project, risky for anything redistributed commercially. README marks the repo "Not Maintained".
- Measured on `-usa.txt` (9,999 lines) filtered to `[a-z]{3,8}`: 7,322 words. By length: 3: 672, 4: 1125, 5: 1385, 6: 1508, 7: 1464, 8: 1168 (ignoring trailing counts; this is after the filter, the 3 to 8 column totals add to 7,322).
- Junk present after regex filter, to be removed by hand: `ebay dvd url html pdf ltd inc gmt usb php isbn xxx www llc cds http jpg cgi gif mls` (and similar acronyms), plus adult-site words in the plain list.
- `-no-swears.txt` (9,894 lines): README says swears were removed using reimertz/curse-words, MauriceButler/badwords and LDNOOBW. It still retains some LDNOOBW words (e.g. `sexy`, `sexual`, `nipples`, `panties`, `erotic`), so a second pass is needed. After filtering `[a-z]{3,8}` and subtracting LDNOOBW single words it has 7,223 words (3: 664, 4: 1100, 5: 1367, 6: 1487, 7: 1449, 8: 1156). The 7,247 figure used in the size section is the usa list after the same LDNOOBW pass.
- Pro: ordered by frequency, very "fair"; each Tier has >= 670 words. Con: licence, junk, only ~1,100 to 1,500 words per length.

### 1c. dwyl/english-words (`words_alpha.txt`), https://github.com/dwyl/english-words

- 370,105 lines; repo is Unlicense, but README says the underlying content came from an infochimps list and "Copyright still belongs to them". Provenance unclear.
- Filtered `[a-z]{3,8}` (after stripping CRLF): 3: 2,130; 4: 7,186; 5: 15,921; 6: 29,874; 7: 41,998; 8: 51,627. Contains huge amounts of obscure words. Not suitable as a "fair" list.

### 1d. wordfreq (rspeer), https://github.com/rspeer/wordfreq

- Code Apache; data under CC BY-SA 4.0 with credit requirements for sub-sources (SUBTLEX, Google Books Ngrams, Twitter). Data is a snapshot to about 2021 and "unlikely to be updated again". `top_n_list('en', n, wordlist='best')` gives frequency-ordered words. Python only, so use it offline as a generator step for ranking, not at runtime. CC BY-SA 4.0 applies to the data, so a derived word list shipped in the game would need attribution and share-alike. Prefer SCOWL for licence simplicity; use wordfreq only if a frequency cut is wanted and the share-alike obligation is acceptable.
- No profanity handling documented in the README I read.

## 2. Profanity filtering

- First pass: SCOWL tags `offensive-*` / `vulgar-*` (MIT-like licence, see above). Removes about 28 of the words in scope.
- Second pass: **LDNOOBW English list**, https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words, file `en`: 403 lines (275 single `[a-z]` tokens, rest multiword/with digits). Licence is **Creative Commons Attribution 4.0 International** (the repo's LICENSE file). Needs attribution if the list is shipped; if used only as a build-time exclusion and never shipped, the attribution burden is minimal but still give credit in the docs.
- Measured: intersecting the 275 single-word entries with google-10000-english-usa (3-8 letters) removes 75 words (7,322 to 7,247) (`sex porn nude ass anal pussy sexy rape incest xxx fucking milf cum hardcore fuck bondage cock porno tits hentai sexual shemale voyeur viagra ... penis erotic butt shit ... nipple vagina orgasm whore`). It is aggressive: it also drops harmless-in-context words like `butt`, `nude`, `sexual`, `escort`, `playboy`, `panties`. For a typing game that is the right bias (false negatives are worse than false positives).
- Not covered by LDNOOBW but present in the google list's `no-swears` diff (i.e. removed by the other two source lists): `god`, `hell`, `damn`, `crap`, `piss`, `balls`, `bloody`, `breasts`. Decide per taste; recommend dropping `god hell damn crap balls bloody` as a house rule.
- Process recommendation: pipeline = SCOWL extract -> regex `^[a-z]{3,8}$` -> remove offensive tags -> subtract LDNOOBW single words -> subtract a project `exclude` list -> write one file. Add a one-off human skim of each Tier before committing. Other possible filter sources (reimertz/curse-words, MauriceButler/badwords) were not licence-checked here.

## 3. Embedding in Haskell and wasm

- **file-embed** (Hackage): "Use Template Haskell to read a file or all the files in a directory, and turn them into (path, bytestring) pairs embedded in your haskell code." Module `Data.FileEmbed`, version 0.0.16.0 (2024-01-28), BSD-2-Clause. https://hackage.haskell.org/package/file-embed
- **GHC wasm backend and TH**: Tweag post (by the backend's authors) says "TH splices that involve only pure computation ... work. Simple file I/O also works, so file-embed works." Requirements: `-dynamic-too` / `shared: True`, `cabal >= 3.14`, an external interpreter run through `node`; side effects limited to WASI. In GHC `master` and release branches from 9.12. https://tweag.io/blog/2024-11-21-ghc-wasm-th-ghci/
- **Obelisk**: README says it supports wasm and GHCJS frontend targets (wasm default), GHC 9.14, with a `static/` directory that is "hashed + compressed automatically" (brotli and gzip by default) and exposes an `obelisk-generated-static` module. So both strategies exist: (a) embed in the frontend with `file-embed` (the word list is then inside the .wasm), or (b) put the file in `static/` and fetch it at start via the generated hashed path, getting automatic compression and HTTP caching. https://github.com/obsidiansystems/obelisk/blob/master/README.md
- Gotcha: a Haskell Discourse thread reports a trap when embedding files in wasm related to command vs reactor modules (https://discourse.haskell.org/t/embedding-files-in-wasm/10216). I only saw a search snippet, not the thread, so treat as an unverified risk. No first-party Obelisk + file-embed + wasm example was found; a spike is needed.
- **Size/load impact**: measured on the google-10000 list after filter, 7,247 words = 48,917 bytes raw, 24,201 bytes gzipped. Scaling to SCOWL size 50 (~26.7k words, average ~6.3 chars + newline) gives roughly 190 KB raw and about 70-90 KB gzipped (estimate, not measured). Embedded as a ByteString literal the cost is about the raw size in the wasm data segment (and, compressed in transit by the host, close to the gzip figure). Parsing 27k lines at start is trivial (<10 ms). Static-file option costs one extra request but gets caching.
- Practical advice: do the word list preparation offline (script in the repo producing `words.txt`, one word per line, grouped or length-sorted), keep the generated file small (size 50 or less, or a per-tier frequency cap), and embed it or serve from `static/`. Decide by the spike outcome.

## Tier sufficiency (50 spawns, no duplicates on screen)

Any of the SCOWL cutoffs gives >= 300 words for the scarcest length (3 letters), and google-10000-usa gives >= 670 per length. Drawing 50 spawns without replacement from a pool of 300+ never repeats within a round. Using a shuffled bag per Tier gives guaranteed no repeats within 50 spawns and no duplicates on screen.

## Open items

- Re-run the official `scowl` tool for exact counts (my counts are from raw data parse).
- Confirm file-embed under the actual Obelisk wasm toolchain with a spike.
- Decide house-rule extra exclusions (`god`, `hell`, `damn`, ...).
