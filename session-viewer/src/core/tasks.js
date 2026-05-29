import { indexToolResults } from './normalize.js';

export function buildTaskBoard(records) {
  const results = indexToolResults(records);
  const tasks = new Map();
  let seq = 0;
  for (const rec of records) {
    if (rec.type !== 'assistant') continue;
    const content = rec.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type !== 'tool_use') continue;
      if (block.name === 'TaskCreate') {
        seq++;
        const id = results.get(block.id)?.structured?.task?.id ?? String(seq);
        tasks.set(id, {
          id,
          subject: block.input?.subject ?? `Task ${id}`,
          description: block.input?.description ?? '',
          finalStatus: 'created',
          trail: ['created'],
        });
      } else if (block.name === 'TaskUpdate') {
        const id = block.input?.taskId;
        const status = block.input?.status;
        if (!id || !status) continue;
        let t = tasks.get(id);
        if (!t) {
          t = { id, subject: `Task ${id}`, description: '', finalStatus: 'created', trail: ['created'] };
          tasks.set(id, t);
        }
        t.trail.push(status);
        t.finalStatus = status;
      }
    }
  }
  return [...tasks.values()];
}
