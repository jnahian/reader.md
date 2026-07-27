const { test } = require('node:test');
const assert = require('node:assert/strict');
const { zoomAt, clampScale, MIN_SCALE, MAX_SCALE } = require('../../Sources/ReaderMd/Resources/web/zoom.js');

// Where a diagram-space point `d` lands on screen along one axis.
const screenOf = (offset, scale, d) => offset + d * scale;

function assertPinned(before, factor, px, py) {
  // The diagram-space coordinates currently sitting under the pointer.
  const dx = (px - before.x) / before.s;
  const dy = (py - before.y) / before.s;
  const after = zoomAt(before, factor, px, py);
  const nx = screenOf(after.x, after.s, dx);
  const ny = screenOf(after.y, after.s, dy);
  assert.ok(Math.abs(nx - px) < 1e-9, `x drifted: ${nx} != ${px}`);
  assert.ok(Math.abs(ny - py) < 1e-9, `y drifted: ${ny} != ${py}`);
  return after;
}

test('zooming in from rest keeps the point under the cursor', () => {
  const after = assertPinned({ s: 1, x: 0, y: 0 }, 2, 300, 120);
  assert.equal(after.s, 2);
});

test('zooming from an already panned and zoomed state keeps the point pinned', () => {
  // The case a naive implementation gets wrong: it ignores the existing offset.
  assertPinned({ s: 2.5, x: -140, y: -30 }, 1.25, 410, 260);
});

test('zooming out keeps the point under the cursor', () => {
  assertPinned({ s: 4, x: -900, y: -220 }, 1 / 1.25, 55, 640);
});

test('at the top clamp the translation does not move either', () => {
  // Deriving the translation from the *requested* scale rather than the clamped
  // one makes the diagram drift every notch once you hit the limit.
  const before = { s: MAX_SCALE, x: -50, y: -60 };
  const after = zoomAt(before, 2, 300, 120);
  assert.equal(after.s, MAX_SCALE);
  assert.equal(after.x, -50);
  assert.equal(after.y, -60);
});

test('at the bottom clamp the translation does not move either', () => {
  const before = { s: MIN_SCALE, x: 12, y: 8 };
  const after = zoomAt(before, 0.5, 300, 120);
  assert.equal(after.s, MIN_SCALE);
  assert.equal(after.x, 12);
  assert.equal(after.y, 8);
});

test('zoomAt does not mutate its argument', () => {
  const before = { s: 1, x: 0, y: 0 };
  zoomAt(before, 2, 10, 10);
  assert.deepEqual(before, { s: 1, x: 0, y: 0 });
});

test('clampScale bounds both ends and passes the middle through', () => {
  assert.equal(clampScale(0.01), MIN_SCALE);
  assert.equal(clampScale(99), MAX_SCALE);
  assert.equal(clampScale(1.75), 1.75);
});
