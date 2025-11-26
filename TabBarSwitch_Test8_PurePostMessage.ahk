#Requires AutoHotkey v2.0
#SingleInstance Force
; #NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  TabBarSwitch v2.1 - Test 8 (Pure PostMessage)
;  方案八：纯消息模拟 (Pure PostMessage)
;  放弃 ControlSend，改用底层的 PostMessage 直接发送 WM_KEYDOWN/UP 消息。
;  ControlSend 内部可能会尝试获取焦点或激活窗口，而纯消息则更“隐蔽”。
;  目标直接指向 Chrome 的渲染子窗口。
; ==============================================================================
TabAreaHeight := 120
MaxQueueSize := 1
ChromiumWindowClasses := Map("Chrome_WidgetWin_1", 1, "Chrome_WidgetWin_0", 1)

CurrentTargetWindow := 0, TaskQueueCount := 0

#HotIf IsMouseInBrowserTabArea()
; 上滚：切换上一个标签 (Ctrl+Shift+Tab)
WheelUp::QueueTask("Prev")
; 下滚：切换下一个标签 (Ctrl+Tab)
WheelDown::QueueTask("Next")
; 中键：恢复关闭的标签 (Ctrl+Shift+T)
MButton::QueueTask("Restore")
#HotIf

QueueTask(action) {
    global TaskQueueCount
    if (TaskQueueCount >= MaxQueueSize)
        return
    TaskQueueCount += 1
    SetTimer () => ExecTask(action), -1
}

ExecTask(action) {
    global TaskQueueCount, CurrentTargetWindow
    try {
        origID := WinExist("A")
        
        if (origID = CurrentTargetWindow) {
            ; 同窗口直接发送按键
            if (action = "Next")
                Send "^{Tab}"
            else if (action = "Prev")
                Send "^+{Tab}"
            else if (action = "Restore")
                Send "^+t"
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
                ; 同类窗口，保持原样
                PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow
                if (action = "Next")
                    ControlSend "^{Tab}", , "ahk_id " . CurrentTargetWindow
                else if (action = "Prev")
                    ControlSend "^+{Tab}", , "ahk_id " . CurrentTargetWindow
                else if (action = "Restore")
                    ControlSend "^+t", , "ahk_id " . CurrentTargetWindow
                PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow
            }
            else {
                ; 异类窗口：纯消息攻击
                try {
                    ; 寻找渲染子窗口
                    hTarget := ControlGetHwnd("Chrome_RenderWidgetHostHWND1", "ahk_id " . CurrentTargetWindow)
                    if (!hTarget)
                        hTarget := CurrentTargetWindow
                    
                    ; 定义虚拟键码
                    VK_CONTROL := 0x11
                    VK_SHIFT   := 0x10
                    VK_TAB     := 0x09
                    VK_T       := 0x54
                    
                    ; 辅助函数：发送按下和抬起
                    PostKey(hwnd, vk) {
                        PostMessage 0x0100, vk, 0, , "ahk_id " . hwnd ; WM_KEYDOWN
                        PostMessage 0x0101, vk, 0, , "ahk_id " . hwnd ; WM_KEYUP
                    }
                    
                    PostDown(hwnd, vk) {
                        PostMessage 0x0100, vk, 0, , "ahk_id " . hwnd
                    }
                    
                    PostUp(hwnd, vk) {
                        PostMessage 0x0101, vk, 0xC0000000, , "ahk_id " . hwnd
                    }

                    ; 执行按键序列
                    if (action = "Next") {
                        ; Ctrl + Tab
                        PostDown(hTarget, VK_CONTROL)
                        PostDown(hTarget, VK_TAB)
                        PostUp(hTarget, VK_TAB)
                        PostUp(hTarget, VK_CONTROL)
                    }
                    else if (action = "Prev") {
                        ; Ctrl + Shift + Tab
                        PostDown(hTarget, VK_CONTROL)
                        PostDown(hTarget, VK_SHIFT)
                        PostDown(hTarget, VK_TAB)
                        PostUp(hTarget, VK_TAB)
                        PostUp(hTarget, VK_SHIFT)
                        PostUp(hTarget, VK_CONTROL)
                    }
                    else if (action = "Restore") {
                        ; Ctrl + Shift + T
                        PostDown(hTarget, VK_CONTROL)
                        PostDown(hTarget, VK_SHIFT)
                        PostDown(hTarget, VK_T)
                        PostUp(hTarget, VK_T)
                        PostUp(hTarget, VK_SHIFT)
                        PostUp(hTarget, VK_CONTROL)
                    }
                    
                    ; 没有任何 Activate/Focus 消息！
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
