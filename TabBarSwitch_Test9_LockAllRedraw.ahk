#Requires AutoHotkey v2.0
#SingleInstance Force
; #NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  TabBarSwitch v2.1 - Test 9 (Lock All Redraw)
;  方案九：全域重绘锁定
;  同时锁定主窗口和渲染子窗口 (RenderWidget) 的重绘。
;  试图掩盖由子窗口绘制的焦点框。
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
                try {
                    PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow
                    SetKeyDelay KeyDelay, KeyDuration
                    ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                    PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow
                }
            }
            else {
                try {
                    ; 1. 寻找渲染子窗口
                    hRender := ControlGetHwnd("Chrome_RenderWidgetHostHWND1", "ahk_id " . CurrentTargetWindow)
                    
                    ; 2. 锁定主窗口重绘
                    SendMessage 0x000B, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_SETREDRAW = FALSE
                    
                    ; 3. 锁定渲染子窗口重绘 (如果存在)
                    if (hRender)
                        SendMessage 0x000B, 0, 0, , "ahk_id " . hRender
                    
                    ; 4. 执行操作
                    PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE
                    
                    SetKeyDelay KeyDelay, KeyDuration
                    ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                    
                    if (origID) {
                        PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow ; Inactive
                    }
                    
                    ; 5. 解锁并刷新
                    SendMessage 0x000B, 1, 0, , "ahk_id " . CurrentTargetWindow
                    DllCall("RedrawWindow", "Ptr", CurrentTargetWindow, "Ptr", 0, "Ptr", 0, "UInt", 0x0405)
                    
                    if (hRender) {
                        SendMessage 0x000B, 1, 0, , "ahk_id " . hRender
                        DllCall("RedrawWindow", "Ptr", hRender, "Ptr", 0, "Ptr", 0, "UInt", 0x0405)
                    }
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
