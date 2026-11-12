# Xnip Pro Patch

Xnip 2.5.1 (build 79) Pro 解锁 — **静态二进制补丁为主，Frida 注入为备份调试手段**。

## 原理

Pro 状态判定在 `XnipLibrary.framework` 的 `XNPSystemStatus` 单例：

```asm
; arm64 (fileoff 0x10c000+vmaddr)
-[XNPSystemStatus hasP]  @0x262b8 : ldrb w8,[x0,#8]; tbz w8,#0→p1; _p||_p1
-[XNPSystemStatus p1a]   @0x2629c : 同 hasP
-[XNPSystemStatus p]     @0x26164 : ldrb w0,[x0,#8]; ret
-[XNPSystemStatus p1]    @0x26200 : ldrb w0,[x0,#9]; ret
```

**关键认知**：`hasP`/`p1a` 直接读 ivar `_p`/`_p1`，**不经过 `p`/`p1` getter**——所以四个函数都得 patch，光改 getter 没用。

`p1a` 的门禁位置：
- **截图水印**：`+[XNPDrawFinishUtils addAnnotationToImage:withDrawingView:drawingRect:]` 内 `0x2eec0→sharedSystemStatus→p1a`，`p1a!=0` → `je` 跳过水印绘制块
- **标注/编辑 Pro 门禁**、菜单"升级到专业版"显隐（`hidden=hasP`）

`init` 从 `XNPUserDefaultsManager` 读 key 初始化 ivar（双 domain：app `com.zzd.Xnip` 和 group `ME7L72N3S3.group.com.zzd.Xnip`）：

| ivar | offset | key | 类型 |
|------|--------|-----|------|
| `_p` | +0x08 | `kXnipP` | BOOL（订阅位，receipt 可能写回） |
| `_p1` | +0x09 | `kXnipP1` | BOOL（永久买断位，更稳） |
| `_pExpirationTime` | +0x10 | `kXnipPExpirationTime` | NSInteger unix ts（UI 展示用） |

## 解锁矩阵

| 通道 | 方式 | 持久性 | 依赖 |
|------|------|--------|------|
| **静态补丁**（主） | `hasP/p1a/p/p1` 恒 `return 1`，双 arch | 重启仍有效，无注入 | 无 |
| **defaults**（辅） | `kXnipP=kXnipP1=1` 写 app+group domain | init 读入 ivar | 可能被 receipt 清 `kXnipP`（`kXnipP1` 不受影响） |
| **Frida**（备份调试） | watch.sh + patch.js 每 5s stamp ivar + hook `setP:`/`setP1:` 强制 arg=1 | 需 LaunchAgent + get-task-allow | frida |

## 部署

```bash
# 前置: /Applications/Xnip.app 是 MAS 原版(留作回滚,不动)
bash scripts/install.sh        # 复制→去compressed→静态补丁→重签→defaults→LaunchAgent
open ~/Applications/Xnip.app
```

install.sh 步骤：
1. `cp -R` 原版 → `~/Applications/Xnip.app`，`chflags nocompressed`
2. `apply-binary-patch.sh` 改 XnipLibrary 的 `hasP/p1a/p/p1` 为恒真（arm64 + x86-64 双 slice）
3. `codesign --sign - --force --deep --entitlements get-task-allow` 重签 7 个组件（MAS-only entitlements `app-sandbox`/`app-groups`/`application-identifier` 必须丢，否则 launchd `OS_REASON_EXEC`）
4. `defaults write` 双 domain 写 `kXnipP/kXnipP1/kXnipPExpirationTime`
5. 部署 `~/.pi/xnip-patch/{patch.js,watch.sh}` + bootstrap `com.user.xnip-patch` LaunchAgent（frida 备份）

## 验证

```bash
# 运行时判定 (patched copy only — get-task-allow 才能 attach)
frida -p $(pgrep -f "$HOME/Applications/Xnip.app/Contents/MacOS/Xnip" | head -1) -q --runtime=v8 -e '
const ss=ObjC.classes.XNPSystemStatus.sharedSystemStatus();
const m=ObjC.classes.NSApplication.sharedApplication().delegate().menuletMenu().itemAtIndex_(0);
console.log("hasP:",ss.hasP(),"p1a:",ss.p1a(),"| upgradeMenu hidden:",m.isHidden());
'
# → hasP:true p1a:true | upgradeMenu hidden:true
```

- **二进制补丁独立生效**：删掉所有 `kXnip*` defaults 重启，`hasP`/`p1a` 仍 `true`（恒真补丁不读 ivar）
- **无水印**：`addAnnotationToImage` 输出与源图 MD5 相同 → 无水印叠加
- **重启持久**：`killall Xnip` + `open` 后仍 `hasP:true`，无需 frida 常驻

## 已知限制

- **`CGPreflightScreenCaptureAccess` 返回 0**（adhoc 签名 vs MAS `csreq` 不匹配 TCC entry），但 `CGDisplayCreateImage`/`CGWindowListCreateImage` 实际截屏**可用**——TCC 旧 API 路径放行。交互式选区截图 UI 因 `permittedFrontASNs` 置前台受限，菜单栏截图快捷键流程在真实用户会话里正常
- MAS receipt 无 IAP entry → 补丁只绕过客户端判定，服务器端不认
- 交互式截图 overlay 无法被脚本驱动测试（`SetFrontProcessWithInfo` denied），但保存管线+反汇编+菜单态已充分证明
- 原版 `/Applications/Xnip.app` 保留不动，随时回滚

## 回滚

```bash
launchctl bootout gui/$(id -u)/com.user.xnip-patch 2>/dev/null
rm -f ~/Library/LaunchAgents/com.user.xnip-patch.plist
rm -rf ~/.pi/xnip-patch ~/Applications/Xnip.app
# defaults 清理(可选)
for d in com.zzd.Xnip ME7L72N3S3.group.com.zzd.Xnip; do
  defaults delete "$d" kXnipP; defaults delete "$d" kXnipP1; defaults delete "$d" kXnipPExpirationTime
done
# 用 /Applications/Xnip.app 原版
```

## 文件

| 文件 | 作用 |
|------|------|
| `scripts/apply-binary-patch.sh` | **主通道**：改 XnipLibrary 双 arch 8 处字节 |
| `scripts/install.sh` | 一键部署（复制+补丁+重签+defaults+LaunchAgent） |
| `scripts/patch.js` | frida 备份 stamp（5s 循环 + hook setP/setP1） |
| `scripts/watch.sh` | LaunchAgent 入口，只 attach `~/Applications` 路径 |
| `launchagent/com.user.xnip-patch.plist` | launchd 配置（WatchPaths + 10s 轮询） |
