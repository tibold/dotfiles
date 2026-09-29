#!/usr/bin/env bash
# Claude Code status line:
#   ctx: <bar stretched to terminal width> N%  5h: N% <icon> HH:MM  7d: N% <icon> Ddd HH:MM
# Input is the status line JSON on stdin. resets_at is Unix epoch seconds.
# Set STATUSLINE_MARGIN to change the right-hand safety margin (default 8 columns).
export LC_ALL=C.UTF-8

input=$(cat)
ctx=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_r=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_r=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# rst <epoch> <date format>: prints " <icon> <time>" (nf-fa-refresh, U+F021), or nothing if missing/invalid.
rst() {
  case "$1" in ''|*[!0-9]*) return ;; esac
  local t
  # GNU date takes -d @epoch; BSD date (macOS) takes -r epoch.
  t=$(date -d "@$1" +"$2" 2>/dev/null || date -r "$1" +"$2" 2>/dev/null) && [ -n "$t" ] && printf '  %s' "$t"
}

# Terminal width: the live tty first, then COLUMNS, then tput, then 100.
# COLUMNS goes second because a Neovim :terminal buffer sets it once at spawn,
# so it goes stale when the window is resized or split.
tty_w=$({ stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2)
w=${tty_w:-${COLUMNS:-$(tput cols 2>/dev/null </dev/null)}}
case "$w" in ''|*[!0-9]*) w=100 ;; esac
# Debug: STATUSLINE_DEBUG=1 logs where the width came from.
[ -n "$STATUSLINE_DEBUG" ] && echo "$(date +%T) tty=[$tty_w] COLUMNS=[$COLUMNS] tput=[$(tput cols 2>/dev/null </dev/null)] NVIM=[${NVIM:+set}] used=$w" >> ~/.claude/statusline-debug.log
w=$((w - ${STATUSLINE_MARGIN:-8}))

# Colours: the terminal's own ANSI palette rather than fixed hex, so they follow
# whatever theme it has. Rio's config maps these four onto the ArchPillar
# cyberpunk tokens, so there they are --accent, --warning, --danger and --fg-2.
esc=$(printf '\033')
MINT="$esc[32m"    # green
AMBER="$esc[33m"   # yellow
RED="$esc[31m"     # red
DIM="$esc[37m"     # white
RESET="$esc[0m"

# The colour for a percentage used: mint, then amber from 50, red from 80.
# Sets $colour rather than printing it, because the bar loop calls it per cell
# and a $(...) there would fork once per column.
level() {
  if [ "$1" -lt 50 ]; then colour=$MINT
  elif [ "$1" -lt 80 ]; then colour=$AMBER
  else colour=$RED
  fi
}

# Everything below is built twice over: the string with escapes in it, and
# its width in columns, which the escapes would otherwise inflate.
tail=''
tail_w=0
# limit <label> <percent> <resets_at> <date format>
limit() {
  local p t
  p=$(printf '%.0f' "$2")
  t=$(rst "$3" "$4")
  level "$p"
  tail="$tail  $DIM$1:$RESET $colour$p%$RESET$DIM$t$RESET"
  tail_w=$((tail_w + 2 + ${#1} + 2 + ${#p} + 1 + ${#t}))
}
[ -n "$five" ] && limit 5h "$five" "$five_r" '%H:%M'
[ -n "$week" ] && limit 7d "$week" "$week_r" '%a %H:%M'

if [ -n "$ctx" ]; then
  r=$(printf '%.0f' "$ctx")
  head='ctx: '
  suf=" $r%"
  bw=$((w - ${#head} - ${#suf} - tail_w))
  [ "$bw" -lt 5 ] && bw=5
  n=$(( (r * bw + 50) / 100 ))
  [ "$n" -gt "$bw" ] && n=$bw
  # Each filled cell takes the colour of where it sits on the bar, so the bar
  # steps from mint to amber to red as it fills. An escape is written only
  # where the colour changes.
  bar=''
  last=''
  i=0
  while [ "$i" -lt "$bw" ]; do
    if [ "$i" -lt "$n" ]; then
      level $((i * 100 / bw))
      ch='█'
    else
      colour=$DIM
      ch='░'
    fi
    [ "$colour" != "$last" ] && bar="$bar$colour" && last=$colour
    bar="$bar$ch"
    i=$((i + 1))
  done
  level "$r"
  out="$DIM$head$RESET$bar$RESET $colour$r%$RESET$tail"
  out_w=$((${#head} + bw + ${#suf} + tail_w))
else
  out="${tail#  }"
  out_w=$((tail_w - 2))
fi

# Right-align with non-breaking spaces (plain spaces get trimmed). The NBSP is
# made by printf because BSD sed (macOS) does not understand \x escapes.
nbsp=$(printf '\302\240')
pad=$((w - out_w))
[ "$pad" -gt 0 ] && printf '%*s' "$pad" '' | sed "s/ /$nbsp/g"
printf '%s' "$out"
