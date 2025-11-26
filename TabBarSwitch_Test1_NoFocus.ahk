#Requires AutoHotkey v2.0
#SingleInstance Force
; #NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  TabBarSwitch v2.1 - Test 1 (Remove WM_SETFOCUS)
;  方案一：移除 WM_SETFOCUS，仅保留 WM_ACTIVATE
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
                ; 场景 1: Chrome A -> Chrome B
                PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Active)
                SetKeyDelay KeyDelay, KeyDuration
                ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Inactive)
            }
            else {
                ; 场景 2: 其他软件 -> Chrome
                ; [修改点] 移除了 WM_NCACTIVATE (0x0086) 和 WM_SETFOCUS (0x0007)
                PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Active)
                
                SetKeyDelay KeyDelay, KeyDuration
                ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                
                if (origID) {
                    ; [修改点] 移除了 WM_KILLFOCUS (0x0008)
                    PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Inactive)
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
