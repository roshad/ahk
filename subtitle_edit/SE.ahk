#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_ScriptDir%\SE_Audio_FFmpeg.ahk

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
global g_ankiDeckName := "00active::0日文::0例句::听力"
global g_ankiNoteType := "0常"
global g_ankiFrontField := "Front"
global g_ankiBackField := "Back"
global g_ankiTags := ["日语::jlpt::N1::2412"]  ; 可以是数组如 ["tag1", "tag2"]，或者空格分隔的字符串如 "tag1 tag2"，或者逗号分隔的字符串如 "tag1,tag2"
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

    subtitleInfo := ParseSelectedSubtitle(raw_text)
    if (subtitleInfo != "") {
        subtitleInfo := FillOriginalFromSubtitleEditOriginalFile(subtitleInfo)
        start_time := subtitleInfo["startTime"]
        end_time := subtitleInfo["endTime"]
        safe_name := Trim(RegExReplace(subtitleInfo["filenameText"], "[\\/:*?<>|]", "_"))
        safe_name := StrReplace(safe_name, '"', "_")

        output_file := BuildUniqueOutputPath(output_dir, safe_name, "ogg")
        EnqueueAudioJob(video_path, start_time, end_time, output_file, safe_name, subtitleInfo["original"], subtitleInfo["translation"])
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

ParseSelectedSubtitle(rawText) {
    rawText := Trim(rawText, "`r`n`t ")

    gridInfo := ParseSubtitleEditGridRow(rawText)
    if (gridInfo != "")
        return gridInfo

    if RegExMatch(rawText, "s)(?:\d+\R)?(\d{2}:\d{2}:\d{2},\d{3})\s+-->\s+(\d{2}:\d{2}:\d{2},\d{3})\R(.*)", &m) {
        blockInfo := ParseSubtitleBlock(m[3])
        blockInfo["startTime"] := StrReplace(m[1], ",", ".")
        blockInfo["endTime"] := StrReplace(m[2], ",", ".")
        return blockInfo
    }

    return ""
}

ParseSubtitleEditGridRow(rawText) {
    fields := StrSplit(rawText, "`t")
    if (fields.Length < 6)
        return ""

    rowNo := Trim(fields[1])
    showTime := NormalizeSeTime(fields[2])
    hideTime := NormalizeSeTime(fields[3])
    if !RegExMatch(rowNo, "^\d+$")
        return ""
    if (showTime = "" || hideTime = "")
        return ""

    textParts := []
    originalParts := []
    textParts.Push(fields[5])
    Loop fields.Length - 5
        originalParts.Push(fields[A_Index + 5])

    chineseText := NormalizeSubtitleText(JoinParts(textParts, "`n"))
    japaneseText := NormalizeSubtitleText(JoinParts(originalParts, "`n"))

    if (japaneseText = "" && IsLikelyJapaneseText(chineseText)) {
        japaneseText := chineseText
        chineseText := ""
    }

    filenameText := japaneseText != "" ? japaneseText : chineseText
    filenameText := RegExReplace(filenameText, "\s+", "")
    if (filenameText = "")
        filenameText := "audio_clip"

    return Map(
        "startTime", showTime,
        "endTime", hideTime,
        "original", japaneseText,
        "translation", chineseText,
        "filenameText", filenameText
    )
}

FillOriginalFromSubtitleEditOriginalFile(subtitleInfo) {
    if (!subtitleInfo.Has("startTime") || !subtitleInfo.Has("endTime"))
        return subtitleInfo

    originalText := subtitleInfo["original"]
    translationText := subtitleInfo["translation"]
    if (IsLikelyJapaneseText(originalText) && originalText != translationText)
        return subtitleInfo

    japaneseText := GetOriginalSubtitleTextFromSubtitleEdit(subtitleInfo["startTime"], subtitleInfo["endTime"])
    if (japaneseText = "") {
        if (originalText = translationText)
            subtitleInfo["translation"] := ""
        return subtitleInfo
    }

    chineseText := translationText != "" ? translationText : originalText
    if (chineseText = japaneseText)
        chineseText := ""

    subtitleInfo["original"] := japaneseText
    subtitleInfo["translation"] := chineseText
    subtitleInfo["filenameText"] := RegExReplace(japaneseText, "\s+", "")
    if (subtitleInfo["filenameText"] = "")
        subtitleInfo["filenameText"] := "audio_clip"
    return subtitleInfo
}

GetOriginalSubtitleTextFromSubtitleEdit(startTime, endTime) {
    originalSubtitlePath := GetSubtitleEditOriginalSubtitlePath()
    if (originalSubtitlePath = "")
        return ""
    return FindSubtitleTextByTime(originalSubtitlePath, startTime, endTime)
}

GetSubtitleEditOriginalSubtitlePath() {
    try {
        seHwnd := WinExist("ahk_exe SubtitleEdit.exe")
        if !seHwnd
            return ""

        title := WinGetTitle("ahk_id " seHwnd)
        originalFileName := GetOriginalSubtitleFileNameFromTitle(title)
        if (originalFileName = "")
            return ""
        primaryFileName := GetPrimarySubtitleFileNameFromTitle(title)

        if FileExist(originalFileName)
            return originalFileName

        pid := WinGetPID("ahk_id " seHwnd)
        subtitlePath := GetSubtitlePathFromProcessCommandLine(pid)
        if (subtitlePath != "") {
            SplitPath subtitlePath, , &subtitleDir
            if (subtitleDir != "") {
                candidate := subtitleDir "\" originalFileName
                if FileExist(candidate)
                    return candidate
            }
        }

        if (primaryFileName != "") {
            primaryPath := FindSubtitlePathInSubtitleEditSettings(primaryFileName)
            if (primaryPath = "")
                primaryPath := FindSubtitleFileInLikelyDirs(primaryFileName)
            if (primaryPath != "") {
                SplitPath primaryPath, , &primaryDir
                candidate := primaryDir "\" originalFileName
                if FileExist(candidate)
                    return candidate
            }
        }

        settingsPath := FindSubtitlePathInSubtitleEditSettings(originalFileName)
        if (settingsPath != "")
            return settingsPath

        mediaDirPath := FindSubtitleNextToCachedMedia(originalFileName)
        if (mediaDirPath != "")
            return mediaDirPath

        return FindSubtitleFileInLikelyDirs(originalFileName)
    } catch {
        return ""
    }
}

GetPrimarySubtitleFileNameFromTitle(title) {
    cleanTitle := Trim(RegExReplace(title, "^\*+\s*", ""))
    if RegExMatch(cleanTitle, 'i)^([^\\/:*?"<>|`r`n]+?\.(?:srt|ass|ssa|vtt|sub|sbv|txt))\s+\+', &m)
        return Trim(m[1])
    return ""
}

GetOriginalSubtitleFileNameFromTitle(title) {
    cleanTitle := Trim(RegExReplace(title, "^\*+\s*", ""))
    if RegExMatch(cleanTitle, 'i)\+\s*([^\\/:*?"<>|`r`n]+?\.(?:srt|ass|ssa|vtt|sub|sbv|txt))\s+-\s+Subtitle Edit', &m)
        return Trim(m[1])
    return ""
}

FindSubtitlePathInSubtitleEditSettings(fileName) {
    settingsPath := A_AppData "\Subtitle Edit\Settings.xml"
    if !FileExist(settingsPath)
        return ""

    try {
        xml := ComObject("Msxml2.DOMDocument.6.0")
        xml.async := false
        if !xml.load(settingsPath)
            return ""

        targetName := StrLower(fileName)
        nodes := xml.selectNodes("//RecentFiles/FileNames/FileName")
        for node in nodes {
            subtitlePath := node.text
            SplitPath subtitlePath, &name
            if (StrLower(name) = targetName && FileExist(subtitlePath))
                return subtitlePath
        }
    }
    return ""
}

FindSubtitleNextToCachedMedia(fileName) {
    global g_mediaPathCache

    if (g_mediaPathCache = "" || !FileExist(g_mediaPathCache))
        return ""

    SplitPath g_mediaPathCache, , &mediaDir
    if (mediaDir = "")
        return ""

    candidate := mediaDir "\" fileName
    if FileExist(candidate)
        return candidate

    return ""
}

FindSubtitleFileInLikelyDirs(fileName) {
    dirs := []
    userProfile := EnvGet("USERPROFILE")
    if (userProfile != "") {
        dirs.Push(userProfile "\Downloads")
        dirs.Push(userProfile "\Desktop")
        dirs.Push(userProfile "\Documents")
        dirs.Push(userProfile "\Videos")
    }
    dirs.Push(A_ScriptDir)

    for _, dir in dirs {
        if !DirExist(dir)
            continue
        Loop Files dir "\" fileName, "FR" {
            return A_LoopFileFullPath
        }
    }
    return ""
}

FindSubtitleTextByTime(subtitlePath, startTime, endTime) {
    try text := FileRead(subtitlePath, "UTF-8")
    catch {
        try text := FileRead(subtitlePath)
        catch
            return ""
    }

    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    startMs := TimeTextToMs(startTime)
    endMs := TimeTextToMs(endTime)
    if (startMs = "" || endMs = "")
        return ""

    for _, block in StrSplit(text, "`n`n") {
        block := Trim(block, "`n`t ")
        if RegExMatch(block, "s)^(?:\d+\s*\n)?(\d{2}:\d{2}:\d{2}[,.]\d{3})\s+-->\s+(\d{2}:\d{2}:\d{2}[,.]\d{3})(?:[^\n]*)\n(.*)$", &m) {
            blockStartMs := TimeTextToMs(m[1])
            blockEndMs := TimeTextToMs(m[2])
            if (Abs(blockStartMs - startMs) <= 80 && Abs(blockEndMs - endMs) <= 80)
                return NormalizeSubtitleText(RegExReplace(m[3], "<[^>]+>", ""))
        }
    }
    return ""
}

TimeTextToMs(timeText) {
    if !RegExMatch(timeText, "^\s*(\d+):(\d{2}):(\d{2})[,.](\d{1,3})\s*$", &m)
        return ""
    ms := m[4] + 0
    if (StrLen(m[4]) = 1)
        ms *= 100
    else if (StrLen(m[4]) = 2)
        ms *= 10
    return (((m[1] + 0) * 3600 + (m[2] + 0) * 60 + (m[3] + 0)) * 1000) + ms
}

ParseSubtitleBlock(subtitleBlock) {
    cleanedBlock := RegExReplace(subtitleBlock, "<[^>]+>", "")
    lines := []
    for _, line in StrSplit(cleanedBlock, ["`r`n", "`n", "`r"]) {
        line := Trim(line)
        if (line != "")
            lines.Push(line)
    }

    original := ""
    translation := ""
    japaneseParts := []
    translationParts := []
    for _, line in lines {
        normalizedLine := NormalizeSubtitleLine(line)
        if (IsLikelyJapaneseText(normalizedLine) && !IsLikelyChineseOnlyText(normalizedLine))
            japaneseParts.Push(normalizedLine)
        else
            translationParts.Push(normalizedLine)
    }

    original := JoinParts(japaneseParts, "`n")
    translation := JoinParts(translationParts, "`n")

    if (original = "" && lines.Length >= 1) {
        original := NormalizeSubtitleLine(lines[1])
        if (lines.Length >= 2) {
            translationParts := []
            Loop lines.Length - 1
                translationParts.Push(NormalizeSubtitleLine(lines[A_Index + 1]))
            translation := JoinParts(translationParts, "`n")
        }
    }

    filenameText := original
    if (filenameText = "")
        filenameText := NormalizeSubtitleLine(cleanedBlock)
    filenameText := RegExReplace(filenameText, "\s+", "")
    if (filenameText = "")
        filenameText := "audio_clip"

    return Map(
        "original", original,
        "translation", translation,
        "filenameText", filenameText
    )
}

NormalizeSeTime(text) {
    text := Trim(text)
    if !RegExMatch(text, "^\d{2}:\d{2}:\d{2},\d{3}$")
        return ""
    return StrReplace(text, ",", ".")
}

NormalizeSubtitleLine(text) {
    text := RegExReplace(text, "\s+", " ")
    return Trim(text)
}

NormalizeSubtitleText(text) {
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    text := RegExReplace(text, "[ `t]+\n", "`n")
    text := RegExReplace(text, "\n[ `t]+", "`n")
    text := RegExReplace(text, "\n{2,}", "`n")
    return Trim(text)
}

IsLikelyJapaneseText(text) {
    return RegExMatch(text, "[\x{3040}-\x{30FF}]")
}

IsLikelyChineseOnlyText(text) {
    return RegExMatch(text, "[\x{4E00}-\x{9FFF}]") && !IsLikelyJapaneseText(text)
}

JoinParts(parts, separator) {
    result := ""
    for _, part in parts {
        if (part = "")
            continue
        result .= (result = "" ? "" : separator) part
    }
    return result
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


AddAudioCardToAnki(job) {
    job.ankiAttempted := true
    try {
        response := SendAnkiAddNoteRequest(job.output, job.originalText, job.translationText)
        if RegExMatch(response, '"error"\s*:\s*null') {
            job.ankiAdded := true
            job.detail := "已导入 Anki"
            return
        }

        if RegExMatch(response, '"error"\s*:\s*"((?:\\.|[^"])*)"', &m)
            job.detail := "Anki 导入失败: " JsonUnescape(m[1])
        else
            job.detail := "Anki 导入失败"
    } catch as err {
        job.detail := "Anki 导入失败: " err.Message
    }
}

SendAnkiAddNoteRequest(audioPath, originalText, translationText) {
    global g_ankiDeckName, g_ankiNoteType, g_ankiFrontField, g_ankiBackField, g_ankiTags

    backHtml := BuildAnkiBackHtml(originalText, translationText)
    audioFileName := GetFileName(audioPath)

    frontHtml := '<audio id="anki-audio" src="' audioFileName '" controls autoplay style="width: 100%; max-width: 480px; margin: 10px auto; display: block;"></audio>'
        . '<script>'
        . 'if (!window.ankiAudioListenerAdded) {'
        . '    window.ankiAudioListenerAdded = true;'
        . '    document.addEventListener("keydown", function(e) {'
        . '        if (e.key === "r" || e.key === "R") {'
        . '            var audio = document.getElementById("anki-audio");'
        . '            if (audio) { audio.currentTime = 0; audio.play(); }'
        . '        }'
        . '    });'
        . '}'
        . '</script>'

    payload := '{'
        . '"action":"addNote",'
        . '"version":6,'
        . '"params":{"note":{'
        . '"deckName":"' JsonEscape(g_ankiDeckName) '",'
        . '"modelName":"' JsonEscape(g_ankiNoteType) '",'
        . '"fields":{'
        . '"' JsonEscape(g_ankiFrontField) '":"' JsonEscape(frontHtml) '",'
        . '"' JsonEscape(g_ankiBackField) '":"' JsonEscape(backHtml) '"'
        . '},'
        . '"tags":' BuildAnkiTagsJson(g_ankiTags) ','
        . '"options":{"allowDuplicate":true},'
        . '"audio":[{'
        . '"path":"' JsonEscape(audioPath) '",'
        . '"filename":"' JsonEscape(audioFileName) '",'
        . '"fields":[]'
        . '}]'
        . '}}}'

    http := ComObject("WinHttp.WinHttpRequest.5.1")
    http.Open("POST", "http://127.0.0.1:8765", false)
    http.SetRequestHeader("Content-Type", "application/json")
    http.Send(payload)
    return http.ResponseText
}

GetFileName(path) {
    SplitPath path, &name
    return name
}

HtmlEscape(text) {
    text := StrReplace(text, "&", "&amp;")
    text := StrReplace(text, "<", "&lt;")
    text := StrReplace(text, ">", "&gt;")
    return text
}

BuildAnkiBackHtml(originalText, translationText) {
    backHtml := HtmlEscape(originalText)
    if (translationText != "")
        backHtml .= "<br><br>" StrReplace(HtmlEscape(translationText), "`n", "<br>")
    return backHtml
}

BuildAnkiTagsJson(tags) {
    if (IsObject(tags)) {
        jsonTags := ""
        for _, tag in tags {
            jsonTags .= (jsonTags = "" ? "" : ",") '"' JsonEscape(tag) '"'
        }
        return "[" jsonTags "]"
    } else {
        strTags := String(tags)
        if (Trim(strTags) = "")
            return "[]"
        delim := InStr(strTags, ",") ? "," : " "
        jsonTags := ""
        for _, tag in StrSplit(strTags, delim) {
            t := Trim(tag)
            if (t != "")
                jsonTags .= (jsonTags = "" ? "" : ",") '"' JsonEscape(t) '"'
        }
        return "[" jsonTags "]"
    }
}

JsonEscape(text) {
    text := StrReplace(text, "\", "\\")
    text := StrReplace(text, '"', '\"')
    text := StrReplace(text, "`r", "\r")
    text := StrReplace(text, "`n", "\n")
    text := StrReplace(text, "`t", "\t")
    return text
}

JsonUnescape(text) {
    text := StrReplace(text, '\"', '"')
    text := StrReplace(text, "\r", "`r")
    text := StrReplace(text, "\n", "`n")
    text := StrReplace(text, "\t", "`t")
    text := StrReplace(text, "\\", "\")
    return text
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
