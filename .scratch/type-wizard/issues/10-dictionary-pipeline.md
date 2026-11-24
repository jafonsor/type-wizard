Type: grilling
Status: resolved
Blocked by: 03

# Dictionary pipeline and word selection

## Question

Decide how the Word list gets into the game and how Words are chosen, using the word-list research.

- The chosen source and the build-time filtering steps (`[a-z]{3,8}`, profanity filter), and where the generated list lives in the repo.
- How the list is embedded or loaded, and the resulting size and load behaviour.
- Word selection: uniform random per Tier or frequency-weighted, no duplicate Words on screen, avoiding a repeat of a recently used Word, and what happens when a Tier's pool is exhausted.
- Whether the first letters of the on-screen Words are kept distinct where possible, or ignored.
- How selection is made deterministic for tests (seeded random).

## Answer

- **Source**: SCOWL v2, US spelling, abbreviations excluded, size 35 (about 19k words), filtered to `[a-z]{3,8}`. SCOWL `offensive-*`/`vulgar-*` tags are dropped, then the LDNOOBW English list and a project-owned `exclude` file (`god`, `hell`, `damn`, ...) are applied. No frequency weighting; fairness comes from the size cutoff. The map Notes' "frequency-ranked" wording is corrected.
- **Pipeline**: an offline script `tools/make-words.sh` produces a committed `words.txt` (one word per line, sorted by length), with SCOWL's `Copyright` text and a `SOURCES.md` committed beside it. The build needs no network.
- **Embedding**: `file-embed` as a ByteString (about 150 KB raw, about 60 KB gzipped), parsed at start. If the spike (ticket 12) fails, fall back to a static file fetched once at app start, before the Start page is usable.
- **Selection**: one shuffled bag per Tier over its length bucket, held in `GameState`, shuffled with the seeded splitmix. Words on screen are skipped. An empty bag is reshuffled, with a no-recent-repeat guard. This covers the endless Tier 8.
- **First letters**: best-effort distinctness. A draw whose first letter matches an on-screen Word is replaced by the next bag Word within the lookahead (setting `Word lookahead`, default 10, min 0 = off, max 50). Otherwise the draw is accepted. Closest-Enemy-wins stays the tiebreaker.
- **Determinism**: the seed is a `GameState` field, clock-derived at Round start and fixed in tests, not a setting and not persisted. The word list is a parameter of `step`, so tests inject a tiny list.
- **Follow-ups**: the settings schema (ticket 05) gains `Word lookahead` in the spawning group. The `file-embed` spike became ticket 12.
