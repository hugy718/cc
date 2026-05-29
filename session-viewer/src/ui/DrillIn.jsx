import React from 'react';
import { Box, Text } from 'ink';
import { ScrollView } from './ScrollView.jsx';

export function DrillIn({ title, rows, top, height }) {
  return (
    <Box flexDirection="column" height={height + 3}>
      <Text color="cyan">▸ {title}</Text>
      <Box flexGrow={1} borderStyle="round" borderColor="blue" paddingX={1}>
        <ScrollView rows={rows} height={height} top={top} />
      </Box>
      <Text dimColor>esc close · ↑↓ scroll · q quit</Text>
    </Box>
  );
}
