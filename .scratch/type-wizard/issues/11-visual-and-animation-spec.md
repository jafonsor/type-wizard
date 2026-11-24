Type: grilling
Status: resolved
Blocked by: 04, 06, 07

# Visual and animation spec

## Question

Pin the visual parameters and animation behaviour so the Scene builder can implement them.

- Default colour for each Tier (3 to 8), the Player, the Word letter states (default, green, red), the dot grid and the background, plus contrast on the dark background.
- Square sizes (Player and Enemies), Word placement below each Enemy and font size, and dot grid spacing and its movement with the Camera.
- Shot: size, speed or duration, start and end points, and the blue-to-red colour ramp (10 steps, red at Streak 100).
- Plus Signs: one per Point, spread and overlap, animation path and timing towards the Player, and fade.
- Camera: ease curve, the margin that keeps the Player on screen, and how the target position is computed from the Focused Enemy.
- Streak Meter and Bonus display near the Player, the fill, the fill-complete moment, the "+N" label.
- Hit feedback and the Grace Period (blink), and the Life display.

## Answer

All values are settings with default, min and max (per the settings schema). World units assume the orthographic camera with a fixed world height of 20.

**Palette** (all Tier colours ≥ 4.5:1 on the background)
- Background `#0e1117`; dot grid `#2a3140`; Player `#f5f5f5`.
- Tiers: 3 `#5ec8e5`, 4 `#6fd68a`, 5 `#d6e06a`, 6 `#f2b45a`, 7 `#ee7f5c`, 8 `#e0577f`.
- Letters: default `#e6e6e6`, typed `#6fe08a`, Lock-expected `#ff5c5c`.

**Sizes and layout**
- Player 1.2 square, Enemy 1.0 square. Word centred 1.0 below the Enemy centre, monospace glyph atlas, 0.9 cap height.
- Dot grid: 2-unit spacing, 0.08 dots, anchored to the world (scrolls with Camera pans).

**Shot**
- Triangle 0.5 long, points along travel, Player centre → killed Enemy position, 0.12 s ease-out. The Enemy is removed and Plus Signs spawn on arrival.
- Colour: 11 stops (one per 10 Streak), linear RGB from `#4aa3ff` at 0 to `#ff3b3b` at 100+.

**Plus Signs**
- One per Point (1 + Bonus), 0.5 units, in the Shot colour at Kill time. Start offset random within 0.6 radius (seeded from `GameState`).
- 0.1 s hold, then fly to the Player over 0.5 s with quadratic ease-in, each delayed a random 0–0.15 s. Scale to 0.3× and fade over the last 0.15 s; removed on reaching the Player.
- Drawing is capped at 30 signs per Kill; Points are unaffected.

**Camera**
- Target is the Focused Enemy position, moved only if it is outside the default view, by the smallest shift that brings it inside a 2-unit inset. The Player stays ≥ 3 units inside every screen edge.
- Exponential smoothing with a 0.25 s time constant, for both the pan and the return. Fixed while the Word is typed; eases back on Kill or tab.

**Streak Meter and Bonus label**
- Bar 2 × 0.25, 1.6 above the Player, dim track, fill in the Shot colour = `(Streak mod 10) / 10`, growing over 0.1 s per Kill.
- At 10/10: flash white 0.15 s, empty over 0.25 s, "+N" label pops 1.4× → 1× over 0.2 s. Label hidden at Bonus 0.
- Typo: bar empties and label fades over 0.2 s.

**Hit feedback and Lives**
- Player blinks (full / 25% opacity every 0.1 s) for the whole Grace Period. Red full-screen overlay at 30% opacity decaying over 0.3 s. A parked Enemy re-Hitting repeats both.
- Lives: 0.4-unit white squares in an overlay row at the HUD top-left; lost Lives are dim `#2a3140` squares (the renderer has no outlines).
