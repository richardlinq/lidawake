#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Lid Shut: Keep Running
# @raycast.mode compact
# @raycast.icon ☕️
# @raycast.packageName Lid Shut
# @raycast.description Keep working with the lid closed
"$HOME/.local/bin/lidawake" auto 2>&1 | head -2
