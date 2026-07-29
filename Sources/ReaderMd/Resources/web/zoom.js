// Pure zoom math for rendered Mermaid diagrams (#38). Deliberately free of DOM
// access and kept out of bridge.js, which touches `document` at load time and so
// cannot be imported by a test.

const MIN_SCALE = 0.25;
const MAX_SCALE = 8;

function clampScale(s) {
  return Math.min(MAX_SCALE, Math.max(MIN_SCALE, s));
}

// Scale `state` by `factor`, keeping the point (px, py) — in the view's own
// coordinate space — pinned under the pointer. Returns a new state.
//
// The clamp is applied to the scale FIRST, so the translation is derived from the
// scale actually used. Deriving it from the requested scale makes the diagram
// drift a little on every notch once you are sitting at a limit.
function zoomAt(state, factor, px, py) {
  const s = clampScale(state.s * factor);
  const ratio = s / state.s;
  return {
    s,
    x: px - (px - state.x) * ratio,
    y: py - (py - state.y) * ratio,
  };
}

// The app loads this as a plain <script>, so the above stay globals. This tail is
// inert in the browser (`module` is undefined there) and is what the node test uses.
if (typeof module !== 'undefined') {
  module.exports = { zoomAt, clampScale, MIN_SCALE, MAX_SCALE };
}
