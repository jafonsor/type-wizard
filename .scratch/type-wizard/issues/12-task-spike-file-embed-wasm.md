Type: task
Status: resolved
Blocked by:

# Spike: file-embed of words.txt under the Obelisk wasm build

## Question

Confirm that `file-embed` can embed a roughly 150 KB `words.txt` as a ByteString in the Obelisk v2 GHC wasm build (laid out like `~/devs/type-solution`), and that it is readable at runtime. Also measure the JS boundary per-call cost if cheap to do. Record the outcome: works, or fall back to a static file fetched at app start (see the dictionary pipeline ticket). The answer records what was done and any facts later tickets depend on. This is a build check, not game code.

## Comments

### Session notes (not resolved)

Finding so far: `~/devs/type-solution` has **no wasm precedent** for `file-embed`. `frontend/frontend.cabal` lists it only under `if !(arch(javascript) || arch(wasm32))`, and `Frontend/Paths.hs` uses it on the native build only. So the spike needs a real wasm build and cannot be answered by reading.

Not started, because it is a long Nix wasm build (GHC 9.12, no binary cache hit guaranteed; type-solution's own notes warn about memory use) that should be run on the user's say-so. Run it in a scratch copy of `type-solution`, never in the original.

Checklist (HITL, run by the user, or by an agent once approved):
1. `cp -R ~/devs/type-solution /tmp/embed-spike && cd /tmp/embed-spike` (or `git worktree add`). `git add -N` any new file, since flake builds ignore untracked files.
2. Generate `frontend/data/words.txt` (about 150 KB, any `[a-z]{3,8}` lines will do).
3. In `frontend/frontend.cabal`, move `file-embed` out of the `!(javascript || wasm32)` conditional into the main `build-depends`.
4. Add `wordsBytes :: ByteString; wordsBytes = $(embedFile "data/words.txt")` and show `length (BS.split 10 wordsBytes)` in the page.
5. `nix build .#haskell-nix --cores 4` and load the result. Pass: the page shows the expected line count. Fail modes to record: TH/external-interpreter error, path resolved relative to the wrong directory, wasm size growth.
6. Record: works or not, wasm size delta, and, if cheap, a loop of 100k trivial JS FFI calls timed with `performance.now()`.

## Answer

**`file-embed` works under the Obelisk v2 GHC wasm build.** Done in a scratch copy of `type-solution` (not the original), with a 20,000-line, 130,655-byte `words.txt`. Template Haskell's `embedFile` runs at compile time on the wasm target and `nix build .#haskell-nix --cores 4` succeeds; the dependencies were cached, so only the frontend package rebuilt.

Three facts the spec must carry (each cost a failed build):
1. **The file must be tracked by git.** `frontend/data/*` is gitignored in this layout, and flake builds only see tracked files (`git add -N` is enough). Put the list in a tracked directory, e.g. `frontend/words/words.txt`, not under `data/`.
2. **The cabal file must declare it**: `extra-source-files: words/words.txt`. Without it haskell.nix's source filter drops the file and the splice fails with `withBinaryFile: does not exist`.
3. **Use `makeRelativeToProject "words/words.txt" >>= embedFile`** (as `Frontend/Paths.hs` already does natively). A bare relative path failed. Also move `file-embed` (and `bytestring`) out of the `!(javascript || wasm32)` conditional into the library's main `build-depends`.

Size: `frontend.wasm` identity 7,181,070 to 7,345,463 bytes (+164 KB, which includes the test page code); gzip +76 KB; brotli +69 KB. The word bytes and the page string are present in the binary (checked by grepping the output), so the embedded list is a plain data segment.

Not done: the page was not loaded in a browser, so the runtime line count was not read back, and the JS-boundary per-call cost was **not measured**. Both stay with the implementation. The static-fetch fallback in the dictionary pipeline ticket is not needed.
