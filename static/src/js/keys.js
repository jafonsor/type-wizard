// The key shim of the Game page (spec sections 4 and 7).
//
// `TypeWizardKeys.attach(canvas, callback)` listens to `keydown` on `window`
// for as long as `canvas` is attached to the document, and calls
// `callback("a".."z")` or `callback("Tab")` once per Keystroke. It is the only
// key listener of the game, so the Start and Settings pages' keys (including
// Tab navigation) are untouched: the listener removes itself on the first
// event or frame at which the canvas has left the document, and, being
// removed before it looks at the key, it never prevents the default then.
//
// What it does with a key:
//   - Tab: `preventDefault` here (never in Haskell, which would be too late),
//     so focus cannot leave the page; reported as "Tab". Tab with Shift is
//     still a Tab. Tab with ctrl/meta/alt is left to the browser (tab switch).
//   - a to z (`event.key`, either case): reported lowercase. Not reported
//     with ctrl, meta or alt held (shortcuts such as Ctrl+C are not
//     Keystrokes and keep working); Shift is fine (Caps Lock and Shift give
//     capitals).
//   - anything else is ignored and left alone.
//   - `event.repeat` (a held key) is ignored; Tab's default is still
//     prevented while the key is held.
//
// Test hook: `TypeWizardKeys.stats` counts attaches, detaches and keys sent.
(function () {
  "use strict";

  var WAIT_FRAMES = 120; // frames a canvas may take to be attached before the shim gives up
  var stats = { attached: 0, detached: 0, sent: 0, active: 0 };

  function attach(canvas, callback) {
    var seen = false;
    var waited = 0;
    var done = false;

    function detach() {
      if (done) return;
      done = true;
      window.removeEventListener("keydown", onKey, true);
      stats.detached++;
      stats.active--;
    }

    // True while the canvas is in the document (or has not arrived yet, for
    // a moment: Reflex attaches it a little after building it).
    function alive() {
      if (canvas.isConnected) { seen = true; return true; }
      if (seen || ++waited > WAIT_FRAMES) { detach(); return false; }
      return true;
    }

    function onKey(e) {
      if (!alive()) return;
      if (!canvas.isConnected) return;
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      if (e.key === "Tab") {
        e.preventDefault();
        if (e.repeat) return;
        stats.sent++;
        callback("Tab");
        return;
      }
      if (e.repeat) return;
      if (typeof e.key === "string" && e.key.length === 1 && /^[a-zA-Z]$/.test(e.key)) {
        stats.sent++;
        callback(e.key.toLowerCase());
      }
    }

    // Capture phase, so nothing on the page can swallow the key first.
    window.addEventListener("keydown", onKey, true);
    stats.attached++;
    stats.active++;

    // Detach promptly when the canvas leaves, even if no key is pressed.
    function poll() {
      if (done) return;
      if (alive()) requestAnimationFrame(poll);
    }
    requestAnimationFrame(poll);
  }

  window.TypeWizardKeys = { attach: attach, stats: stats };
})();
