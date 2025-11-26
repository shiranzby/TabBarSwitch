#Requires AutoHotkey v2.0
#SingleInstance Force
; #NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  TabBarSwitch v2.1 - Test 3 (AttachThreadInput)
;  方案三：使用 AttachThreadInput 共享输入队列
;  这是一种更底层的“黑魔法”，让两个窗口共享输入状态，可能彻底解决焦点问题
; ==============================================================================
TabAreaHeight := 120
MaxQueueSize := 1
KeyDelay := 5
KeyDuration := 7
ChromiumWindowClasses := Map("Chrome_WidgetWin_1", 1, "Chrome_WidgetWin_0", 1)

CurrentTargetWindow := 0, TaskQueueCount := 0

#HotIf IsMouseInBrowserTabArea()
WheelUp::QueueTask("{Blind}{Ctrl down}{Shift down}{Tab}{Shift up}{Ctrl up}")
WheelDown::QueueTask("{Blind}{Ctrl down}{Tab}{Ctrl up}")
MButton::QueueTask("{Blind}{Ctrl down}{Shift down}t{Shift up}{Ctrl up}")
#HotIf

QueueTask(keySeq) {
    global TaskQueueCount
    if (TaskQueueCount >= MaxQueueSize)
        return
    TaskQueueCount += 1
    SetTimer () => ExecTask(keySeq), -1
}

ExecTask(keySeq) {
    global TaskQueueCount, CurrentTargetWindow, KeyDelay, KeyDuration, ChromiumWindowClasses
    try {
        origID := WinExist("A")
        
        if (origID = CurrentTargetWindow) {
            Send keySeq
        } else {
            Critical "On"
            
            isForegroundBrowser := false
            try {
                if (origID) {
                    fgClass := WinGetClass("ahk_id " . origID)
                    if (ChromiumWindowClasses.Has(fgClass))
                        isForegroundBrowser := true
                }
            }

            if (isForegroundBrowser) {
                PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow
                SetKeyDelay KeyDelay, KeyDuration
                ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow
            }
            else {
                ; [修改点] 使用 AttachThreadInput 共享线程输入状态
                ; 这种方法不需要显式切换焦点，直接让目标窗口认为它和当前窗口是一伙的
                
                targetThreadID := DllCall("GetWindowThreadProcessId", "Ptr", CurrentTargetWindow, "Ptr", 0)
                currentThreadID := DllCall("GetCurrentThreadId")
                
                if (targetThreadID != currentThreadID) {
                    DllCall("AttachThreadInput", "UInt", currentThreadID, "UInt", targetThreadID, "Int", 1)
                }
                
                ; 依然发送激活消息，但可能不需要 SETFOCUS
                PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow
                
                SetKeyDelay KeyDelay, KeyDuration
                ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                
                if (targetThreadID != currentThreadID) {
                    DllCall("AttachThreadInput", "UInt", currentThreadID, "UInt", targetThreadID, "Int", 0)
                }
                
                if (origID) {
                    PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow
                }
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
    try if !ChromiumWindowClasses.Has(WinGetClass("ahk_id " . root))
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
