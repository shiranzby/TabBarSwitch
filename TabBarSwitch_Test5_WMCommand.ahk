#Requires AutoHotkey v2.0
#SingleInstance Force
; #NoTrayIcon
ProcessSetPriority "High"
DllCall("SetProcessDPIAware")
SetWinDelay 0

; ==============================================================================
;  TabBarSwitch v2.1 - Test 5 (WM_COMMAND)
;  方案五：直接发送 WM_COMMAND 命令 ID
;  绕过键盘模拟，直接触发 Chrome 内部命令
;  注意：Chrome 的 Command ID 可能会随版本变化，这里使用的是常见 ID
; ==============================================================================
TabAreaHeight := 120
MaxQueueSize := 1
ChromiumWindowClasses := Map("Chrome_WidgetWin_1", 1, "Chrome_WidgetWin_0", 1)

; Chrome 常见 Command IDs (可能需要根据版本调整)
; IDC_SELECT_NEXT_TAB = 34014
; IDC_SELECT_PREVIOUS_TAB = 34015
; IDC_RESTORE_TAB = 34027
CMD_NEXT_TAB := 34014
CMD_PREV_TAB := 34015
CMD_RESTORE_TAB := 34027

CurrentTargetWindow := 0, TaskQueueCount := 0

#HotIf IsMouseInBrowserTabArea()
; 上滚：切换上一个标签
WheelUp::QueueTask(CMD_PREV_TAB)
; 下滚：切换下一个标签
WheelDown::QueueTask(CMD_NEXT_TAB)
; 中键：恢复关闭的标签
MButton::QueueTask(CMD_RESTORE_TAB)
#HotIf

QueueTask(cmdID) {
    global TaskQueueCount
    if (TaskQueueCount >= MaxQueueSize)
        return
    TaskQueueCount += 1
    SetTimer () => ExecTask(cmdID), -1
}

ExecTask(cmdID) {
    global TaskQueueCount, CurrentTargetWindow
    try {
        origID := WinExist("A")
        
        if (origID = CurrentTargetWindow) {
            ; 同窗口直接发命令
            PostMessage 0x0111, cmdID, 0, , "ahk_id " . CurrentTargetWindow ; WM_COMMAND
        } else {
            Critical "On"
            
            ; 跨窗口发送命令
            ; 理论上 WM_COMMAND 不需要焦点，只要窗口能接收消息即可
            ; 如果不行，可能还是需要轻微的激活
            
            ; 尝试1：直接发送 (最无感)
            PostMessage 0x0111, cmdID, 0, , "ahk_id " . CurrentTargetWindow
            
            ; 如果直接发送无效，可以尝试解开下面这行的注释，给一个轻微的激活
            ; PostMessage 0x0006, 1, 0, , "ahk_id " . CurrentTargetWindow ; WM_ACTIVATE
            
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
