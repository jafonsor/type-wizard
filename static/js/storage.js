// The localStorage seam (spec section 12). Every access is wrapped: in a
// private window or with storage blocked, `window.localStorage` itself can
// throw, so a failed read is null and a failed write is false, and the game
// plays with defaults and in-memory state.
window.TypeWizardStorage = {
  load: function (key) {
    try { return window.localStorage.getItem(key); } catch (e) { return null; }
  },
  store: function (key, value) {
    try { window.localStorage.setItem(key, value); return true; } catch (e) { return false; }
  }
};
