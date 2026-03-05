#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
SetKeyDelay 30, 30

; Support both orders:
; 1) Win then Left Alt
; 2) Left Alt then Win
#LAlt::TriggerVoiceInput()
<!LWin::TriggerVoiceInput()

TriggerVoiceInput() {
    static busy := false
    if busy
        return
    busy := true

    ; Release physical modifiers first to avoid leaking them into simulated keys.
    KeyWait "LAlt"
    KeyWait "LWin"

    SendEvent "{LAlt down}{LShift down}"
    Sleep 40
    SendEvent "2"
    Sleep 40
    SendEvent "{LShift up}{LAlt up}"

    Sleep 120

    SendEvent "{LWin down}"
    Sleep 30
    SendEvent "h"
    Sleep 30
    SendEvent "{LWin up}"

    busy := false
}
