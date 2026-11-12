# Xnip Pro Patch

Xnip 2.5.1 (build 79) 运行时 Pro 解锁补丁 — 通过 Frida 注入强制 `XNPSystemStatus._p = _p1 = 1`。

## 原理

Xnip 的 Pro 状态判定在 `XnipLibrary.framework` 的 `XNPSystemStatus` 单例：

```asm
-[XNPSystemStatus hasP]:
    movb $0x1, %al
    cmpb $0x0, 0x8(%rdi)    ; ivar _p
    jne  0x32fda            ; _p != 0 → return true
    cmpb $0x0, 0x9(%rdi)    ; ivar _p1
    setne %al               ; return (_p1 != 0)
```

`p1a` 和 `hasP` 实现相同（可能是遗留兼容判定）。它们被调用处包括：
- **截图水印**（`drawStepAndCommentWithTextRect:` 系列函数）— `p1a` 为 0 时画 Xnip logo+文字
- **标注/编辑功能**的 Pro 门禁

`init` 从 `NSUserDefaults.standardUserDefaults` 读三个 key 初始化 ivar：
| ivar | offset | key | 类型 |
|------|--------|-----|------|
| `_p` | +0x08 | `kXnipP` | BOOL |
| `_p1` | +0x09 | `kXnipP1` | BOOL |
| `_pExpirationTime` | +0x10 | `kXnipPExpirationTime` | NSDate* |

`setP:`/`setP1:` 写回 ivar + defaults + post `_pChanged` 通知。

## 部署

```bash
# 1. 原版 Xnip 已装于 /Applications（MAS 版）
# 2. 运行 installer — 复制到 ~/Applications，签名，装 LaunchAgent
bash scripts/install.sh

# 3. 启动 patch 版
open ~/Applications/Xnip.app
```

Installer 做四件事：
1. 复制 `/Applications/Xnip.app` → `~/Applications/Xnip.app`（MAS 签名在 `/Applications` 受 SIP 保护无法改）
2. 重签所有组件：`get-task-allow` + adhoc 签名（去掉 MAS-only entitlements 否则 launchd 拒启动）
3. 部署 `patch.js` 到 `~/.pi/xnip-patch/`
4. 装 `com.user.xnip-patch` LaunchAgent — watch.sh 每 10s 检查 Xnip 进程并 attach frida

## 验证

```bash
frida -p $(pgrep -f "Xnip.app/Contents/MacOS/Xnip" | head -1) -q --runtime=v8 -e '
const ss = ObjC.classes.XNPSystemStatus.sharedSystemStatus();
console.log("hasP:", ss.hasP(), "p1a:", ss.p1a());
'
# → hasP: true p1a: true
```

## 回滚

```bash
launchctl bootout gui/$(id -u)/com.user.xnip-patch
rm ~/Library/LaunchAgents/com.user.xnip-patch.plist
rm -rf ~/.pi/xnip-patch ~/Applications/Xnip.app
# 用 /Applications/Xnip.app 原版
```

## 限制

- 需要 frida (`pip install frida-tools`)
- patch 版路径是 `~/Applications/Xnip.app`（不是 `/Applications`）
- MAS 版 receipt 里没 IAP entry，补丁只是绕过客户端判定 — 服务器端不会认
- 原版 `/Applications/Xnip.app` 保留不动，随时可回滚
