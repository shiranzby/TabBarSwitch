#Requires AutoHotkey v2.0
#SingleInstance Force
; #NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  TabBarSwitch v2.1 - Test 10 (Click Focus)
;  方案十：点击聚焦法
;  在发送按键前，向网页内容区域 (RenderWidget) 发送一个模拟点击消息。
;  这通常会强制 Chrome 将焦点从地址栏转移到网页内容上，从而消除地址栏的焦点框。
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
                    
                    ; 2. 激活主窗口
                    PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow
                    
                    ; 3. 【关键】向渲染窗口发送点击消息 (坐标 1,1)
                    ; 这会欺骗 Chrome 认为用户点击了网页，从而移除地址栏焦点
                    if (hRender) {
                        PostMessage 0x0201, 1, 0x00010001, , "ahk_id " . hRender ; WM_LBUTTONDOWN at (1,1)
                        PostMessage 0x0202, 0, 0x00010001, , "ahk_id " . hRender ; WM_LBUTTONUP at (1,1)
                    }
                    
                    ; 4. 发送按键
                    SetKeyDelay KeyDelay, KeyDuration
                    ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                    
                    ; 5. 恢复
                    if (origID) {
                        PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow
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
