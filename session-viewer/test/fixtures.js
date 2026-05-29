// test/fixtures.js
// A realistic mini-session as RawRecord objects.
export const records = [
  { type: 'ai-title', aiTitle: 'Relax init-workspace perms', sessionId: 'sess-1' },
  { type: 'user', timestamp: '2026-05-21T10:00:00Z', cwd: '/Users/me/cc', gitBranch: 'main',
    sessionId: 'sess-1', message: { role: 'user', content: 'relax the permissions please' } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:01Z', message: { role: 'assistant', content: [
      { type: 'thinking', thinking: 'I will edit the settings file.\nTwo lines.' },
      { type: 'text', text: "I'll update the settings file." },
      { type: 'tool_use', id: 'tu-edit', name: 'Edit',
        input: { file_path: '/Users/me/cc/.claude/settings.local.json',
                 old_string: '"deny": []', new_string: '"allow": ["Write"]', replace_all: false } },
  ] } },
  { type: 'user', timestamp: '2026-05-21T10:00:02Z',
    toolUseResult: { filePath: '/Users/me/cc/.claude/settings.local.json' },
    message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'tu-edit', content: 'File updated.' } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:03Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-bash', name: 'Bash', input: { command: 'git status' } } ] } },
  { type: 'user', timestamp: '2026-05-21T10:00:04Z',
    toolUseResult: { exitCode: 0, stdout: 'On branch main' },
    message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'tu-bash', content: 'On branch main\nnothing to commit' } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:07Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-tc', name: 'TaskCreate',
        input: { subject: 'Do the thing', description: 'details' } } ] } },
  { type: 'user', timestamp: '2026-05-21T10:00:06Z',
    toolUseResult: { task: { id: '1', subject: 'Do the thing' } },
    message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'tu-tc', content: 'created' } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:07Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-tu1', name: 'TaskUpdate', input: { taskId: '1', status: 'in_progress' } } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:08Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-tu2', name: 'TaskUpdate', input: { taskId: '1', status: 'completed' } } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:09Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-agent', name: 'Agent',
        input: { description: 'find stuff', subagent_type: 'Explore', prompt: 'find the helper' } } ] } },
  { type: 'user', timestamp: '2026-05-21T10:00:10Z',
    toolUseResult: { status: 'completed' },
    message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'tu-agent', content: 'done' } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:11Z',
    message: { role: 'assistant', content: [{ type: 'text', text: 'Done.' }] } },
];

// Same session as raw JSONL text, plus one blank and one malformed line.
export function toJsonl(recs = records) {
  return recs.map((r) => JSON.stringify(r)).join('\n');
}
export const rawJsonl = toJsonl() + '\n\n' + '{ this is not valid json';

// A subagent file's records (its first user message echoes the dispatch prompt).
export const subagentRecords = [
  { type: 'user', isSidechain: true, agentId: 'aaa111', sessionId: 'sess-1',
    message: { role: 'user', content: 'find the helper' } },
  { type: 'assistant', isSidechain: true, agentId: 'aaa111',
    message: { role: 'assistant', content: [{ type: 'text', text: 'Found it.' }] } },
];
