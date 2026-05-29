// Parse Claude Code session JSONL into raw records.
// null  = blank line (ignore), undefined = malformed (count as skipped).
export function parseLine(line) {
  const t = String(line).trim();
  if (!t) return null;
  try {
    return JSON.parse(t);
  } catch {
    return undefined;
  }
}

export function parseLines(input) {
  const lines = Array.isArray(input) ? input : String(input).split('\n');
  const records = [];
  let skipped = 0;
  for (const line of lines) {
    const r = parseLine(line);
    if (r === null) continue;
    if (r === undefined) { skipped++; continue; }
    records.push(r);
  }
  return { records, skipped };
}
