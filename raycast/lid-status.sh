#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Lid Shut: Status
# @raycast.mode inline
# @raycast.refreshTime 15s
# @raycast.icon 💤
# @raycast.packageName Lid Shut
# @raycast.description Current mode, power source, battery and lid state
s="$("$HOME/.local/bin/lidawake" status 2>/dev/null)"
printf '%s\n' "$s" | awk '
  /^State/ {v=$0; sub(/^[^:]*: */,"",v); a=v}
  /^Mode/  {v=$0; sub(/^[^:]*: */,"",v); b=v}
  /^Power/ {v=$0; sub(/^[^:]*: */,"",v); c=v}
  END{ print a "  ·  " b "  ·  " c }'
