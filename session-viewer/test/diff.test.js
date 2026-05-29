// test/diff.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lineDiff, editDiff } from '../src/core/diff.js';

test('lineDiff counts added and removed lines', () => {
  const d = lineDiff('a\nb\nc', 'a\nB\nc');
  assert.equal(d.added, 1);
  assert.equal(d.removed, 1);
  assert.ok(d.lines.some((l) => l.type === 'add' && l.text === 'B'));
  assert.ok(d.lines.some((l) => l.type === 'ctx' && l.text === 'a'));
});

test('editDiff: Write is all additions', () => {
  const d = editDiff('Write', { content: 'x\ny' });
  assert.equal(d.removed, 0);
  assert.equal(d.added, 2);
});

test('editDiff: Edit uses old/new strings', () => {
  const d = editDiff('Edit', { old_string: 'foo', new_string: 'bar' });
  assert.equal(d.added, 1);
  assert.equal(d.removed, 1);
});
