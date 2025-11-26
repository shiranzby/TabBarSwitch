#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  配置区域
; ==============================================================================
TabAreaHeight := 120
MaxQueueSize := 1
KeyHoldDuration := 35 
ChromiumWindowClasses := ["Chrome_WidgetWin_1", "Chrome_WidgetWin_0"]

; ==============================================================================
;  核心逻辑
; ==============================================================================
CurrentTargetWindow := 0, TaskQueueCount := 0

#HotIf IsMouseInBrowserTabArea()
WheelUp::QueueTask("{Ctrl down}{Shift down}{Tab}{Shift up}{Ctrl up}")
WheelDown::QueueTask("{Ctrl down}{Tab}{Ctrl up}")
MButton::QueueTask("{Ctrl down}{Shift down}t{Shift up}{Ctrl up}")
#HotIf

QueueTask(keySeq) {
    global TaskQueueCount
    if (TaskQueueCount >= MaxQueueSize)
        return
    TaskQueueCount += 1
    SetTimer () => ExecTask(keySeq), -1
}

ExecTask(keySeq) {
    global TaskQueueCount, CurrentTargetWindow, KeyHoldDuration, ChromiumWindowClasses
    try {
        origID := WinExist("A")
        
        ; 1. 如果当前就在目标窗口，直接发
        if (origID = CurrentTargetWindow) {
            Send keySeq
        } else {
            Critical "On"
            
            ; 检查当前活动窗口是否也是浏览器？
            isForegroundBrowser := false
            try {
                fgClass := WinGetClass("ahk_id " . origID)
                if (HasValue(ChromiumWindowClasses, fgClass))
                    isForegroundBrowser := true
            }

            ; ============================================================
            ; 唤醒阶段 (Wake Up)
            ; ============================================================
            ; 无论哪种情况，都必须先唤醒目标窗口
            PostMessage 0x0086, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_NCACTIVATE
            PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE
            PostMessage 0x0007, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_SETFOCUS

            ; 发送按键
            SetKeyDelay 0, KeyHoldDuration
            ControlSend keySeq, , "ahk_id " . CurrentTargetWindow

            ; ============================================================
            ; 清理阶段 (Cleanup) - 智能分支
            ; ============================================================
            
            if (!isForegroundBrowser) {
                ; 场景 A：Typora -> Chrome
                ; 必须严格清理现场，否则 Typora 可能会失去焦点或无法输入
                if (origID) {
                    PostMessage 0x0008, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_KILLFOCUS
                    PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Inactive)
                    PostMessage 0x0086, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_NCACTIVATE (Inactive)
                }
            } else {
                ; 场景 B：Chrome A -> Chrome B
                ; 【关键修复】不做任何清理！
                ; 让 B 窗口保持“半醒”状态。
                ; 因为前台是 A 窗口，A 会自然地保持系统级焦点。
                ; 强行发 KILLFOCUS 给 B 会导致 B 在短时间内拒绝下一次输入，或者干扰 A 的输入流。
            }
            
            Critical "Off"
        }
    } finally {
        if (TaskQueueCount > 0)
            TaskQueueCount -= 1
    }
}

IsMouseInBrowserTabArea() {
    global CurrentTargetWindow
    CoordMode "Mouse", "Screen"
    MouseGetPos(&mx, &my, &hw)
    if !hw || !(root := DllCall("GetAncestor", "ptr", hw, "uint", 2, "ptr") || hw)
        return false
    
    try if !HasValue(ChromiumWindowClasses, WinGetClass("ahk_id " . root))
        return false
        
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . root)
    catch
        return false

    if ((relY := my - wy) >= 0 && relY <= TabAreaHeight) {
        CurrentTargetWindow := root
        return true
    }
    return false
}

HasValue(arr, val) {
    for item in arr
        if item = val
            return true
    return false
}