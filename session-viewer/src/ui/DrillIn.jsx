import React from 'react';
import { Box, Text } from 'ink';
import { ScrollView } from './ScrollView.jsx';

// Content-sized (NOT full-terminal-height): title + bordered scroll area +
// footer = `height + 4` lines. Callers pass height = termRows - 5 so the whole
// drill view is one line short of the terminal, avoiding the repaint scroll
// that causes flicker.
export function DrillIn({ title, rows, top, height }) {
  return (
    <Box flexDirection="column">
      <Text color="cyan">▸ {title}</Text>
      <Box borderStyle="round" borderColor="blue" paddingX={1}>
        <ScrollView rows={rows} height={height} top={top} />
      </Box>
      <Text dimColor>esc close · ↑↓ scroll · q quit</Text>
    </Box>
  );
}
