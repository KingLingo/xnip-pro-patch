#!/bin/bash
# Xnip Pro patch — watch & inject via frida
# Runs as LaunchAgent; restarts frida whenever Xnip starts

FRIDA="@FRIDA@"
PATCH_JS="@HOME@/.pi/xnip-patch/patch.js"
LOG=/tmp/xnip-patch.stdout.log

# Find main Xnip process (patched version in ~/Applications)
XNP_PID=$(pgrep -f "^/Users/$USER/Applications/Xnip.app/Contents/MacOS/Xnip$" | head -1)
if [ -z "$XNP_PID" ]; then
    # also try /Applications (unpatched original)
    XNP_PID=$(pgrep -f "^/Applications/Xnip.app/Contents/MacOS/Xnip$" | head -1)
fi

if [ -n "$XNP_PID" ]; then
    echo "$(date): Xnip found pid=$XNP_PID, attaching frida" >> "$LOG"
    "$FRIDA" -p "$XNP_PID" -q --runtime=v8 -l "$PATCH_JS" >> "$LOG" 2>&1
    echo "$(date): frida detached" >> "$LOG"
else
    echo "$(date): Xnip not running" >> "$LOG"
fi
