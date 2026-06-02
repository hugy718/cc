import { diffLines } from 'diff';

export function lineDiff(oldStr, newStr) {
  const parts = diffLines(String(oldStr ?? ''), String(newStr ?? ''));
  const lines = [];
  let added = 0;
  let removed = 0;
  for (const part of parts) {
    const type = part.added ? 'add' : part.removed ? 'del' : 'ctx';
    const segs = part.value.split('\n');
    if (segs.length && segs[segs.length - 1] === '') segs.pop();
    for (const text of segs) {
      lines.push({ type, text });
      if (type === 'add') added++;
      else if (type === 'del') removed++;
    }
  }
  return { lines, added, removed };
}

export function editDiff(toolName, input) {
  if (toolName === 'Write') return lineDiff('', input?.content ?? '');
  return lineDiff(input?.old_string ?? '', input?.new_string ?? '');
}
