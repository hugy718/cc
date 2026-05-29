import { indexToolResults } from './normalize.js';

export function listDispatches(records) {
  const results = indexToolResults(records);
  const out = [];
  for (const rec of records) {
    if (rec.type !== 'assistant') continue;
    const content = rec.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type === 'tool_use' && block.name === 'Agent') {
        out.push({
          description: block.input?.description ?? '',
          subagentType: block.input?.subagent_type ?? 'agent',
          prompt: block.input?.prompt ?? '',
          status: results.get(block.id)?.structured?.status ?? 'unknown',
        });
      }
    }
  }
  return out;
}

// Match a dispatch to its subagent file by first-prompt equality, then by prefix.
// `used` prevents two dispatches from resolving to the same file.
export function resolveDispatchFile(dispatch, summaries, used = new Set()) {
  const norm = (s) => String(s ?? '').trim().slice(0, 200);
  const target = norm(dispatch.prompt);
  if (!target) return null;
  let match = summaries.find((s) => !used.has(s.file) && norm(s.firstPrompt) === target);
  if (!match) {
    const head = target.slice(0, 80);
    match = summaries.find((s) => !used.has(s.file) && norm(s.firstPrompt).startsWith(head));
  }
  if (match) { used.add(match.file); return match.file; }
  return null;
}

// Resolve every dispatch to a file using ONE shared `used` set, so distinct
// dispatches that share a prompt map to distinct files (in dispatch order).
// Returns an array parallel to `dispatches` (entries may be null).
export function resolveAllDispatchFiles(dispatches, summaries) {
  const used = new Set();
  return dispatches.map((d) => resolveDispatchFile(d, summaries, used));
}
