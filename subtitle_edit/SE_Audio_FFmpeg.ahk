; SE_Audio_FFmpeg.ahk
; 处理音频媒体文件查找、提取和 FFmpeg 队列转换逻辑

ResolveMediaPath() {
    global g_mediaPathCache

    if (g_mediaPathCache != "" && FileExist(g_mediaPathCache)) {
        SaveLastMediaPath(g_mediaPathCache)
        return g_mediaPathCache
    }

    lastMediaPath := LoadLastMediaPath()
    if (lastMediaPath != "" && FileExist(lastMediaPath)) {
        g_mediaPathCache := lastMediaPath
        return lastMediaPath
    }

    if mediaPath := GetMediaPathFromSubtitleEdit() {
        g_mediaPathCache := mediaPath
        SaveLastMediaPath(mediaPath)
        return mediaPath
    }

    selected := FileSelect(1, , "选择音频/视频文件", "Media Files (*.opus; *.mp3; *.wav; *.m4a; *.flac; *.ogg; *.aac; *.mp4; *.mkv; *.webm)")
    if (selected != "") {
        g_mediaPathCache := selected
        SaveLastMediaPath(selected)
        return selected
    }

    return ""
}

LoadLastMediaPath() {
    try {
        path := IniRead(GetSeAudioSettingsPath(), "Media", "LastPath", "")
        if (path != "" && FileExist(path))
            return path
    }
    return ""
}

SaveLastMediaPath(path) {
    if (path = "")
        return

    try {
        settingsPath := GetSeAudioSettingsPath()
        SplitPath settingsPath, , &settingsDir
        if (settingsDir != "")
            DirCreate(settingsDir)
        IniWrite(path, settingsPath, "Media", "LastPath")
    }
}

GetDefaultMediaSelectPath() {
    global g_mediaPathCache

    if (g_mediaPathCache != "" && FileExist(g_mediaPathCache))
        return g_mediaPathCache

    lastMediaPath := LoadLastMediaPath()
    if (lastMediaPath != "")
        return lastMediaPath

    return ""
}

GetSeAudioSettingsPath() {
    return A_AppData "\SE_Audio_FFmpeg\settings.ini"
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

InitAudioQueue() {
    global g_queueTimerStarted

    if g_queueTimerStarted
        return

    A_TrayMenu.Add()
    A_TrayMenu.Add("手动指定音视频", ManualSelectMedia)
    A_TrayMenu.Add("转换进度", ShowProgressWindow)
    A_TrayMenu.Add("清空已完成记录", ClearFinishedJobs)
    SetTimer(ProcessAudioQueue, 500)
    g_queueTimerStarted := true
}

ManualSelectMedia(*) {
    global g_mediaPathCache
    selected := FileSelect(1, , "手动指定后续处理的音频/视频文件", "Media Files (*.opus; *.mp3; *.wav; *.m4a; *.flac; *.ogg; *.aac; *.mp4; *.mkv; *.webm)")
    if (selected != "") {
        g_mediaPathCache := selected
        MsgBox("已强制指定，接下来的切片将使用此文件：`n" selected, "指定成功", "T3")
    }
}

EnqueueAudioJob(videoPath, startTime, endTime, outputFile, displayName, originalText := "", translationText := "") {
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
        detail: "",
        originalText: originalText,
        translationText: translationText,
        ankiAdded: false,
        ankiAttempted: false
    })

    RefreshProgressView()
}

ProcessAudioQueue(*) {
    global g_convertQueue, g_runningJobs, g_doneJobs, g_maxConcurrentJobs

    for jobId, job in g_runningJobs.Clone() {
        UpdateRunningJob(job)
        if (!ProcessExist(job.pid) && !job.ankiAttempted && FileExist(job.output))
            AddAudioCardToAnki(job)
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
    
    ; 强制 cmd.exe 使用 UTF-8 (65001) 来解析和运行命令行，防止带有日文的视频路径变成问号，导致找不到输入文件。
    Run Format('{1} /d /q /c "chcp 65001 >nul & {2}"', A_ComSpec, cmdPayload), , "Hide", &pid

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
            job.detail := "ffmpeg 未生成输出"
        ; 将输入文件包含在详情中，以便排查是不是路径本身找错了
        job.detail := "输入文件: " GetFileName(job.input) " | " job.detail
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
    for _, line in StrSplit(text, ["``r``n", "``n", "``r"]) {
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

ReadTail(path, lineCount := 1) {
    if !FileExist(path)
        return ""

    try text := FileRead(path, "UTF-8")
    catch
        return ""

    lines := []
    for _, line in StrSplit(text, ["``r``n", "``n", "``r"]) {
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
