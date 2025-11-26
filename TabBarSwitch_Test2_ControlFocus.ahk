#Requires AutoHotkey v2.0
#SingleInstance Force
; #NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  TabBarSwitch v2.1 - Test 2 (ControlFocus Hidden)
;  方案二：使用 ControlFocus 将焦点转移到网页内容区域 (Chrome_RenderWidgetHostHWND1)
;  试图让焦点框出现在网页内部而非地址栏
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
                ; [修改点] 尝试将焦点设置到 Chrome 的渲染子窗口 (网页内容区域)
                ; 这样焦点框可能不会出现在 UI 层 (地址栏)
                try ControlFocus "Chrome_RenderWidgetHostHWND1", "ahk_id " . CurrentTargetWindow
                
                PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Active)
                
                SetKeyDelay KeyDelay, KeyDuration
                ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                
                if (origID) {
                    PostMessage 0x0008, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_KILLFOCUS
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
