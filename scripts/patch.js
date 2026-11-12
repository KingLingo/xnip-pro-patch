// Xnip Pro patch — force XNPSystemStatus._p = _p1 = 1
// Target: Xnip 2.5.1 (build 79) re-signed with get-task-allow, no sandbox
// Usage: frida -p <PID> -q --runtime=v8 -l patch.js

function stampPro() {
    try {
        const ss = ObjC.classes.XNPSystemStatus.sharedSystemStatus();
        const NSDate = ObjC.classes.NSDate;
        const future = NSDate.dateWithTimeIntervalSince1970_(4102444800); // 2100-01-01
        ss.handle.add(0x8).writeU8(1);  // _p
        ss.handle.add(0x9).writeU8(1);  // _p1
        ss.handle.add(0x10).writePointer(future.handle); // _pExpirationTime
        console.log("[xnip-patch] stamped: hasP=" + ss.hasP() + " p1a=" + ss.p1a());
        return true;
    } catch (e) {
        console.log("[xnip-patch] stamp error: " + e);
        return false;
    }
}

// Hook setP:/setP1: to always force arg=true
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
    console.log("[xnip-patch] hooked setP:/setP1:");
}

// Stamp immediately and re-stamp every 5s (in case something resets)
stampPro();
setInterval(stampPro, 5000);
