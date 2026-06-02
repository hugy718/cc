// test/normalize.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toSteps, indexToolResults } from '../src/core/normalize.js';
import { records } from './fixtures.js';

test('indexToolResults maps tool_use_id -> result text + structured', () => {
  const map = indexToolResults(records);
  assert.equal(map.get('tu-edit').text, 'File updated.');
  assert.equal(map.get('tu-bash').structured.exitCode, 0);
});

test('toSteps produces ordered, typed steps with paired results', () => {
  const steps = toSteps(records);
  assert.equal(steps[0].kind, 'userPrompt');
  assert.equal(steps[0].text, 'relax the permissions please');
  const thinking = steps.find((s) => s.kind === 'thinking');
  assert.match(thinking.text, /edit the settings/);
  const edit = steps.find((s) => s.kind === 'tool' && s.subtype === 'edit');
  assert.equal(edit.tool, 'Edit');
  assert.equal(edit.result.text, 'File updated.');
  const bash = steps.find((s) => s.kind === 'tool' && s.subtype === 'bash');
  assert.equal(bash.result.structured.exitCode, 0);
  // tool_result-only user records are NOT emitted as userPrompt
  assert.equal(steps.filter((s) => s.kind === 'userPrompt').length, 1);
});
