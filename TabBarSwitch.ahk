#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon                     ; 隐藏后台，如不需要则自行注释此行 (即: ;#NoTrayIcon)
ProcessSetPriority "High"       ; 提高进程优先级，减少延迟
DllCall("SetProcessDPIAware")   ; 禁用系统 DPI 缩放，确保坐标准确
SetWinDelay 0                   ; 消除窗口操作的默认延时

; ==============================================================================
;  TabBarSwitch V2.1
;  更新日志: 使用 Ctrl+PageUp/PageDown 替代 Ctrl+Tab，彻底解决后台切换时的焦点框闪烁问题
; ==============================================================================

; ==============================================================================
;  配置区域
; ==============================================================================
; --- 触发区域设置 ---
TabAreaHeight := 120        ; 顶部触发区域高度 (像素)，在此区域内滚动滚轮生效

; --- 任务队列设置 ---
MaxQueueSize := 1           ; 最大任务队列长度，防止操作积压

; --- 按键模拟参数 ---
; 调整建议：Delay (按键间隔) 给浏览器反应时间确认修饰键；Duration (持续时间) 防止掉键
KeyDelay := 5               ; 按键间隔 (毫秒)
KeyDuration := 7            ; 按键按下持续时间 (毫秒)

; --- 目标窗口设置 ---
; Chromium 内核浏览器通用类名 (Chrome, Edge, Brave, Vivaldi, 360极速等)
ChromiumWindowClasses := ["Chrome_WidgetWin_1", "Chrome_WidgetWin_0"]

; ==============================================================================
;  核心逻辑
; ==============================================================================
CurrentTargetWindow := 0, TaskQueueCount := 0

#HotIf IsMouseInBrowserTabArea() ; 仅当鼠标在浏览器标签栏区域时生效
; 使用 {Blind} 避免干扰，显式拆分按键
; V2.1 修改: 使用 PgUp/PgDn 替代 Tab，避免触发焦点导航导致的黑色边框闪烁
WheelUp::QueueTask("{Blind}{Ctrl down}{PgUp}{Ctrl up}")       ; 上滚：切换上一个标签 (Ctrl+PageUp)
WheelDown::QueueTask("{Blind}{Ctrl down}{PgDn}{Ctrl up}")     ; 下滚：切换下一个标签 (Ctrl+PageDown)
MButton::QueueTask("{Blind}{Ctrl down}{Shift down}t{Shift up}{Ctrl up}")     ; 中键：恢复关闭的标签
#HotIf

QueueTask(keySeq) {
    global TaskQueueCount
    if (TaskQueueCount >= MaxQueueSize) ; 队列满则丢弃，防止卡顿
        return
    TaskQueueCount += 1
    SetTimer () => ExecTask(keySeq), -1 ; 异步执行任务
}

ExecTask(keySeq) {
    global TaskQueueCount, CurrentTargetWindow, KeyDelay, KeyDuration, ChromiumWindowClasses
    try {
        origID := WinExist("A") ; 获取当前激活窗口 ID
        
        if (origID = CurrentTargetWindow) {
            Send keySeq ; 如果当前就是目标浏览器，直接发送按键
        } else {
            Critical "On" ; 关键区，防止线程中断
            
            isForegroundBrowser := false
            try {
                if (origID) {
                    fgClass := WinGetClass("ahk_id " . origID)
                    if (HasValue(ChromiumWindowClasses, fgClass))
                        isForegroundBrowser := true ; 判断前台是否也是浏览器
                }
            }

            ; ============================================================
            ;  分支逻辑
            ; ============================================================
            
            if (isForegroundBrowser) {
                ; 场景 1: Chrome A -> Chrome B (强制激活恢复法)
                ; 这种场景下，直接 ControlSend 可能会失效，需要伪造激活消息
                PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Active)
                
                ; 【关键修改】增加按键间隔
                SetKeyDelay KeyDelay, KeyDuration
                ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                
                PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Inactive)
                
                if (origID)
                    WinActivate "ahk_id " . origID ; 恢复原窗口激活状态
            }
            else {
                ; 场景 2: 其他软件 -> Chrome (深度欺骗法)
                ; 模拟完整的窗口激活流程，欺骗 Chrome 以为自己获得了焦点
                PostMessage 0x0086, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_NCACTIVATE (Active)
                PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Active)
                PostMessage 0x0007, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_SETFOCUS
                
                ; 【关键修改】增加按键间隔
                SetKeyDelay KeyDelay, KeyDuration
                ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                
                if (origID) {
                    ; 恢复现场：取消目标窗口焦点，恢复原窗口状态
                    PostMessage 0x0008, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_KILLFOCUS
                    PostMessage 0x0006, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE (Inactive)
                    PostMessage 0x0086, 0, 0, , "ahk_id " . CurrentTargetWindow ; WM_NCACTIVATE (Inactive)
                    PostMessage 0x0086, 1, 0, , "ahk_id " . origID          ; 恢复原窗口标题栏激活态
                }
            }
            
            Critical "Off"
        }
    } finally {
        if (TaskQueueCount > 0)
            TaskQueueCount -= 1 ; 任务完成，减少计数
    }
}

IsMouseInBrowserTabArea() {
    global CurrentTargetWindow
    CoordMode "Mouse", "Screen" ; 使用屏幕绝对坐标
    MouseGetPos(&mx, &my, &hw)
    ; 获取鼠标下的根窗口句柄 (处理子窗口情况)
    if !hw || !(root := DllCall("GetAncestor", "ptr", hw, "uint", 2, "ptr") || hw)
        return false
    
    ; 检查窗口类名是否为支持的浏览器
    try if !HasValue(ChromiumWindowClasses, WinGetClass("ahk_id " . root))
        return false
        
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . root)
    catch
        return false

    ; 计算鼠标相对于窗口顶部的 Y 坐标
    if ((relY := my - wy) >= 0 && relY <= TabAreaHeight) {
        CurrentTargetWindow := root ; 缓存目标窗口句柄
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
