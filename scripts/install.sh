#!/bin/bash
# Xnip Pro patch installer
# Re-signs Xnip with get-task-allow + adhoc, deploys patch.js + LaunchAgent

set -e

XNP_SRC="${1:-/Applications/Xnip.app}"
XNP_DST="$HOME/Applications/Xnip.app"
DEPLOY_DIR="$HOME/.pi/xnip-patch"
PLIST_NAME="com.user.xnip-patch.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"
ENTITLEMENTS="$(mktemp -t xnip-entitlements).plist"
FRIDA=$(which frida 2>/dev/null || echo "")
FRIDA_DIR=""

# --- Find frida ---
if [ -z "$FRIDA" ]; then
    for c in "$HOME/.local/share/mise/installs/python"/*/bin/frida "$HOME/.local/bin/frida" /opt/homebrew/bin/frida; do
        [ -x "$c" ] && FRIDA="$c" && break
    done
fi
[ -z "$FRIDA" ] && { echo "ERROR: frida not found. Install via: pip install frida-tools"; exit 1; }
FRIDA_DIR=$(dirname "$FRIDA")

# --- Cleanup root-owned leftovers ---
rm -f /tmp/xnip-patch.*.log 2>/dev/null || true

# --- 1. Copy Xnip to ~/Applications ---
if [ ! -d "$XNP_DST" ]; then
    echo "[*] Copying $XNP_SRC → $XNP_DST"
    mkdir -p "$HOME/Applications"
    cp -R "$XNP_SRC" "$XNP_DST"
    # remove compressed flag (MAS SIP-protected files)
    find "$XNP_DST" -flags +compressed -exec chflags nocompressed {} \; 2>/dev/null || true
fi

# --- 2. Write entitlements ---
cat > "$ENTITLEMENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.get-task-allow</key>
	<true/>
</dict>
</plist>
EOF

# --- 3. Re-sign all components ---
echo "[*] Re-signing with get-task-allow + adhoc"
SIGN_COMPONENTS=(
    "$XNP_DST/Contents/Library/LoginItems/XnipHelper.app/Contents/Frameworks/XnipLibrary.framework"
    "$XNP_DST/Contents/Library/LoginItems/XnipHelper.app/Contents/Frameworks/DKDrawKit.framework"
    "$XNP_DST/Contents/Library/LoginItems/XnipHelper.app"
    "$XNP_DST/Contents/Library/LoginItems/XnipLoginHelperApp.app"
    "$XNP_DST/Contents/Frameworks/XnipLibrary.framework"
    "$XNP_DST/Contents/Frameworks/DKDrawKit.framework"
    "$XNP_DST"
)
for c in "${SIGN_COMPONENTS[@]}"; do
    [ -e "$c" ] || continue
    echo "  signing: $(basename "$c")"
    codesign --sign - --force --deep --entitlements "$ENTITLEMENTS" "$c" 2>&1 | grep -v "replacing existing" || true
done
rm -f "$ENTITLEMENTS"
echo "[*] Signature done"

# --- 3.5 Static binary patch (PRIMARY unlock channel) ---
echo "[*] Applying static binary patch (hasP/p1a/p/p1 → constant true)"
bash "$(dirname "$0")/apply-binary-patch.sh" "$XNP_DST"

# --- 3.6 defaults belt-and-suspenders (kXnipP/kXnipP1 → true) ---
echo "[*] Writing Pro defaults to app + group domain"
for dom in com.zzd.Xnip ME7L72N3S3.group.com.zzd.Xnip; do
    defaults write "$dom" kXnipP  -bool true 2>/dev/null || true
    defaults write "$dom" kXnipP1 -bool true 2>/dev/null || true
    defaults write "$dom" kXnipPExpirationTime -int 4102444800 2>/dev/null || true
done

# --- 4. Deploy patch files ---
echo "[*] Deploying patch to $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
cp "$(dirname "$0")/patch.js" "$DEPLOY_DIR/patch.js"
cp "$(dirname "$0")/watch.sh" "$DEPLOY_DIR/watch.sh"
chmod +x "$DEPLOY_DIR/watch.sh"

# --- 5. Install LaunchAgent ---
echo "[*] Installing LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|@HOME@|$HOME|g" \
    -e "s|@FRIDA@|$FRIDA|g" \
    -e "s|@FRIDA_DIR@|$FRIDA_DIR|g" \
    "$(dirname "$0")/../launchagent/com.user.xnip-patch.plist" > "$PLIST_DST"

# --- 6. Boot out old, bootstrap new ---
launchctl bootout "gui/$(id -u)/com.user.xnip-patch" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" || echo "WARNING: bootstrap failed (may need logout/login)"

echo ""
echo "=== Done ==="
echo "Patched Xnip:  $XNP_DST"
echo "Patch files:   $DEPLOY_DIR"
echo "LaunchAgent:   $PLIST_DST"
echo "Logs:          /tmp/xnip-patch.stdout.log /tmp/xnip-patch.stderr.log"
echo ""
echo "Start patched Xnip with:"
echo "  open ~/Applications/Xnip.app"
echo ""
echo "Verify:"
echo "  frida -p \$(pgrep -f Xnip.app/Contents/MacOS/Xnip | head -1) -q --runtime=v8 -e 'console.log(ObjC.classes.XNPSystemStatus.sharedSystemStatus().hasP())'"
