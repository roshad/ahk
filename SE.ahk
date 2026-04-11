#Requires AutoHotkey v2.0
#SingleInstance Force

; 全局设置：按 Alt+Q 打开面板，鼠标侧键触发切音频
!q::ShowMyPanel()
XButton1::CutAudio()
global g_panelGui := ""
global g_mediaPathCache := ""
global g_cmdShellSwitch := ""
global g_progressGui := ""
global g_progressList := ""
global g_convertQueue := []
global g_runningJobs := Map()
global g_doneJobs := []
global g_queueTimerStarted := false
global g_jobSeq := 0
global g_maxConcurrentJobs := 3
; "/c" (close) or "/k" (keep) GetComSpecSwitchFromArgs()
Persistent()
InitAudioQueue()


ShowMyPanel() {
    global g_panelGui
    if g_panelGui {
        g_panelGui.Show()
        return
    }

    g_panelGui := Gui("+AlwaysOnTop", "我的工具箱")
    g_panelGui.SetFont("s12", "Microsoft YaHei")

    g_panelGui.Add("Button", "w220 h40", "SE 精听切片").OnEvent("Click", (*) => SetTimer(() => CutAudio(), -100))
    g_panelGui.Add("Button", "w220 h40", "转换进度").OnEvent("Click", (*) => SetTimer(() => ShowProgressWindow(), -100))
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

        output_file := BuildUniqueOutputPath(output_dir, safe_name, "ogg")
        EnqueueAudioJob(video_path, start_time, end_time, output_file, safe_name)
        ToolTip "已加入转换队列: " safe_name
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

InitAudioQueue() {
    global g_queueTimerStarted

    if g_queueTimerStarted
        return

    A_TrayMenu.Add()
    A_TrayMenu.Add("转换进度", ShowProgressWindow)
    A_TrayMenu.Add("清空已完成记录", ClearFinishedJobs)
    SetTimer(ProcessAudioQueue, 500)
    g_queueTimerStarted := true
}

EnqueueAudioJob(videoPath, startTime, endTime, outputFile, displayName) {
    global g_convertQueue, g_jobSeq

    g_jobSeq += 1
    progressFile := A_Temp "\se_ffmpeg_progress_" g_jobSeq ".txt"
    logFile := A_Temp "\se_ffmpeg_log_" g_jobSeq ".txt"
    TryDeleteFile(progressFile)
    TryDeleteFile(logFile)

    g_convertQueue.Push({
        id: g_jobSeq,
        name: displayName,
        input: videoPath,
        start: startTime,
        end: endTime,
        output: outputFile,
        progressFile: progressFile,
        logFile: logFile,
        state: "排队中",
        percent: 0,
        pid: 0,
        createdAt: FormatTime(, "yyyy-MM-dd HH:mm:ss"),
        startedAt: "",
        finishedAt: "",
        durationMs: TimeToMs(endTime) - TimeToMs(startTime),
        detail: ""
    })

    RefreshProgressView()
}

ProcessAudioQueue(*) {
    global g_convertQueue, g_runningJobs, g_doneJobs, g_maxConcurrentJobs

    for jobId, job in g_runningJobs.Clone() {
        UpdateRunningJob(job)
        if (job.state = "已完成" || job.state = "失败") {
            g_runningJobs.Delete(jobId)
            g_doneJobs.Push(job)
        }
    }

    while (g_runningJobs.Count < g_maxConcurrentJobs && g_convertQueue.Length > 0) {
        job := g_convertQueue.RemoveAt(1)
        StartAudioJob(job)
        g_runningJobs[job.id] := job
    }

    RefreshProgressView()
}

StartAudioJob(job) {
    ffmpegArgs := Format(
        'ffmpeg -hide_banner -nostats -ss {1} -to {2} -i "{3}" -vn -ac 1 -c:a libopus -b:a 32k -application voip -y -progress "{4}" "{5}" 1>"{6}" 2>&1',
        job.start,
        job.end,
        job.input,
        job.progressFile,
        job.output,
        job.logFile
    )
    cmdPayload := StrReplace(ffmpegArgs, '"', '""')
    Run Format('{1} /d /q /c "{2}"', A_ComSpec, cmdPayload), , "Hide", &pid

    job.pid := pid
    job.state := "转换中"
    job.startedAt := FormatTime(, "HH:mm:ss")
    job.detail := "PID " pid
}

UpdateRunningJob(job) {
    progress := ReadProgressFile(job.progressFile)
    if (progress.Has("percent"))
        job.percent := progress["percent"]

    if (progress.Has("detail"))
        job.detail := progress["detail"]

    if ProcessExist(job.pid) {
        job.state := "转换中"
        return
    }

    job.finishedAt := FormatTime(, "HH:mm:ss")
    if FileExist(job.output) {
        job.state := "已完成"
        job.percent := 100
        job.detail := "输出完成"
    } else {
        job.state := "失败"
        job.detail := ReadTail(job.logFile, 1)
        if (job.detail = "")
            job.detail := "ffmpeg 未生成输出文件"
    }
}

ReadProgressFile(progressFile) {
    result := Map()
    if !FileExist(progressFile)
        return result

    try text := FileRead(progressFile, "UTF-8")
    catch
        return result

    lastOutTimeMs := ""
    for _, line in StrSplit(text, ["`r`n", "`n", "`r"]) {
        if (line = "")
            continue
        if RegExMatch(line, "i)^out_time_ms=(\d+)$", &m)
            lastOutTimeMs := m[1] + 0
        else if RegExMatch(line, "i)^progress=(.+)$", &m)
            result["detail"] := (m[1] = "continue") ? "ffmpeg 处理中" : "ffmpeg 已结束"
    }

    if (lastOutTimeMs != "" && lastOutTimeMs >= 0) {
        durationMs := 0
        try durationMs := TimeToMsFromProgressFile(progressFile)
        catch
            durationMs := 0
        if (durationMs > 0) {
            percent := Round(Min(100, Max(0, (lastOutTimeMs / 1000) / durationMs * 100)))
            result["percent"] := percent
        }
    }

    return result
}

TimeToMsFromProgressFile(progressFile) {
    global g_runningJobs
    for _, job in g_runningJobs {
        if (job.progressFile = progressFile)
            return job.durationMs
    }
    return 0
}

TimeToMs(timeText) {
    if !RegExMatch(timeText, "^\s*(\d+):(\d{2}):(\d{2})\.(\d{1,3})\s*$", &m)
        return 0
    hours := m[1] + 0
    mins := m[2] + 0
    secs := m[3] + 0
    ms := m[4] + 0
    if (StrLen(m[4]) = 1)
        ms *= 100
    else if (StrLen(m[4]) = 2)
        ms *= 10
    return ((hours * 3600 + mins * 60 + secs) * 1000) + ms
}

BuildUniqueOutputPath(outputDir, baseName, ext) {
    safeBase := baseName
    if (safeBase = "")
        safeBase := "audio_clip"

    candidate := outputDir "\" safeBase "." ext
    index := 2
    while FileExist(candidate) {
        candidate := outputDir "\" safeBase "_" index "." ext
        index += 1
    }
    return candidate
}

ShowProgressWindow(*) {
    global g_progressGui, g_progressList

    if !g_progressGui {
        g_progressGui := Gui("+AlwaysOnTop +Resize", "音频转换队列")
        g_progressGui.SetFont("s10", "Microsoft YaHei")
        g_progressList := g_progressGui.Add("ListView", "w860 r18 Grid", ["ID", "状态", "进度", "片段名", "开始", "结束", "输出文件", "详情"])
        g_progressGui.Add("Button", "xm w120 h32", "刷新").OnEvent("Click", RefreshProgressView)
        g_progressGui.Add("Button", "x+10 w120 h32", "清空已完成").OnEvent("Click", ClearFinishedJobs)
        g_progressGui.OnEvent("Close", (*) => g_progressGui.Hide())
    }

    RefreshProgressView()
    g_progressGui.Show()
}

RefreshProgressView(*) {
    global g_progressGui, g_progressList, g_convertQueue, g_runningJobs, g_doneJobs

    if !g_progressGui || !g_progressList
        return

    g_progressList.Opt("-Redraw")
    g_progressList.Delete()

    for _, job in g_runningJobs
        AddJobRow(job)
    for _, job in g_convertQueue
        AddJobRow(job)
    loopCount := g_doneJobs.Length
    Loop loopCount {
        job := g_doneJobs[loopCount - A_Index + 1]
        AddJobRow(job)
    }

    try g_progressList.ModifyCol()
    g_progressList.Opt("+Redraw")
}

AddJobRow(job) {
    global g_progressList
    g_progressList.Add(
        ,
        job.id,
        job.state,
        job.percent "%",
        job.name,
        job.startedAt != "" ? job.startedAt : job.createdAt,
        job.finishedAt,
        job.output,
        job.detail
    )
}

ClearFinishedJobs(*) {
    global g_doneJobs
    g_doneJobs := []
    RefreshProgressView()
}

ReadTail(path, lineCount := 1) {
    if !FileExist(path)
        return ""

    try text := FileRead(path, "UTF-8")
    catch
        return ""

    lines := []
    for _, line in StrSplit(text, ["`r`n", "`n", "`r"]) {
        if (Trim(line) != "")
            lines.Push(line)
    }

    if (lines.Length = 0)
        return ""
    return lines[Max(1, lines.Length - lineCount + 1)]
}

TryDeleteFile(path) {
    try if FileExist(path)
        FileDelete(path)
}
