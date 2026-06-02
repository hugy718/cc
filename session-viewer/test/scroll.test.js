// test/scroll.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { clampTop, ensureVisible } from '../src/ui/scroll.js';

test('clampTop keeps top within [0, total-height]', () => {
  assert.equal(clampTop(100, 10, -5), 0);
  assert.equal(clampTop(100, 10, 200), 90);
  assert.equal(clampTop(5, 10, 0), 0); // content shorter than viewport
});

test('ensureVisible scrolls down to reveal the cursor item', () => {
  const rows = [];
  for (let i = 0; i < 50; i++) rows.push({ text: 't', idx: i, _head: true });
  // cursor at idx 40, viewport height 10, currently at top 0 -> should scroll
  const top = ensureVisible(rows, 10, 40, 0);
  assert.ok(top <= 40 && 40 < top + 10);
});

test('ensureVisible scrolls up when cursor above viewport', () => {
  const rows = [];
  for (let i = 0; i < 50; i++) rows.push({ text: 't', idx: i, _head: true });
  const top = ensureVisible(rows, 10, 2, 30);
  assert.equal(top, 2);
});
