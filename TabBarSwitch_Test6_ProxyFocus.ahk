#Requires AutoHotkey v2.0
#SingleInstance Force
; #NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  TabBarSwitch v2.1 - Test 6 (Proxy Focus)
;  方案六：透明替身窗口 (Proxy Window)
;  创建一个不可见的子窗口挂载到 Chrome 上，强制将焦点转移给它，
;  从而避免 Chrome 将焦点绘制在地址栏或网页内容上。
; ==============================================================================
TabAreaHeight := 120
MaxQueueSize := 1
KeyDelay := 5
KeyDuration := 7
ChromiumWindowClasses := Map("Chrome_WidgetWin_1", 1, "Chrome_WidgetWin_0", 1)

CurrentTargetWindow := 0, TaskQueueCount := 0

; 创建一个透明的、无边框的 GUI 窗口作为“焦点替身”
ProxyGui := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x08000000") ; WS_EX_NOACTIVATE
ProxyGui.BackColor := "000000"
WinSetTransparent(0, ProxyGui.Hwnd) ; 完全透明

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
    global TaskQueueCount, CurrentTargetWindow, KeyDelay, KeyDuration, ChromiumWindowClasses, ProxyGui
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
                    ; 1. 将替身窗口挂载为 Chrome 的子窗口
                    DllCall("SetParent", "Ptr", ProxyGui.Hwnd, "Ptr", CurrentTargetWindow)
                    
                    ; 2. 显示替身窗口 (不激活)
                    ProxyGui.Show("x0 y0 w1 h1 NoActivate")
                    
                    ; 3. 告诉 Chrome 它被激活了 (WM_ACTIVATE)
                    PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow
                    
                    ; 4. 【关键】将焦点强制设置到我们的替身窗口上
                    ; 这样 Chrome 认为自己有焦点，但焦点实际落在一个什么都没有的透明窗口上
                    try ControlFocus "ahk_id " . ProxyGui.Hwnd
                    
                    ; 5. 发送按键
                    SetKeyDelay KeyDelay, KeyDuration
                    ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                    
                    ; 6. 恢复现场
                    if (origID) {
                        PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Inactive)
                    }
                    
                    ; 7. 撤销挂载并隐藏
                    DllCall("SetParent", "Ptr", ProxyGui.Hwnd, "Ptr", 0)
                    ProxyGui.Hide()
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
