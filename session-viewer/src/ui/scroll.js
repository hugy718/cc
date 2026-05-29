export function clampTop(totalRows, height, top) {
  const max = Math.max(0, totalRows - height);
  return Math.min(Math.max(0, top), max);
}

// Return a new `top` so the rows belonging to item `cursorIdx` are visible.
export function ensureVisible(rows, height, cursorIdx, top) {
  let first = -1;
  let last = -1;
  rows.forEach((r, i) => {
    if (r.idx === cursorIdx) { if (first < 0) first = i; last = i; }
  });
  if (first < 0) return clampTop(rows.length, height, top);
  let t = top;
  if (first < t) t = first;
  if (last >= t + height) t = last - height + 1;
  return clampTop(rows.length, height, t);
}
