import React from 'react';
import { Box, Text } from 'ink';
import TextInput from 'ink-text-input';
import { sessionListRows } from './render.js';

export function SessionList({ groups, selectedPath, searching, query, onChange, onSubmit, height, width }) {
  const rows = sessionListRows(groups, width);
  let sel = rows.findIndex((r) => r.path && r.path === selectedPath);
  if (sel < 0) sel = 0;
  const listHeight = Math.max(1, height - 1); // first line is the search field
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
        const selected = r.path && r.path === selectedPath;
        const color = r.style === 'group' ? 'blue' : selected ? 'white' : 'gray';
        return (
          <Text key={top + i} color={color} bold={r.style === 'group'} inverse={!!selected}>
            {r.text}
          </Text>
        );
      })}
    </Box>
  );
}
