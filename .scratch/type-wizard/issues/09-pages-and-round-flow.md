Type: grilling
Status: resolved
Blocked by: 02, 04, 05

# Pages and Round flow

## Question

Decide the three pages and the flow between them, using the routing research.

- Hosting target and routing option: where the game is hosted (a root or a sub-path such as GitHub Pages), and which of the three options in the routing research to use (hash routes, a base path in the encoder with a per-route `index.html` or `404.html`, or no URL routing). Settings and totals Dynamics are created above `subRoute_`, and the WebGL canvas sits above it if it must survive page switches.
- Routes and navigation: start page (play and settings links), game page, settings page, and how the player returns from each.
- The Round Summary: shown over the game page or as its own state, which buttons it has (play again, back to start), and the exact rows of the table (Points, Total Points, WPM, Accuracy, Kills, Longest Streak, current Streak).
- Pause and blur: what happens when the window loses focus or the player leaves the game page mid-Round.
- The persistence interface (save and load of Total Points, Streak, Bonus and settings), when it is written, and a reset option for saved progress.
- The page layout of the HUD during a Round (Lives, Points, Streak, Streak Meter placement).

## Answer

Resolved by grilling; the user accepted the recommended answer on every question.

**Hosting and routing.** Static deploy to a GitHub Pages sub-path, with option C from the routing research: no URL routing. `FrontendRoute` keeps a single constructor. The current page is a `Dynamic Page` (`Start | Game | Settings`) held above the page switch, and `routeLink` is not used. One exported `index.html`; no deep links and no browser Back between pages. The shell around the switch stays route-independent, so hydration is unaffected.

**Canvas.** Created inside the game page, fresh on each visit. Each entry fires `Start seed`. Detaching the canvas stops the render loop and the key listener, so no extra teardown is written. Start and Settings are plain DOM with no canvas and no GL context.

**Navigation.** Start has "Play" and "Settings" buttons and shows Total Points, Streak and Bonus. Settings has "Back" to Start. During a Round a small "Menu" control and the Escape key both go straight to Start. Leaving abandons the Round with **no confirm dialog**: the Streak is already persisted per Kill or Typo, and the only loss is the unbanked Round Points.

**Round Summary.** A DOM panel over the frozen game canvas, shown when `Phase = Over`. It is not a separate page or route. Buttons: "Play again" (fires `Start` again, no page change; Enter does the same) and "Back to start". Rows in order: Points (this Round), Total Points, WPM, Accuracy, Kills, Longest Streak, Streak (current, carried out). Letters are ignored while the Summary is shown.

**Blur.** Window `blur` freezes the Round: the tick is dropped so `dt` is zero, and a "Paused, click or press any key to resume" overlay appears. `focus` followed by a click or key press resumes. There is no manual pause key. This extends the FRP ticket's "no explicit pause feature" with an automatic freeze only. Hiding the tab still freezes through rAF as before.

**Persistence.** Settings are written on every change. The save (`typewizard.save`) is written whenever the Streak changes (each Kill or Typo) and when `RoundEnded` banks Total Points. Interface: `loadSave :: IO Save` and `storeSave :: Save -> IO ()`, plus the same pair for settings, behind the JS shim. A "Reset progress" button sits on the settings page in its own "Saved progress" section, apart from the settings groups. It clears Total Points, Streak and Bonus and needs a second click ("Really reset?"). "Reset all" for settings stays no-confirm and leaves saved progress untouched.

**HUD (overlay layer, screen-fixed).** Top-left: "Lives N" (the ASCII atlas cannot draw a heart). Top-right: Points this Round and Total Points. Bottom-centre: "Streak N". Bottom-left: small "Esc: menu" hint. The Bonus "+N" and the Streak Meter stay next to the Player as world nodes. No live WPM. Fonts, sizes and colours go to the visual ticket.
