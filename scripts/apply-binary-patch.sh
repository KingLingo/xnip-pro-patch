#!/bin/bash
# apply-binary-patch.sh — 对 ~/Applications/Xnip.app 内 XnipLibrary.framework
# 的 XNPSystemStatus 判定函数打恒真补丁 (mov w0,#1; ret / mov eax,1; ret)。
#
# 判定矩阵 (Xnip 2.5.1 build 79, arm64 slice fileoff=0x10c000, x86=0x4000):
#   -[XNPSystemStatus p]     @0x26164 arm / 0x32e39 x86 → ldrb w0,[x0,#8]
#   -[XNPSystemStatus p1]    @0x26200 arm / 0x32ef4 x86 → ldrb w0,[x0,#9]
#   -[XNPSystemStatus p1a]   @0x2629c arm / 0x32faf x86 → _p || _p1 (ivar,非getter)
#   -[XNPSystemStatus hasP]  @0x262b8 arm / 0x32fc7 x86 → _p || _p1 (ivar,非getter)
# 注意: hasP/p1a 直接读 ivar 而非调 p/p1 getter → 四者都必须 patch。
#
# arm64 patch: mov w0,#1; ret; nop*N   (20 00 80 52 c0 03 5f d6 1f 20 03 d5...)
# x86-64 patch: mov eax,1; ret; nop*N  (b8 01 00 00 00 c3 90...)
#
# 用法: bash apply-binary-patch.sh [~/Applications/Xnip.app]

set -e
APP="${1:-$HOME/Applications/Xnip.app}"
LIB="$APP/Contents/Frameworks/XnipLibrary.framework/Versions/A/XnipLibrary"

[ -f "$LIB" ] || { echo "ERROR: $LIB not found"; exit 1; }

python3 - "$LIB" <<'PY'
import sys, struct
path = sys.argv[1]
data = bytearray(open(path, 'rb').read())

ARM, X86 = 0x10c000, 0x4000   # slice file offsets in fat Mach-O

# arm64: mov w0,#1; ret; nop*4  (24 bytes to overwrite for p1a/hasP)
ARM_PATCH_24 = bytes([0x20,0x00,0x80,0x52, 0xc0,0x03,0x5f,0xd6] + [0x1f,0x20,0x03,0xd5]*4)
# arm64: mov w0,#1; ret          (8 bytes — p/p1 have no room for nops)
ARM_PATCH_8  = bytes([0x20,0x00,0x80,0x52, 0xc0,0x03,0x5f,0xd6])

# x86-64: mov eax,1; ret; nop*18 (20 bytes for p1a/hasP)
X86_PATCH_20 = bytes([0xb8,0x01,0x00,0x00,0x00,0xc3] + [0x90]*14)
# x86-64: mov eax,1; ret; nop*4  (10 bytes for p/p1)
X86_PATCH_10 = bytes([0xb8,0x01,0x00,0x00,0x00,0xc3] + [0x90]*4)

targets = [
    # (slice_base, vmaddr, patch, name)
    (ARM, 0x26164, ARM_PATCH_8,  "p"),
    (ARM, 0x26200, ARM_PATCH_8,  "p1"),
    (ARM, 0x2629c, ARM_PATCH_24, "p1a"),
    (ARM, 0x262b8, ARM_PATCH_24, "hasP"),
    (X86, 0x32e39, X86_PATCH_10, "p"),
    (X86, 0x32ef4, X86_PATCH_10, "p1"),
    (X86, 0x32faf, X86_PATCH_20, "p1a"),
    (X86, 0x32fc7, X86_PATCH_20, "hasP"),
]

for base, addr, patch, name in targets:
    off = base + addr
    old = bytes(data[off:off+len(patch)])
    data[off:off+len(patch)] = patch
    print(f"  [{name}] @0x{addr:x}  {old.hex()} -> {patch.hex()}")

open(path, 'wb').write(data)
print("[*] binary patch applied (8 sites, both arches)")
PY

echo "[*] Re-signing XnipLibrary + app"
ENT=$(mktemp -t xnip-ent).plist
cat > "$ENT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>
EOF
codesign --sign - --force --entitlements "$ENT" "$APP/Contents/Frameworks/XnipLibrary.framework" >/dev/null 2>&1
codesign --sign - --force --deep --entitlements "$ENT" "$APP" >/dev/null 2>&1
rm -f "$ENT"
codesign --verify --deep --strict "$APP" && echo "[+] verify OK"
echo "[+] Done. hasP/p1a/p/p1 now hard-coded true."
