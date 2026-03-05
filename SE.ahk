#Requires AutoHotkey v2.0
#SingleInstance Force

; 全局设置：按 Alt+Q 打开面板，鼠标侧键触发切音频
!q::ShowMyPanel()
XButton1::CutAudio()
global g_panelGui := ""
global g_mediaPathCache := ""
global g_cmdShellSwitch := "/k"
; "/c" (close) or "/k" (keep) GetComSpecSwitchFromArgs()
Persistent()


ShowMyPanel() {
    global g_panelGui
    if g_panelGui {
        g_panelGui.Show()
        return
    }

    g_panelGui := Gui("+AlwaysOnTop", "我的工具箱")
    g_panelGui.SetFont("s12", "Microsoft YaHei")

    g_panelGui.Add("Button", "w220 h40", "SE 精听切片").OnEvent("Click", (*) => SetTimer(() => CutAudio(), -100))
    g_panelGui.Add("Button", "w220 h40", "示例功能").OnEvent("Click", (*) => SetTimer(() => MsgBox("你点了示例按钮"), -100))
    g_panelGui.Add("Button", "w220 h40", "重载脚本").OnEvent("Click", (*) => SetTimer(() => Reload(), -100))

    g_panelGui.Show()
}

CutAudio(*) {
    global g_cmdShellSwitch
    video_path := ResolveMediaPath()
    if (video_path = "") {
        MsgBox "未能自动获取媒体路径。请先在 Subtitle Edit 打开字幕，或手动选择音频/视频文件。"
        return
    }

    output_dir := A_Desktop

    A_Clipboard := ""
    Send "^c"
    if !ClipWait(2) {
        MsgBox "复制失败，请重试"
        return
    }

    try {
        raw_text := GetClipboardText()
    } catch {
        MsgBox "剪贴板正在被其他程序占用，请重试"
        return
    }

    if RegExMatch(raw_text, "s)(\d{2}:\d{2}:\d{2},\d{3})\s+-->\s+(\d{2}:\d{2}:\d{2},\d{3})\R(.*)", &m) {
        start_time := StrReplace(m[1], ",", ".")
        end_time := StrReplace(m[2], ",", ".")
        subtitle := m[3]

        subtitle := RegExReplace(subtitle, "<[^>]+>", "")
        subtitle := RegExReplace(subtitle, "\s+", "")      ; Remove all whitespaces, newlines, tabs entirely
        safe_name := Trim(RegExReplace(subtitle, "[\\/:*?<>|]", "_"))
        safe_name := StrReplace(safe_name, '"', "_")

        output_file := output_dir "\" safe_name ".ogg"
        run_str := Format('ffmpeg -i "{1}" -ss {2} -to {3} -vn -ac 1 -c:a libopus -b:a 32k -application voip -y "{4}"', video_path, start_time, end_time, output_file)

        if (g_cmdShellSwitch != "/c" && g_cmdShellSwitch != "/k")
            g_cmdShellSwitch := "/c"
        cmdPayload := StrReplace(run_str, '"', '""')
        Run Format('{1} {2} "{3}"', A_ComSpec, g_cmdShellSwitch, cmdPayload)

        ToolTip "已截取: " safe_name
        SetTimer () => ToolTip(), -2000
    } else {
        MsgBox "未能识别字幕格式，请确认选中了包含时间码的文本。"
    }
}

GetClipboardText(timeoutMs := 1500) {
    endTick := A_TickCount + timeoutMs
    while (A_TickCount < endTick) {
        try return A_Clipboard
        catch
            Sleep 30
    }
    throw Error("Clipboard busy")
}

ResolveMediaPath() {
    global g_mediaPathCache

    if (g_mediaPathCache != "" && FileExist(g_mediaPathCache))
        return g_mediaPathCache

    if mediaPath := GetMediaPathFromSubtitleEdit() {
        g_mediaPathCache := mediaPath
        return mediaPath
    }

    selected := FileSelect(1, , "选择音频/视频文件", "Media Files (*.opus; *.mp3; *.wav; *.m4a; *.flac; *.ogg; *.aac; *.mp4; *.mkv; *.webm)")
    if (selected != "") {
        g_mediaPathCache := selected
        return selected
    }

    return ""
}

GetMediaPathFromSubtitleEdit() {
    global g_mediaPathCache
    try {
        seHwnd := WinExist("ahk_exe SubtitleEdit.exe")
        if !seHwnd
            return ""

        pid := WinGetPID("ahk_id " seHwnd)
        title := WinGetTitle("ahk_id " seHwnd)

        ; 1) Best effort: parse subtitle path from process command line.
        subtitlePath := GetSubtitlePathFromProcessCommandLine(pid)
        if (subtitlePath != "") {
            SplitPath subtitlePath, , &dir, , &nameNoExt
            if (dir != "" && nameNoExt != "") {
                mediaPath := FindSiblingMediaByBase(dir, nameNoExt)
                if (mediaPath != "")
                    return mediaPath
            }
        }

        ; 2) If command line has no subtitle argument, parse window title like "2307.srt - Subtitle Edit".
        titleBaseName := GetSubtitleBaseNameFromWindowTitle(title)
        if (titleBaseName = "")
            return ""

        ; 3) Read Subtitle Edit recent files to recover full subtitle/media path.
        mediaPath := GetMediaPathFromSubtitleEditSettings(titleBaseName)
        if (mediaPath != "")
            return mediaPath

        ; 4) Try cached directory first.
        if (g_mediaPathCache != "" && FileExist(g_mediaPathCache)) {
            SplitPath g_mediaPathCache, , &cacheDir
            if (cacheDir != "") {
                mediaPath := FindSiblingMediaByBase(cacheDir, titleBaseName)
                if (mediaPath != "")
                    return mediaPath
            }
        }

        ; 5) Fallback: search common user folders recursively.
        return FindMediaByBaseInLikelyDirs(titleBaseName)
    } catch {
        return ""
    }
}

GetSubtitlePathFromProcessCommandLine(pid) {
    try {
        wmi := ComObject("WbemScripting.SWbemLocator").ConnectServer(".", "root\\cimv2")
        procs := wmi.ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" pid)
        cmd := ""
        for proc in procs {
            cmd := proc.CommandLine
            break
        }
        if (cmd = "")
            return ""

        ; Quoted path with known subtitle extension.
        if RegExMatch(cmd, 'i)"([A-Za-z]:\\[^"]+\.(srt|ass|ssa|vtt|sub|sbv|txt))"', &m)
            return m[1]

        ; Unquoted path with known subtitle extension.
        if RegExMatch(cmd, 'i)([A-Za-z]:\\\S+\.(srt|ass|ssa|vtt|sub|sbv|txt))', &m)
            return m[1]

        return ""
    } catch {
        return ""
    }
}

GetSubtitleBaseNameFromWindowTitle(title) {
    cleanTitle := Trim(RegExReplace(title, "^\*+\s*", ""))
    if RegExMatch(cleanTitle, 'i)([^\\/:*?"<>|`r`n]+?)\.(srt|ass|ssa|vtt|sub|sbv|txt)\b', &m)
        return m[1]
    return ""
}

GetMediaPathFromSubtitleEditSettings(titleBaseName) {
    settingsPath := A_AppData "\Subtitle Edit\Settings.xml"
    if !FileExist(settingsPath)
        return ""

    try {
        xml := ComObject("Msxml2.DOMDocument.6.0")
        xml.async := false
        if !xml.load(settingsPath)
            return ""

        nodes := xml.selectNodes("//RecentFiles/FileNames/FileName")
        for node in nodes {
            subtitlePath := node.text
            if (subtitlePath = "")
                continue

            SplitPath subtitlePath, , &subtitleDir, , &subtitleBase
            if (StrLower(subtitleBase) != StrLower(titleBaseName))
                continue

            mediaFromSe := node.getAttribute("VideoFileName")
            if (mediaFromSe != "" && FileExist(mediaFromSe))
                return mediaFromSe

            if (subtitleDir != "") {
                mediaPath := FindSiblingMediaByBase(subtitleDir, titleBaseName)
                if (mediaPath != "")
                    return mediaPath
            }
        }
    } catch {
        return ""
    }

    return ""
}

FindMediaByBaseInLikelyDirs(baseName) {
    exts := ["opus", "mp3", "wav", "m4a", "flac", "ogg", "aac", "mp4", "mkv", "webm"]
    dirs := []
    userProfile := EnvGet("USERPROFILE")
    if (userProfile != "") {
        dirs.Push(userProfile "\\Downloads")
        dirs.Push(userProfile "\\Desktop")
        dirs.Push(userProfile "\\Documents")
        dirs.Push(userProfile "\\Music")
        dirs.Push(userProfile "\\Videos")
    }
    dirs.Push(A_ScriptDir)

    for _, dir in dirs {
        if !DirExist(dir)
            continue

        mediaPath := FindSiblingMediaByBase(dir, baseName)
        if (mediaPath != "")
            return mediaPath

        for _, ext in exts {
            Loop Files dir "\\" baseName "." ext, "FR" {
                return A_LoopFileFullPath
            }
        }
    }

    return ""
}

FindSiblingMediaByBase(dir, baseName) {
    exts := ["opus", "mp3", "wav", "m4a", "flac", "ogg", "aac", "mp4", "mkv", "webm"]
    for _, ext in exts {
        candidate := dir "\\" baseName "." ext
        if FileExist(candidate)
            return candidate
    }

    for _, ext in exts {
        Loop Files dir "\\*." ext, "F" {
            return A_LoopFileFullPath
        }
    }

    return ""
}

GetComSpecSwitchFromArgs() {
    mode := "/k" ; default: keep command window open

    for i, arg in A_Args {
        a := StrLower(Trim(arg))

        if (a = "--cmd=close" || a = "--close" || a = "/c" || a = "close") {
            mode := "/c"
            continue
        }

        if (a = "--cmd=keep" || a = "--keep" || a = "/k" || a = "keep") {
            mode := "/k"
            continue
        }

        if (a = "--cmd" && i < A_Args.Length) {
            v := StrLower(Trim(A_Args[i + 1]))
            if (v = "close" || v = "/c")
                mode := "/c"
            else if (v = "keep" || v = "/k")
                mode := "/k"
        }
    }

    return mode
}
