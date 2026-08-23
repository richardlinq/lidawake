#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Lid Shut: Toggle
# @raycast.mode compact
# @raycast.icon 🔀
# @raycast.packageName Lid Shut
# @raycast.description Switch between Keep Running and Let It Sleep
"$HOME/.local/bin/lidawake" toggle 2>&1 | head -2
