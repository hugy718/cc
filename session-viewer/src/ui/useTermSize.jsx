import { useState, useEffect } from 'react';

export function useTermSize() {
  const read = () => ({ cols: process.stdout.columns || 80, rows: process.stdout.rows || 24 });
  const [size, setSize] = useState(read());
  useEffect(() => {
    const on = () => setSize(read());
    process.stdout.on('resize', on);
    return () => process.stdout.off('resize', on);
  }, []);
  return size;
}
