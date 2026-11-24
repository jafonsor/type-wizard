Type: grilling
Status: resolved
Blocked by:

# Game rules and typing state machine

## Question

Lock the rules as a precise state machine the spec can state without ambiguity. Start from the "Settled while charting" list in the map and resolve what is still open:

- Typing: the states Idle, Focused and Locked, the transitions for a correct key, a wrong key while Focused, the correct key while Locked, tab and kill. What happens to the letters already typed when tab clears Focus. Whether wrong keys while Locked count as extra typos.
- Whether a key with no Focus and no match counts against Accuracy. Sharpen the exact definition of "keystroke".
- Spawn curve: how spawn rate rises within each set of 50, and whether it resets at each new Tier or continues across Tiers. The user said the curve is the same for every Tier.
- Enemy speed: constant across Tiers, or per Tier. The user said the difficulty is the longer Words.
- Streak Meter and Bonus: the exact moments when the meter fills, the Bonus rises and the meter clears, and what a typo does to each.
- Grace Period: whether it starts on the Hit and whether touching Enemies during it do nothing. The Round ends when Lives reach 0, and what happens to Enemies on screen at that moment.
- Round start: initial Tier, Lives, empty field, and what carries over (Streak, Bonus, Total Points).

Write the answer as the rules section of the spec draft and sharpen `GLOSSARY.md` as terms resolve.


## Answer

Rules (all confirmed by the user in grilling):

**Keystroke.** A physical a-z key-down while a Round runs. OS auto-repeat events (key held down) are ignored. Separate presses of the same letter each count. Non-letter keys, tab included, are ignored. In Idle, a letter matching no Word is not a keystroke (counts for nothing, not a typo).

**Typing state machine.**
- Idle + letter matching the first letter of some Word: Focus the closest Enemy (smallest Euclidean centre-to-centre distance to the Player at key press; tie goes to the earlier spawn). The key is correct, k=1.
- Focused + correct next letter: k+1. When k reaches the Word length: Kill, state Idle.
- Focused + wrong letter: typo. Streak, Bonus and Streak Meter clear immediately. State Locked.
- Locked + expected letter: state Focused, k+1.
- Locked + wrong letter: not a new typo (Streak already 0); counts as an incorrect keystroke; stays Locked.
- Tab, from Focused or Locked: clears Focus and Lock, resets the Word to untyped (k=0). The Enemy keeps moving. No cost to Streak or Accuracy. Tab in Idle does nothing.

**Accuracy** = correct / (correct + wrong). Wrong = Focused typos + wrong keys while Locked. Zero keystrokes shows 100%.

**Spawning.** Within each Tier the spawn interval shrinks linearly from intervalStart (Enemy 1) to intervalEnd (Enemy 50). Same two values for every Tier; the curve resets at each new Tier. Tier is capped at 8: after 50 Tier-8 spawns, spawning continues at Tier 8 with the interval held at intervalEnd. Endless, no victory condition.

**Enemy speed.** One constant for all Enemies. Difficulty comes only from Word length and spawn rate.

**Streak, Bonus, Points.** A Kill increments the Streak first, then Points = 1 + floor(Streak/10) using the new Streak. The 10th consecutive Kill already earns 2. On that Kill the Streak Meter fills, the Bonus rises, the meter clears. Typo clears Streak, Bonus and meter immediately.

**Hit and Grace Period.** An Enemy stops at contact distance with the Player and stays until killed; it can still be Focused and typed. A Hit happens when an Enemy touches the Player and no Grace Period is active: -1 Life, 2 s Grace Period starts. During Grace, touching Enemies do nothing. When Grace ends, any Enemy still touching Hits at once (a parked Enemy costs a Life every 2 s). Streak is never affected.

**Round end.** When Lives reach 0: spawning, movement and input stop; Focus and Lock drop; Enemies on screen are discarded with no Points. Round Points are added to Total Points and the Round Summary is shown. In-flight Shot and Plus Sign animations are a presentation question (visual ticket).

**Round start.** First Tier (3), full Lives, empty field, spawn counters 0, no Focus, no Grace Period. Carried over: Streak (with its Bonus and meter), Total Points, settings. Longest Streak is the longest run of consecutive Kills within this Round, counted from 0 at Round start (carried-in 7 plus 5 Kills: Streak 12, Longest Streak 5).
