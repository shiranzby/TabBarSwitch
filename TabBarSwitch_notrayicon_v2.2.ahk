#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon                     ; 隐藏后台，如不需要则自行注释此行 (即: ;#NoTrayIcon)
ProcessSetPriority "High"       ; 提高进程优先级，减少延迟
DllCall("SetProcessDPIAware")   ; 禁用系统 DPI 缩放，确保坐标准确
SetWinDelay 0                   ; 消除窗口操作的默认延时

; ==============================================================================
;  TabBarSwitch v2.2 (No Tray Icon)
;  更新日志: 
;  1. 采用 AttachThreadInput 技术统一了后台控制逻辑，不再区分前台是否为浏览器。
;  2. 极大地提升了 Chrome 多窗口之间切换的流畅度，消除了旧版本中的焦点抢占问题。
;  3. 保持了 v2.1 的 Ctrl+PgUp/PgDn 映射，确保无视觉闪烁。
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
            
            ; 获取目标窗口的线程 ID
            targetThreadId := DllCall("GetWindowThreadProcessId", "Ptr", CurrentTargetWindow, "Ptr", 0, "UInt")
            ; 获取当前脚本的线程 ID
            currentThreadId := DllCall("GetCurrentThreadId", "UInt")
            
            if (targetThreadId != currentThreadId) {
                ; 连接线程输入队列 (AttachThreadInput)
                ; 这使得脚本线程可以直接向目标窗口线程发送输入，就像它们属于同一个程序一样
                DllCall("AttachThreadInput", "UInt", currentThreadId, "UInt", targetThreadId, "Int", 1)
                
                ; 尝试给予焦点，确保按键能被接收
                ; 由于已经 Attach，ControlFocus 不会强制抢占前台窗口的激活状态
                try ControlFocus "Chrome_RenderWidgetHostHWND1", "ahk_id " . CurrentTargetWindow
                
                SetKeyDelay KeyDelay, KeyDuration
                ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
                
                ; 断开连接
                DllCall("AttachThreadInput", "UInt", currentThreadId, "UInt", targetThreadId, "Int", 0)
            } else {
                ; 如果是同一线程 (极少见)，直接发送
                ControlSend keySeq, , "ahk_id " . CurrentTargetWindow
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
