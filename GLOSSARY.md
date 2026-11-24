# Type Wizard

A top-down typing game: enemies approach a player at the centre of the screen, and the player kills them by typing the word under each one.

## Language

**Player**:
The square at the centre of the world that the enemies approach and that the typing defends.
_Avoid_: Character, hero, wizard

**Enemy**:
A square that spawns outside the screen edges, moves towards the Player, and carries one Word.
_Avoid_: Monster, target, mob

**Word**:
The lowercase a–z string, 3 to 8 letters long, shown below an Enemy and typed to kill it.
_Avoid_: Text, label

**Tier**:
The Word length (3 to 8) of an Enemy, which sets its colour. The Tier of new Enemies rises by one after every 50 Enemies of the current Tier have spawned, up to 8. At 8 it stays, and the Round is endless.
_Avoid_: Level, difficulty

**Focus**:
The state of one Enemy being the target of the typed letters. It begins when a key matches the start of an Enemy's Word. It ends when the Word is complete or when the Player presses tab.
_Avoid_: Target, lock-on, selection

**Typo**:
A wrong letter typed while an Enemy is Focused. It clears the Streak and puts the Word in Lock. A letter with no Focus and no matching Word is not a Typo.
_Avoid_: Mistake, error

**Keystroke**:
A letter key press during a Round, not counting held-key auto-repeat. A letter that matches no Word while nothing is Focused is not a Keystroke.
_Avoid_: Input, key event

**Lock**:
The state of a Focused Word after a typo: the expected letter is shown red, and nothing advances until that letter is typed. Wrong letters while Locked count against Accuracy but are not new Typos.
_Avoid_: Block, freeze

**Kill**:
An Enemy removed because its Word was fully typed.
_Avoid_: Defeat, destroy

**Shot**:
The small triangle animated from the Player to a killed Enemy. Its colour follows the Streak.
_Avoid_: Bullet, projectile

**Life**:
One of the Player's hit points (three by default, a setting) at the start of a Round.
_Avoid_: Health, heart, HP

**Hit**:
An Enemy touching the Player, which costs one Life and starts the Grace Period. A Hit never affects the Streak.
_Avoid_: Damage, collision

**Grace Period**:
The period (2 seconds by default, a setting) after a Hit in which the Player cannot be Hit again. Enemies are not removed by touching the Player, and an Enemy still touching when it ends causes a new Hit.
_Avoid_: Cooldown, invulnerability, i-frames

**Round**:
One play from start until the last Life is lost.
_Avoid_: Game, session, run

## Scoring

**Streak**:
The count of Kills without a typo. A typo clears it. It carries over between Rounds and is not affected by death.
_Avoid_: Combo, chain

**Longest Streak**:
The longest run of consecutive Kills within the current Round, counted from 0 at Round start regardless of the Streak carried in.
_Avoid_: Best streak, record

**Bonus**:
The +N added to the points of each Kill, equal to the number of completed groups of 10 in the Streak. It is kept after death and cleared with the Streak.
_Avoid_: Multiplier, combo level

**Streak Meter**:
The indicator next to the Player that fills over each group of 10 Kills in the Streak. When it fills, the Bonus rises by one, and the meter then clears.
_Avoid_: Progress bar, combo bar

**Points**:
What a Kill awards: 1 plus the Bonus. Points from a Round are added to the Total Points when the Round ends.
_Avoid_: Score, XP

**Total Points**:
The sum of Points from all finished Rounds.
_Avoid_: High score, balance

**Round Summary**:
The table shown at the end of a Round with Points, Total Points, words per minute, accuracy, Kills, Longest Streak and the current Streak.
_Avoid_: Results screen, game over

**Accuracy**:
The percentage of Keystrokes in a Round that were correct.
_Avoid_: Precision

## Presentation

**Scene**:
The data structure describing everything to draw in a frame, built each frame from the game state and read by the renderer.
_Avoid_: World state, frame

**Camera**:
The top-down view onto the world. It pans, animated, to bring the Focused Enemy into view without the Player leaving the screen, stays fixed while that Enemy is typed, and eases back to the Player when Focus ends.
_Avoid_: Viewport

**Plus Sign**:
A "+" spawned at a killed Enemy for each point earned. The signs are slightly spread, overlap, and animate towards the Player.
_Avoid_: Coin, particle
