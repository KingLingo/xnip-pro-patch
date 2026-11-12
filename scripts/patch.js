// Xnip Pro patch — backup runtime stamper (primary = static binary patch).
// Force XNPSystemStatus._p = _p1 = 1, _pExpirationTime = far-future NSTimeInterval.
// Target: Xnip 2.5.1 (build 79) re-signed with get-task-allow, no sandbox.
// Usage: frida -p <PID> -l patch.js   (stays resident; setInterval keeps alive)

function stampPro() {
    try {
        const ss = ObjC.classes.XNPSystemStatus.sharedSystemStatus();
        ss.handle.add(0x8).writeU8(1);          // _p
        ss.handle.add(0x9).writeU8(1);          // _p1
        ss.handle.add(0x10).writeU64(4102444800); // _pExpirationTime (NSInteger unix ts, 2100)
        return true;
    } catch (e) {
        console.log("[xnip-patch] stamp error: " + e);
        return false;
    }
}

// Hook setP:/setP1: to always force arg=true (in case receipt refresh resets).
const sysStatus = ObjC.classes.XNPSystemStatus;
if (sysStatus) {
    const setP = sysStatus["- setP:"];
    const setP1 = sysStatus["- setP1:"];
    if (setP) Interceptor.attach(setP.implementation, {
        onEnter(args) { args[2] = ptr(0x1); }
    });
    if (setP1) Interceptor.attach(setP1.implementation, {
        onEnter(args) { args[2] = ptr(0x1); }
    });
}

stampPro();
setInterval(stampPro, 5000);
console.log("[xnip-patch] resident, stamping every 5s");
