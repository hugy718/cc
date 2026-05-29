// Turn raw records into an ordered list of renderable Steps,
// pairing each tool_use with its result.

function blockResultText(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.map((b) => (b.type === 'text' ? b.text : '')).join('\n');
  }
  return '';
}

// Map tool_use_id -> { text, structured, isError }
export function indexToolResults(records) {
  const map = new Map();
  for (const rec of records) {
    const content = rec.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type === 'tool_result') {
        map.set(block.tool_use_id, {
          text: blockResultText(block.content),
          structured: rec.toolUseResult,
          isError: block.is_error === true,
        });
      }
    }
  }
  return map;
}

function subtypeFor(name) {
  switch (name) {
    case 'Edit': return 'edit';
    case 'Write': return 'write';
    case 'Bash': return 'bash';
    case 'Read': case 'Grep': case 'Glob': return 'read';
    case 'Agent': return 'agent';
    case 'TaskCreate': case 'TaskUpdate': case 'TaskList': return 'task';
    default: return 'other';
  }
}

export function toSteps(records) {
  const results = indexToolResults(records);
  const steps = [];
  for (const rec of records) {
    if (rec.type !== 'assistant' && rec.type !== 'user') continue;
    if (rec.isMeta) continue;
    const content = rec.message?.content;
    const ts = rec.timestamp;

    if (typeof content === 'string') {
      if (!content.trim()) continue;
      steps.push({ kind: rec.type === 'user' ? 'userPrompt' : 'assistantText', text: content, ts });
      continue;
    }
    if (!Array.isArray(content)) continue;

    for (const block of content) {
      if (block.type === 'text' && block.text?.trim()) {
        steps.push({ kind: rec.type === 'user' ? 'userPrompt' : 'assistantText', text: block.text, ts });
      } else if (block.type === 'thinking') {
        const text = block.thinking ?? block.text ?? '';
        if (text.trim()) steps.push({ kind: 'thinking', text, ts });
      } else if (block.type === 'tool_use') {
        steps.push({
          kind: 'tool',
          tool: block.name,
          subtype: subtypeFor(block.name),
          input: block.input ?? {},
          id: block.id,
          result: results.get(block.id) ?? null,
          ts,
        });
      }
      // tool_result blocks are intentionally skipped (surfaced via their tool_use step)
    }
  }
  return steps;
}
