#!/bin/bash
# Xnip Pro patch — watch & inject via frida (BACKUP channel only).
# Primary unlock is the static binary patch on XnipLibrary.framework.
# This watcher only attaches to the PATCHED copy in ~/Applications so it
# never fights the SIP-protected MAS original in /Applications.
# frida -l keeps the JS runtime resident (setInterval in patch.js).

FRIDA="/Users/lingoking/.local/share/mise/installs/python/3.12.12/bin/frida"
PATCH_JS="/Users/lingoking/.pi/xnip-patch/patch.js"
LOG=/tmp/xnip-patch.stdout.log

# Only the patched copy — strict anchored match, no /Applications fallback.
XNP_PID=$(pgrep -f "^/Users/$USER/Applications/Xnip.app/Contents/MacOS/Xnip$" | head -1)

if [ -n "$XNP_PID" ]; then
    # Skip if frida already attached to this pid (avoid stacking on 10s poll)
    if pgrep -f "frida.*-p[ =]$XNP_PID" >/dev/null 2>&1; then
        exit 0
    fi
    echo "$(date): attaching frida to patched Xnip pid=$XNP_PID" >> "$LOG"
    # No -q: keep process alive so patch.js setInterval runs.
    "$FRIDA" -p "$XNP_PID" --runtime=v8 -l "$PATCH_JS" >> "$LOG" 2>&1
    echo "$(date): frida exited (pid=$XNP_PID)" >> "$LOG"
fi
# Xnip not running → exit silently; launchd StartInterval re-runs us.
