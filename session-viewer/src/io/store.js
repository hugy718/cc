import { readFile, readdir, stat, open } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { parseLines } from '../core/parser.js';
import { summarize, firstUserPrompt } from '../core/sessionIndex.js';

export function defaultRoot() {
  return path.join(homedir(), '.claude', 'projects');
}

// Read the WHOLE file (only used for the single session the user opens).
export async function readLines(filePath) {
  const text = await readFile(filePath, 'utf8');
  return text.split('\n');
}

// Read at most `maxBytes` from the start and return only the COMPLETE lines.
// Bounds memory/IO per file regardless of session size — used for the index
// and for subagent first-prompts. (Titles/first prompts live at the top.)
export async function readHead(filePath, maxBytes = 131072) {
  const fh = await open(filePath, 'r');
  try {
    const buf = Buffer.alloc(maxBytes);
    const { bytesRead } = await fh.read(buf, 0, maxBytes, 0);
    const text = buf.subarray(0, bytesRead).toString('utf8');
    const lines = text.split('\n');
    if (bytesRead === maxBytes && lines.length > 1) lines.pop(); // drop partial last line
    return lines;
  } finally {
    await fh.close();
  }
}

export async function listProjects(root) {
  let entries;
  try { entries = await readdir(root, { withFileTypes: true }); }
  catch { return []; }
  return entries
    .filter((e) => e.isDirectory())
    .map((e) => ({ name: e.name, dir: path.join(root, e.name) }));
}

export async function listSessions(projectDir) {
  let entries;
  try { entries = await readdir(projectDir, { withFileTypes: true }); }
  catch { return []; }
  const out = [];
  for (const e of entries) {
    if (!e.isFile() || !e.name.endsWith('.jsonl')) continue;
    const p = path.join(projectDir, e.name);
    try {
      const s = await stat(p); // file may vanish between readdir and stat on a live folder
      out.push({ id: e.name.replace(/\.jsonl$/, ''), path: p, mtime: s.mtimeMs });
    } catch { /* skip a file that disappeared mid-scan */ }
  }
  return out;
}

// Cheap: readdir + stat only, NO file content read. Returns stubs sorted
// newest-first so the UI can render the list instantly.
export async function listAllSessions(root) {
  const projects = await listProjects(root);
  const out = [];
  for (const proj of projects) {
    for (const sess of await listSessions(proj.dir)) {
      out.push({
        ...sess,
        project: proj.name,
        projectDir: proj.dir,
        title: '…',
        firstPrompt: '',
      });
    }
  }
  out.sort((a, b) => b.mtime - a.mtime);
  return out;
}

// Enrich stubs in place (copied) with title/cwd/branch via bounded head-reads,
// running `concurrency` at a time and calling onBatch(snapshot) every batchSize.
export async function enrichSummaries(stubs, { concurrency = 8, batchSize = 24, onBatch } = {}) {
  const result = stubs.map((s) => ({ ...s }));
  let next = 0;
  let done = 0;
  async function worker() {
    while (next < result.length) {
      const i = next++;
      try {
        const head = await readHead(result[i].path);
        const sum = summarize(head, { path: result[i].path, mtime: result[i].mtime });
        result[i] = { ...result[i], ...sum };
      } catch {
        result[i] = { ...result[i], title: result[i].id, unreadable: true };
      }
      done++;
      if (onBatch && done % batchSize === 0) onBatch(result.slice());
    }
  }
  await Promise.all(Array.from({ length: Math.max(1, concurrency) }, worker));
  if (onBatch) onBatch(result.slice());
  return result;
}

// Convenience used by tests / simple callers: list + enrich fully.
export async function buildIndex(root) {
  const stubs = await listAllSessions(root);
  const summaries = await enrichSummaries(stubs, { concurrency: 8 });
  return { summaries, unreadable: summaries.filter((s) => s.unreadable).length };
}

// Read lazily — only when the user drills into a subagent. Bounded head-read.
export async function readSubagentSummaries(projectDir, sessionId) {
  const dir = path.join(projectDir, sessionId, 'subagents');
  let entries;
  try { entries = await readdir(dir, { withFileTypes: true }); }
  catch { return []; }
  const out = [];
  for (const e of entries) {
    if (!e.isFile() || !e.name.startsWith('agent-') || !e.name.endsWith('.jsonl')) continue;
    const p = path.join(dir, e.name);
    try {
      const { records } = parseLines(await readHead(p));
      const agentId = records.find((r) => r.agentId)?.agentId
        ?? e.name.slice('agent-'.length).replace(/\.jsonl$/, '');
      out.push({ file: p, agentId, firstPrompt: firstUserPrompt(records) });
    } catch { /* skip an agent file that can't be read */ }
  }
  return out;
}
