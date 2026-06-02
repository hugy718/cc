import React from 'react';
import { Box, Text } from 'ink';
import TextInput from 'ink-text-input';

// `rows` is the exact list App navigates (from R.sessionListRows): the cursor
// index maps 1:1 to a visible row, so the highlight and the ↑↓ traversal can
// never disagree. We only window/scroll and paint the selection here.
export function SessionList({ rows, cursor, searching, query, onChange, onSubmit, height }) {
  const listHeight = Math.max(1, height - 1); // first line is the search field
  const sel = Math.max(0, Math.min(cursor, rows.length - 1));
  const top = Math.max(0, Math.min(sel - Math.floor(listHeight / 2), Math.max(0, rows.length - listHeight)));
  const slice = rows.slice(top, top + listHeight);

  return (
    <Box flexDirection="column">
      {searching ? (
        <Box>
          <Text color="cyan">/ </Text>
          <TextInput value={query} onChange={onChange} onSubmit={onSubmit} placeholder="filter…" />
        </Box>
      ) : (
        <Text dimColor>/ {query || 'search'}</Text>
      )}
      {slice.map((r, i) => {
        const idx = top + i;
        const selected = idx === sel && r.kind !== 'empty';
        const color = r.style === 'group' ? 'blue' : selected ? 'white' : 'gray';
        return (
          <Text key={idx} color={color} bold={r.style === 'group'} inverse={!!selected}>
            {r.text}
          </Text>
        );
      })}
    </Box>
  );
}
