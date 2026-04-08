#!/bin/bash
input=$(cat 2>/dev/null)

# Parse JSON input from Claude Code (if available)
if [ -n "$input" ]; then
  eval "$(echo "$input" | python3 -c "
import sys, json, time
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cw = d.get('context_window', {})
cu = cw.get('current_usage') or {}
model_obj = d.get('model', {})
if isinstance(model_obj, dict):
    model = model_obj.get('display_name', model_obj.get('id', 'unknown'))
else:
    model = str(model_obj) if model_obj else ''
rl = d.get('rate_limits', {})
fh = rl.get('five_hour', {})
sd = rl.get('seven_day', {})
fh_pct = f\"{fh.get('used_percentage'):.2f}\" if fh.get('used_percentage') is not None else ''
sd_pct = f\"{sd.get('used_percentage'):.2f}\" if sd.get('used_percentage') is not None else ''
fh_reset = fh.get('resets_at')
sd_reset = sd.get('resets_at')
def fmt_reset(ts):
    if ts is None: return ''
    remaining = int(ts) - int(time.time())
    if remaining <= 0: return 'now'
    h, m = divmod(remaining // 60, 60)
    return f'{h}h{m}m' if h else f'{m}m'
fh_reset_str = fmt_reset(fh_reset)
sd_reset_str = fmt_reset(sd_reset)
print(f\"model={repr(model)}\"
      f\" fh_pct={repr(str(fh_pct))}\"
      f\" sd_pct={repr(str(sd_pct))}\"
      f\" fh_reset={repr(fh_reset_str)}\"
      f\" sd_reset={repr(sd_reset_str)}\")
" 2>/dev/null)" 2>/dev/null
fi

# Build rate limit display with color coding (green <50%, yellow 50-80%, red >80%)
color_pct() {
  local pct="$1"
  if [ -z "$pct" ]; then echo ""; return; fi
  local val="${pct%.*}"
  if [ "$val" -ge 80 ] 2>/dev/null; then printf "\033[31m%s%%\033[00m" "$pct"
  elif [ "$val" -ge 50 ] 2>/dev/null; then printf "\033[33m%s%%\033[00m" "$pct"
  else printf "\033[32m%s%%\033[00m" "$pct"; fi
}

fh_display=$(color_pct "$fh_pct")
sd_display=$(color_pct "$sd_pct")

printf "\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m" \
  "$(whoami)" "$(hostname -s)" "$(pwd)"

[ -n "$model" ] && printf " \033[33m%s\033[00m" "$model"

if [ -n "$fh_pct" ]; then
  printf " 5h:%b" "$fh_display"
  [ -n "$fh_reset" ] && printf "(%s)" "$fh_reset"
fi
if [ -n "$sd_pct" ]; then
  printf " 7d:%b" "$sd_display"
  [ -n "$sd_reset" ] && printf "(%s)" "$sd_reset"
fi
