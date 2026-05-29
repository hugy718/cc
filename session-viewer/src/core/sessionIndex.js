import { parseLines } from './parser.js';

export function firstUserPrompt(records) {
  for (const rec of records) {
    if (rec.type !== 'user' || rec.isMeta) continue;
    const c = rec.message?.content;
    if (typeof c === 'string' && c.trim()) return c.trim();
    if (Array.isArray(c)) {
      const txt = c.filter((b) => b.type === 'text').map((b) => b.text).join('\n').trim();
      if (txt) return txt;
    }
  }
  return '';
}

// `lines` may be a bounded head-read of the file, not the whole thing —
// title and first prompt live at the top, so that is sufficient.
export function summarize(lines, meta) {
  const { records } = parseLines(lines);
  let title = '';
  let cwd = '';
  let gitBranch = '';
  let sessionId = '';
  for (const rec of records) {
    if (rec.type === 'ai-title' && rec.aiTitle) title = rec.aiTitle;
    if (!cwd && rec.cwd) cwd = rec.cwd;
    if (!gitBranch && rec.gitBranch) gitBranch = rec.gitBranch;
    if (!sessionId && rec.sessionId) sessionId = rec.sessionId;
  }
  const firstPrompt = firstUserPrompt(records);
  if (!title) title = firstPrompt ? firstPrompt.slice(0, 60) : '(untitled)';
  return { path: meta.path, sessionId, title, firstPrompt, mtime: meta.mtime, cwd, gitBranch };
}
