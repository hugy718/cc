import React from 'react';
import { Box, Text } from 'ink';

const STYLE = {
  user: { color: 'yellow' },
  ai: { color: 'green', bold: true },
  plain: {},
  dim: { color: 'gray' },
  edit: { color: 'blue' },
  bash: { color: 'greenBright' },
  add: { color: 'green' },
  del: { color: 'red' },
  ok: { color: 'green' },
  run: { color: 'yellow' },
  meta: { color: 'gray' },
  accent: { color: 'cyan' },
  group: { color: 'blue', bold: true },
  sess: { color: 'gray' },
};

// rows: Row[]; cursorIdx highlights the head row of the cursored item (optional).
export function ScrollView({ rows, height, top, cursorIdx }) {
  const slice = rows.slice(top, top + height);
  return (
    <Box flexDirection="column">
      {slice.map((r, i) => {
        const isCursor = r._head && cursorIdx !== undefined && r.idx === cursorIdx;
        return (
          <Text key={top + i} {...(STYLE[r.style] || {})} inverse={isCursor}>
            {(isCursor ? '▌ ' : '  ') + r.text}
          </Text>
        );
      })}
    </Box>
  );
}
