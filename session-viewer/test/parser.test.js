// test/parser.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseLine, parseLines } from '../src/core/parser.js';
import { rawJsonl } from './fixtures.js';

test('parseLine: blank -> null, malformed -> undefined, valid -> object', () => {
  assert.equal(parseLine('   '), null);
  assert.equal(parseLine('{bad'), undefined);
  assert.deepEqual(parseLine('{"a":1}'), { a: 1 });
});

test('parseLines: collects records and counts malformed', () => {
  const { records, skipped } = parseLines(rawJsonl);
  assert.equal(skipped, 1);            // the one malformed line
  assert.equal(records[0].type, 'ai-title');
  assert.ok(records.length >= 12);
});
