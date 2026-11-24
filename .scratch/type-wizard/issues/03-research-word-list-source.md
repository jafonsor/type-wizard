Type: research
Status: resolved
Findings: research/03-word-list-source.md
Blocked by:

# Research: word list source for the dictionary

## Question

Find a source for the Word list: English words, lowercase a–z only, 3 to 8 letters, common enough to be fair in a typing game and clean enough to need little filtering.

1. Candidate lists (frequency lists, Wiktionary-derived, SCOWL, Google 10k, etc.): licence, size after filtering to `[a-z]{3,8}`, and word count per length 3 to 8. Each Tier needs enough words to avoid obvious repetition over 50 spawns, without duplicates on screen.
2. How to filter profanity and offensive words, and with what source list and licence.
3. Whether the list can be embedded at build time in Haskell (a file embedded with Template Haskell or `file-embed`, or the Obelisk static directory fetched at start), and the resulting wasm size or load impact.

Primary sources only: the list project's own repository or site and its licence text. Write the findings to `.scratch/type-wizard/research/03-word-list-source.md`.
