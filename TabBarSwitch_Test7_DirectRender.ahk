#Requires AutoHotkey v2.0
#SingleInstance Force
; #NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  TabBarSwitch v2.1 - Test 7 (Direct RenderWidget)
;  方案七：直攻核心
;  完全放弃激活主窗口 (WM_ACTIVATE)，直接将按键发送给 Chrome 的渲染子控件
;  (Chrome_RenderWidgetHostHWND1)。
;  理论上这是最彻底的“无感”方案，因为主窗口状态完全未变。
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
                ; 同类窗口切换，保持原逻辑 (轻量激活)
                try {
                    PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow
                    SetKeyDelay KeyDelay, KeyDuration
                    ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                    PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow
                }
            }
            else {
                ; 异类窗口切换 (后台滚动)
                try {
                    ; 1. 尝试寻找 Chrome 的渲染子窗口 (网页内容区域)
                    ; 大多数快捷键其实是由这个控件处理的
                    hRender := ControlGetHwnd("Chrome_RenderWidgetHostHWND1", "ahk_id " . CurrentTargetWindow)
                    
                    if (hRender) {
                        ; 2. 直接发送给子窗口，不激活主窗口
                        SetKeyDelay KeyDelay, KeyDuration
                        ControlSend keySeq, , "ahk_id " . hRender
                    } else {
                        ; 如果找不到渲染窗口 (极少见)，回退到发送给主窗口，但不激活
                        SetKeyDelay KeyDelay, KeyDuration
                        ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                    }
                    
                    ; 注意：这里完全移除了 PostMessage WM_ACTIVATE / WM_SETFOCUS
                    ; 没有任何激活消息 = 没有任何闪烁
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
