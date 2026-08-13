#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

global MainGui := ""
global AddButton := ""
global NewGroupButton := ""
global SortButton := ""
global TrashButton := ""
global SettingsButton := ""
global PrevButton := ""
global NextButton := ""
global StatusText := ""
global EmptyText := ""
global Snippets := []
global ButtonToSnippet := Map()
global CurrentPage := 1
global LastClientWidth := 1000
global LastClientHeight := 700
global LastTargetHwnd := 0
global SettingsPath := A_ScriptDir "\文本段保存面板设置.ini"
global StorageRoot := A_ScriptDir
global DataDir := ""
global OrderPath := ""
global LayoutPath := ""
global TrashDir := ""
global BackupDir := ""
global SafetyBackupMade := false
global SortModeActive := false
global SortDragFrom := 0
global SortDragTo := 0
global SortDragMoved := false
global SortOrderDirty := false
global SortDragType := ""
global SortDragId := ""
global SortDropMessage := ""
global SortLastTargetKey := ""
global Groups := []
global GroupById := Map()
global RootItems := []
global SnippetById := Map()
global GroupControlToGroup := Map()
global UngroupedPanel := ""
global UngroupedTitle := ""
global LayoutRegions := []
global DarkEditHandles := Map()
global DarkEditBrush := 0
global LastContextMenuTick := 0
global LastContextMenuHwnd := 0

Initialize()

!+v::ToggleMainGui()

Initialize() {
    global MainGui, AddButton, NewGroupButton, SortButton, TrashButton, SettingsButton, PrevButton, NextButton
    global StatusText, EmptyText, DataDir, TrashDir, BackupDir

    LoadStorageSettings()
    DirCreate(DataDir)
    DirCreate(TrashDir)
    DirCreate(BackupDir)
    LoadSnippets()
    CreateDailyBackup()

    MainGui := Gui("+Resize +MinSize760x480", "文本段保存面板")
    MainGui.BackColor := "202124"
    MainGui.SetFont("s10 cE8EAED", "Microsoft YaHei UI")

    AddButton := MainGui.AddButton("x20 y18 w140 h42 Default", "+ 添加文本")
    NewGroupButton := MainGui.AddButton("x170 y22 w96 h34", "+ 分组")
    SortButton := MainGui.AddButton("x274 y22 w88 h34", "排序")
    TrashButton := MainGui.AddButton("x370 y22 w88 h34", "回收站")
    SettingsButton := MainGui.AddButton("x466 y22 w100 h34", "存储位置")
    AddButton.SetFont("s11 Bold", "Microsoft YaHei UI")
    AddButton.OnEvent("Click", OpenAddDialog)
    NewGroupButton.OnEvent("Click", OpenCreateGroup)
    SortButton.OnEvent("Click", ToggleSortMode)
    TrashButton.OnEvent("Click", OpenTrashManager)
    SettingsButton.OnEvent("Click", ChooseStorageLocation)

    PrevButton := MainGui.AddButton("x600 y22 w72 h34", "上一页")
    NextButton := MainGui.AddButton("x680 y22 w72 h34", "下一页")
    PrevButton.OnEvent("Click", ChangePage.Bind(-1))
    NextButton.OnEvent("Click", ChangePage.Bind(1))

    StatusText := MainGui.AddText("x464 y28 w130 h28 +0x200", "")
    StatusText.SetFont("s9 cAAB2BD", "Microsoft YaHei UI")

    EmptyText := MainGui.AddText("x20 y100 w700 h80 Center +0x200", "还没有保存文本。`n点击“添加文本”创建第一条内容。")
    EmptyText.SetFont("s14 c8AB4F8", "Microsoft YaHei UI")

    CreateUngroupedControls()
    CreateGroupControls()
    CreateSnippetButtons()
    EnableDarkWindow(MainGui)
    for control in [AddButton, NewGroupButton, SortButton, TrashButton, SettingsButton, PrevButton, NextButton]
        EnableDarkControl(control)

    MainGui.OnEvent("Size", MainGuiSize)
    MainGui.OnEvent("Close", HideMainGui)
    MainGui.OnEvent("Escape", HideMainGui)

    ConfigureTrayMenu()
    OnMessage(0x007B, HandleContextMenu)
    OnMessage(0x0205, HandleRightButtonUp)
    OnMessage(0x0201, SortMouseDown)
    OnMessage(0x0200, SortMouseMove)
    OnMessage(0x0202, SortMouseUp)
    OnMessage(0x0133, HandleEditControlColor)

    TrackActiveWindow()
    MainGui.Show("Maximize")
    SetTimer(TrackActiveWindow, 150)
}

ConfigureTrayMenu() {
    ; Insert panel commands before AutoHotkey's standard tray commands.
    ; Keep the built-in Open, Reload Script, Edit Script, Pause and Exit items.
    A_TrayMenu.Insert("1&", "显示/隐藏面板 (Alt+Shift+V)", ToggleMainGui)
    A_TrayMenu.Insert("2&", "打开数据目录", OpenDataFolder)
    A_TrayMenu.Insert("3&", "打开备份目录", OpenBackupFolder)
    A_TrayMenu.Insert("4&", "设置存储位置...", ChooseStorageLocation)
    A_TrayMenu.Insert("5&")
    A_TrayMenu.Default := "显示/隐藏面板 (Alt+Shift+V)"
    A_TrayMenu.ClickCount := 1
}

LoadStorageSettings() {
    global SettingsPath, StorageRoot

    configuredRoot := ""
    if FileExist(SettingsPath) {
        try configuredRoot := IniRead(SettingsPath, "Storage", "Root", "")
        catch
            configuredRoot := ""
    }

    configuredRoot := NormalizeStorageRoot(configuredRoot)
    if (configuredRoot = "") {
        SetStoragePaths(A_ScriptDir)
        return
    }

    if DirExist(configuredRoot) {
        SetStoragePaths(configuredRoot)
        return
    }

    SetStoragePaths(A_ScriptDir)
    MsgBox("配置的存储位置当前不可用：`n`n" configuredRoot "`n`n本次将临时使用脚本所在目录。设置不会被清除，下次启动时会再次尝试。", "存储位置不可用", "Icon!")
}

SetStoragePaths(root) {
    global StorageRoot, DataDir, OrderPath, LayoutPath, TrashDir, BackupDir

    StorageRoot := NormalizeStorageRoot(root)
    DataDir := StorageRoot "\文本段保存面板数据"
    OrderPath := DataDir "\order.txt"
    LayoutPath := DataDir "\layout.ini"
    TrashDir := StorageRoot "\文本段保存面板回收站"
    BackupDir := StorageRoot "\文本段保存面板备份"
}

NormalizeStorageRoot(path) {
    path := Trim(path, " `t`r`n")
    while (StrLen(path) > 3 && (SubStr(path, -1) = "\" || SubStr(path, -1) = "/"))
        path := SubStr(path, 1, -1)
    return path
}

ChooseStorageLocation(*) {
    global StorageRoot, SettingsPath

    selectedRoot := DirSelect(, 3, "选择存储根目录（将在其中创建数据、回收站和备份文件夹）")
    selectedRoot := NormalizeStorageRoot(selectedRoot)
    if (selectedRoot = "" || selectedRoot = StorageRoot)
        return

    try DirCreate(selectedRoot)
    catch as err {
        MsgBox("无法创建或使用所选目录：`n" err.Message, "设置存储位置", "Iconx")
        return
    }

    targetHasData := ManagedRootHasData(selectedRoot)
    sourceHasData := ManagedRootHasData(StorageRoot)

    if targetHasData {
        result := MsgBox("目标位置已经包含文本面板数据。`n`n切换后将直接使用目标中的数据，不会覆盖或合并当前数据。是否继续？", "使用已有数据", "YesNo Icon!")
        if (result != "Yes")
            return
    } else if sourceHasData {
        result := MsgBox("是否将当前文本、顺序、回收站和备份复制到新位置？`n`n是：复制后切换`n否：使用新的空存储位置`n取消：不作更改", "迁移现有数据", "YesNoCancel Icon?")
        if (result = "Cancel")
            return
        if (result = "Yes") {
            try CopyManagedData(StorageRoot, selectedRoot)
            catch as err {
                MsgBox("复制现有数据失败，存储位置没有切换：`n" err.Message, "迁移失败", "Iconx")
                return
            }
        }
    }

    try IniWrite(selectedRoot, SettingsPath, "Storage", "Root")
    catch as err {
        MsgBox("无法保存存储位置设置：`n" err.Message, "设置失败", "Iconx")
        return
    }

    MsgBox("存储位置已设置为：`n`n" selectedRoot "`n`n脚本将重新加载并使用该位置。", "设置完成", "Iconi")
    Reload()
}

ManagedRootHasData(root) {
    for folderName in ["文本段保存面板数据", "文本段保存面板回收站", "文本段保存面板备份"] {
        folderPath := NormalizeStorageRoot(root) "\" folderName
        if !DirExist(folderPath)
            continue
        Loop Files, folderPath "\*", "FR"
            return true
    }
    return false
}

CopyManagedData(sourceRoot, targetRoot) {
    for folderName in ["文本段保存面板数据", "文本段保存面板回收站", "文本段保存面板备份"] {
        sourcePath := NormalizeStorageRoot(sourceRoot) "\" folderName
        targetPath := NormalizeStorageRoot(targetRoot) "\" folderName
        if DirExist(sourcePath)
            DirCopy(sourcePath, targetPath, 0)
    }
}

OpenDataFolder(*) {
    global DataDir
    OpenFolder(DataDir)
}

OpenBackupFolder(*) {
    global BackupDir
    OpenFolder(BackupDir)
}

OpenFolder(path) {
    DirCreate(path)
    Run("explorer.exe " Chr(34) path Chr(34))
}

ToggleMainGui(*) {
    global MainGui

    if DllCall("IsWindowVisible", "Ptr", MainGui.Hwnd) {
        MainGui.Hide()
        return
    }

    TrackActiveWindow()
    MainGui.Show("Maximize")
    WinActivate("ahk_id " MainGui.Hwnd)
}

HideMainGui(*) {
    global MainGui
    MainGui.Hide()
}

LoadSnippets() {
    global Snippets, DataDir, OrderPath, LayoutPath, SnippetById
    global Groups, GroupById, RootItems

    Snippets := []
    SnippetById := Map()
    Loop Files, DataDir "\*.txt", "F" {
        if (A_LoopFileName = "order.txt")
            continue

        textPath := A_LoopFileFullPath
        SplitPath(textPath, , , , &id)
        titlePath := DataDir "\" id ".title"

        try content := FileRead(textPath, "UTF-8")
        catch
            continue

        title := ""
        if FileExist(titlePath) {
            try title := FileRead(titlePath, "UTF-8")
            catch
                title := ""
        }

        snippet := {
            Id: id,
            Title: Trim(title, " `t`r`n"),
            Content: content,
            GroupId: "",
            Button: ""
        }
        Snippets.Push(snippet)
        SnippetById[id] := snippet
    }

    Groups := []
    GroupById := Map()
    RootItems := []
    if FileExist(LayoutPath)
        LoadLayoutFile()
    else
        LoadLegacyLayout()
}

LoadLegacyLayout() {
    global Snippets, SnippetById, RootItems, OrderPath

    seen := Map()
    if FileExist(OrderPath) {
        try orderText := FileRead(OrderPath, "UTF-8")
        catch
            orderText := ""

        for line in StrSplit(StrReplace(orderText, "`r", ""), "`n") {
            id := Trim(line)
            if (id != "" && SnippetById.Has(id) && !seen.Has(id)) {
                RootItems.Push("s:" id)
                seen[id] := true
            }
        }
    }

    for snippet in Snippets {
        if !seen.Has(snippet.Id)
            RootItems.Push("s:" snippet.Id)
    }
}

LoadLayoutFile() {
    global LayoutPath, Snippets, SnippetById, Groups, GroupById, RootItems
    global OrderPath

    raw := ""
    try raw := FileRead(LayoutPath, "UTF-8")
    catch {
        LoadLegacyLayout()
        return
    }

    records := Map()
    section := ""
    rootItemsText := ""
    for line in StrSplit(StrReplace(raw, "`r", ""), "`n") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if RegExMatch(line, "^\[(.+)\]$", &sectionMatch) {
            section := sectionMatch[1]
            continue
        }
        if !RegExMatch(line, "^([^=]+)=(.*)$", &valueMatch)
            continue

        key := Trim(valueMatch[1])
        value := valueMatch[2]
        if (section = "Root" && key = "Items") {
            rootItemsText := value
            continue
        }
        if RegExMatch(section, "^Group\.(.+)$", &groupMatch) {
            id := groupMatch[1]
            if !records.Has(id)
                records[id] := Map()
            records[id][key] := value
        }
    }

    for id, record in records {
        group := {
            Id: id,
            Title: DecodeLayoutValue(record.Has("Title") ? record["Title"] : "未命名分组"),
            ParentId: DecodeLayoutValue(record.Has("ParentId") ? record["ParentId"] : ""),
            Rows: ParsePositiveInt(record.Has("Rows") ? record["Rows"] : "2", 2),
            Cols: ParsePositiveInt(record.Has("Cols") ? record["Cols"] : "2", 2),
            Items: [],
            Frame: "",
            TitleControl: "",
            MenuButton: ""
        }
        if record.Has("Items")
            group.Items := ParseLayoutItems(record["Items"])
        Groups.Push(group)
        GroupById[id] := group
    }

    usedSnippets := Map()
    usedGroups := Map()
    RootItems := []
    for token in ParseLayoutItems(rootItemsText) {
        if (SubStr(token, 1, 2) = "s:" && SnippetById.Has(SubStr(token, 3))) {
            id := SubStr(token, 3)
            if !usedSnippets.Has(id) {
                RootItems.Push(token)
                usedSnippets[id] := true
            }
        } else if (SubStr(token, 1, 2) = "g:" && GroupById.Has(SubStr(token, 3))) {
            id := SubStr(token, 3)
            if !usedGroups.Has(id) {
                RootItems.Push(token)
                usedGroups[id] := true
            }
        }
    }

    for group in Groups {
        filtered := []
        for token in group.Items {
            if (SubStr(token, 1, 2) = "s:" && SnippetById.Has(SubStr(token, 3))) {
                id := SubStr(token, 3)
                if !usedSnippets.Has(id) {
                    filtered.Push(token)
                    usedSnippets[id] := true
                    SnippetById[id].GroupId := group.Id
                }
            } else if (SubStr(token, 1, 2) = "g:" && GroupById.Has(SubStr(token, 3))) {
                childId := SubStr(token, 3)
                if !usedGroups.Has(childId) {
                    filtered.Push(token)
                    usedGroups[childId] := true
                    GroupById[childId].ParentId := group.Id
                }
            }
        }
        group.Items := filtered
    }

    for snippet in Snippets {
        if !usedSnippets.Has(snippet.Id)
            RootItems.Push("s:" snippet.Id)
    }
    for group in Groups {
        if !usedGroups.Has(group.Id)
            RootItems.Push("g:" group.Id)
    }
}

ParseLayoutItems(text) {
    items := []
    for value in StrSplit(text, "|") {
        value := Trim(value)
        if (value != "")
            items.Push(value)
    }
    return items
}

ParseNonNegativeInt(value, fallback) {
    value := Trim(value)
    if !RegExMatch(value, "^\d+$")
        return fallback

    number := value + 0
    return number >= 0 ? number : fallback
}

ParsePositiveInt(value, fallback) {
    value := Trim(value)
    if !RegExMatch(value, "^\d+$")
        return fallback

    number := value + 0
    return number > 0 ? number : fallback
}

EncodeLayoutValue(value) {
    slash := Chr(92)
    value := StrReplace(value, "`r`n", "`n")
    value := StrReplace(value, "`r", "`n")
    value := StrReplace(value, slash, slash . slash)
    value := StrReplace(value, "`n", slash . "n")
    return value
}

DecodeLayoutValue(value) {
    slash := Chr(92)
    placeholder := Chr(1)
    value := StrReplace(value, slash . slash, placeholder)
    value := StrReplace(value, slash . "n", "`n")
    return StrReplace(value, placeholder, slash)
}

JoinLayoutItems(items) {
    result := ""
    for token in items
        result .= (result = "" ? "" : "|") token
    return result
}

WriteLayout() {
    global LayoutPath, RootItems, Groups

    text := "[Meta]`nVersion=1`n`n[Root]`nItems=" JoinLayoutItems(RootItems) "`n"
    for group in Groups {
        text .= "`n[Group." group.Id "]`n"
        text .= "Title=" EncodeLayoutValue(group.Title) "`n"
        text .= "ParentId=" EncodeLayoutValue(group.ParentId) "`n"
        text .= "Rows=" group.Rows "`n"
        text .= "Cols=" group.Cols "`n"
        text .= "Items=" JoinLayoutItems(group.Items) "`n"
    }
    WriteTextAtomic(LayoutPath, text)
    WriteLegacyOrder()
}

WriteLegacyOrder() {
    global Snippets, OrderPath, RootItems, Groups

    ids := []
    seen := Map()
    AppendSnippetIds(RootItems, ids, seen)
    for group in Groups {
        AppendSnippetIds(group.Items, ids, seen)
    }

    text := ""
    for id in ids
        text .= id "`n"
    WriteTextAtomic(OrderPath, RTrim(text, "`n"))
}

AppendSnippetIds(items, ids, seen) {
    global SnippetById, GroupById

    for token in items {
        type := SubStr(token, 1, 2)
        id := SubStr(token, 3)
        if (type = "s:" && SnippetById.Has(id) && !seen.Has(id)) {
            ids.Push(id)
            seen[id] := true
        } else if (type = "g:" && GroupById.Has(id)) {
            AppendSnippetIds(GroupById[id].Items, ids, seen)
        }
    }
}

GetUngroupedTokens() {
    global RootItems

    tokens := []
    for token in RootItems {
        if (SubStr(token, 1, 2) = "s:")
            tokens.Push(token)
    }
    return tokens
}

FindTokenIndex(items, token) {
    for index, value in items {
        if (value = token)
            return index
    }
    return 0
}

RemoveTokenFromLayout(token) {
    global RootItems, Groups

    index := FindTokenIndex(RootItems, token)
    if index {
        RootItems.RemoveAt(index)
        return true
    }
    for group in Groups {
        index := FindTokenIndex(group.Items, token)
        if index {
            group.Items.RemoveAt(index)
            return true
        }
    }
    return false
}

FindSnippetLocation(id) {
    global SnippetById, RootItems, Groups

    token := "s:" id
    if FindTokenIndex(RootItems, token)
        return {GroupId: "", Items: RootItems}
    for group in Groups {
        if FindTokenIndex(group.Items, token)
            return {GroupId: group.Id, Items: group.Items}
    }
    return 0
}

FindGroupLocation(id) {
    global RootItems, Groups

    token := "g:" id
    if FindTokenIndex(RootItems, token)
        return {ParentId: "", Items: RootItems}
    for group in Groups {
        if FindTokenIndex(group.Items, token)
            return {ParentId: group.Id, Items: group.Items}
    }
    return 0
}

InsertSnippetIntoGroup(snippet, group) {
    token := "s:" snippet.Id
    RemoveTokenFromLayout(token)
    group.Items.Push(token)
    snippet.GroupId := group.Id
}

InsertSnippetIntoRoot(snippet) {
    token := "s:" snippet.Id
    RemoveTokenFromLayout(token)
    RootItems.Push(token)
    snippet.GroupId := ""
}

WriteOrder() {
    WriteLayout()
}

WriteTextAtomic(path, content) {
    tempPath := path ".tmp-" A_TickCount "-" Random(1000, 9999)
    try {
        FileAppend(content, tempPath, "UTF-8")
        FileMove(tempPath, path, 1)
    } catch as err {
        try FileDelete(tempPath)
        throw err
    }
}

CreateDailyBackup() {
    global BackupDir

    today := FormatTime(, "yyyyMMdd")
    Loop Files, BackupDir "\" today "-*", "D"
        return

    dataTime := GetNewestDataTime()
    if (dataTime = "")
        return

    backupTime := GetNewestBackupTime()
    if (backupTime = "" || dataTime > backupTime)
        CreateBackup()
}

EnsureSafetyBackup() {
    global SafetyBackupMade

    if SafetyBackupMade
        return true

    SafetyBackupMade := CreateBackup()
    return SafetyBackupMade
}

CreateBackup() {
    global DataDir, BackupDir

    hasData := false
    Loop Files, DataDir "\*", "F" {
        hasData := true
        break
    }
    if !hasData
        return false

    stamp := FormatTime(, "yyyyMMdd-HHmmss")
    finalDir := BackupDir "\" stamp
    if DirExist(finalDir)
        finalDir .= "-" Random(1000, 9999)
    tempDir := BackupDir "\.tmp-" stamp "-" Random(1000, 9999)

    try {
        DirCreate(tempDir)
        Loop Files, DataDir "\*", "F"
            FileCopy(A_LoopFileFullPath, tempDir "\" A_LoopFileName, 1)
        DirMove(tempDir, finalDir)
        PruneBackups()
        return true
    } catch {
        try DirDelete(tempDir, true)
        return false
    }
}

GetNewestDataTime() {
    global DataDir

    newest := ""
    Loop Files, DataDir "\*", "F" {
        try modified := FileGetTime(A_LoopFileFullPath, "M")
        catch
            continue
        if (newest = "" || modified > newest)
            newest := modified
    }
    return newest
}

GetNewestBackupTime() {
    global BackupDir

    newest := ""
    Loop Files, BackupDir "\20*", "D" {
        try modified := FileGetTime(A_LoopFileFullPath, "M")
        catch
            continue
        if (newest = "" || modified > newest)
            newest := modified
    }
    return newest
}

PruneBackups() {
    global BackupDir

    names := ""
    Loop Files, BackupDir "\20*", "D"
        names .= A_LoopFileName "`n"
    names := RTrim(names, "`n")
    if (names = "")
        return

    sorted := StrSplit(Sort(names, "R"), "`n")
    for index, name in sorted {
        if (index > 10)
            try DirDelete(BackupDir "\" name, true)
    }
}

CreateSnippetButtons() {
    global Snippets

    for snippet in Snippets
        CreateButtonForSnippet(snippet)
}

CreateUngroupedControls() {
    global MainGui, UngroupedPanel, UngroupedTitle, GroupControlToGroup

    UngroupedPanel := MainGui.AddText("Hidden +Border", "")
    UngroupedPanel.BackColor := "202124"
    EnableDarkControl(UngroupedPanel)
    UngroupedTitle := MainGui.AddText("Hidden", "未分组")
    UngroupedTitle.SetFont("s10 Bold c8AB4F8", "Microsoft YaHei UI")
    EnableDarkControl(UngroupedTitle)
    GroupControlToGroup[UngroupedPanel.Hwnd] := {Type: "root"}
    GroupControlToGroup[UngroupedTitle.Hwnd] := {Type: "root"}
}

CreateGroupControls() {
    global Groups

    for group in Groups
        CreateGroupControlsFor(group)
}

CreateGroupControlsFor(group) {
    global MainGui, GroupControlToGroup

    group.Frame := MainGui.AddText("Hidden +Border", "")
    group.Frame.BackColor := "202124"
    EnableDarkControl(group.Frame)
    group.TitleControl := MainGui.AddText("Hidden", group.Title)
    group.TitleControl.SetFont("s10 Bold c8AB4F8", "Microsoft YaHei UI")
    EnableDarkControl(group.TitleControl)
    group.MenuButton := MainGui.AddButton("Hidden", "操作")
    group.MenuButton.SetFont("s9", "Microsoft YaHei UI")
    group.MenuButton.OnEvent("Click", OpenGroupMenu.Bind(group.Id))
    EnableDarkControl(group.MenuButton)
    GroupControlToGroup[group.Frame.Hwnd] := {Type: "group", Id: group.Id}
    GroupControlToGroup[group.TitleControl.Hwnd] := {Type: "group", Id: group.Id}
    GroupControlToGroup[group.MenuButton.Hwnd] := {Type: "group", Id: group.Id}
}

CreateButtonForSnippet(snippet) {
    global MainGui, ButtonToSnippet

    button := MainGui.AddButton("Hidden", GetButtonLabel(snippet))
    button.SetFont("s10", "Microsoft YaHei UI")
    button.OnEvent("Click", PasteSnippet.Bind(snippet))
    EnableDarkControl(button)
    snippet.Button := button
    ButtonToSnippet[button.Hwnd] := snippet
}

CreateGroupFromDialog(*) {
    global Groups, GroupById, RootItems, CurrentPage, LastClientWidth, LastClientHeight, SortModeActive

    if SortModeActive {
        ShowTemporaryStatus("请先退出排序模式")
        return
    }

    result := InputBox("输入分组名称：", "新建分组", "w360 h140")
    if (result.Result != "OK")
        return
    title := Trim(result.Value)
    if (title = "")
        title := "未命名分组"

    EnsureSafetyBackup()

    id := "group-" FormatTime(, "yyyyMMdd-HHmmss") "-" A_TickCount "-" Random(1000, 9999)
    rows := 2
    cols := 2
    if !GroupSizeFitsPage(rows, cols, LastClientWidth, LastClientHeight) {
        rows := 1
        if !GroupSizeFitsPage(rows, cols, LastClientWidth, LastClientHeight)
            cols := 1
    }

    group := {
        Id: id,
        Title: title,
        ParentId: "",
        Rows: rows,
        Cols: cols,
        Items: [],
        Frame: "",
        TitleControl: "",
        MenuButton: ""
    }
    Groups.Push(group)
    GroupById[id] := group
    RootItems.Push("g:" id)
    CreateGroupControlsFor(group)
    WriteLayout()
    CurrentPage := 999999
    LayoutCards(LastClientWidth, LastClientHeight)
    ShowTemporaryStatus("分组已创建（" rows "×" cols "）")
}

OpenCreateGroup(*) {
    CreateGroupFromDialog()
}

OpenRenameGroup(groupId, *) {
    global GroupById

    if !GroupById.Has(groupId)
        return
    group := GroupById[groupId]
    result := InputBox("输入新的分组名称：", "重命名分组", "w360 h140", group.Title)
    if (result.Result != "OK")
        return
    title := Trim(result.Value)
    if (title = "")
        title := "未命名分组"
    EnsureSafetyBackup()
    group.Title := title
    group.TitleControl.Text := title
    WriteLayout()
    ShowTemporaryStatus("分组已重命名")
}

OpenGroupGridSettings(groupId, *) {
    global GroupById, LastClientWidth, LastClientHeight

    if !GroupById.Has(groupId)
        return
    group := GroupById[groupId]
    rowsResult := InputBox("输入行数（正整数）：", "设置分组网格", "w360 h140", group.Rows)
    if (rowsResult.Result != "OK")
        return
    colsResult := InputBox("输入列数（正整数）：", "设置分组网格", "w360 h140", group.Cols)
    if (colsResult.Result != "OK")
        return

    rows := ParsePositiveInt(rowsResult.Value, 0)
    cols := ParsePositiveInt(colsResult.Value, 0)
    if (!rows || !cols) {
        MsgBox("行数和列数必须是正整数。", "设置分组网格", "Icon!")
        return
    }

    if (rows * cols < CountGroupSnippets(group)) {
        MsgBox("网格容量不足，当前分组有 " CountGroupSnippets(group) " 个文本。", "设置分组网格", "Icon!")
        return
    }

    if !GroupSizeFitsPage(rows, cols, LastClientWidth, LastClientHeight) {
        MsgBox("该网格尺寸超出当前分页可显示范围。", "设置分组网格", "Icon!")
        return
    }

    EnsureSafetyBackup()
    group.Rows := rows
    group.Cols := cols
    WriteLayout()
    LayoutCards(LastClientWidth, LastClientHeight)
    ShowTemporaryStatus("分组网格已更新")
}

CountGroupSnippets(group) {
    count := 0
    for token in group.Items {
        if (SubStr(token, 1, 2) = "s:")
            count += 1
    }
    return count
}

DeleteGroup(groupId, *) {
    global GroupById, Groups, RootItems, SnippetById, GroupControlToGroup, LastClientWidth, LastClientHeight

    if !GroupById.Has(groupId)
        return
    group := GroupById[groupId]
    if (MsgBox("删除分组后，里面的文本会移到未分组区域。`n`n确定删除“" group.Title "”吗？", "删除分组", "YesNo Icon!") != "Yes")
        return

    EnsureSafetyBackup()
    location := FindGroupLocation(groupId)
    if !IsObject(location)
        return
    insertAt := FindTokenIndex(location.Items, "g:" groupId)
    if !insertAt
        insertAt := location.Items.Length + 1
    else
        location.Items.RemoveAt(insertAt)

    moved := []
    for token in group.Items {
        if (SubStr(token, 1, 2) = "s:") {
            id := SubStr(token, 3)
            if SnippetById.Has(id) {
                SnippetById[id].GroupId := location.ParentId
                moved.Push(token)
            }
        } else if (SubStr(token, 1, 2) = "g:" && GroupById.Has(SubStr(token, 3))) {
            childId := SubStr(token, 3)
            GroupById[childId].ParentId := location.ParentId
            moved.Push(token)
        }
    }
    for index, token in moved
        location.Items.InsertAt(Min(insertAt + index - 1, location.Items.Length + 1), token)

    for index, candidate in Groups {
        if (candidate.Id = groupId) {
            Groups.RemoveAt(index)
            break
        }
    }
    GroupById.Delete(groupId)
    GroupControlToGroup.Delete(group.Frame.Hwnd)
    GroupControlToGroup.Delete(group.TitleControl.Hwnd)
    GroupControlToGroup.Delete(group.MenuButton.Hwnd)
    try group.Frame.Destroy()
    try group.TitleControl.Destroy()
    try group.MenuButton.Destroy()
    WriteLayout()
    LayoutCards(LastClientWidth, LastClientHeight)
    destination := location.ParentId = "" ? "未分组" : "父分组"
    ShowTemporaryStatus("分组已删除，内容已移到" destination)
}

OpenAddDialog(*) {
    OpenSnippetDialog()
}

OpenEditDialog(snippet, *) {
    OpenSnippetDialog(snippet)
}

OpenSnippetDialog(snippet := 0) {
    global MainGui

    editing := IsObject(snippet)
    dialog := Gui("+Owner" MainGui.Hwnd " +AlwaysOnTop", editing ? "编辑文本" : "添加文本")
    dialog.BackColor := "202124"
    dialog.SetFont("s10 cE8EAED", "Microsoft YaHei UI")

    titleValue := editing ? snippet.Title : ""
    contentValue := editing ? snippet.Content : ""
    dialog.AddText("x20 y18 w580 h24", "标题（可选）")
    titleEdit := dialog.AddEdit("x20 y46 w580 h34 vTitle", titleValue)
    dialog.AddText("x20 y94 w580 h24", "文本内容")
    contentEdit := dialog.AddEdit("x20 y122 w580 h290 vContent WantTab", contentValue)

    saveButton := dialog.AddButton("x408 y430 w92 h38 Default", "保存")
    cancelButton := dialog.AddButton("x508 y430 w92 h38", "取消")
    saveButton.OnEvent("Click", SaveSnippetFromDialog.Bind(dialog, snippet))
    cancelButton.OnEvent("Click", CloseDialog.Bind(dialog))
    dialog.OnEvent("Close", CloseDialog.Bind(dialog))
    dialog.OnEvent("Escape", CloseDialog.Bind(dialog))

    EnableDarkWindow(dialog)
    for control in [titleEdit, contentEdit]
        EnableDarkEdit(control)
    for control in [saveButton, cancelButton]
        EnableDarkControl(control)
    dialog.Show("w620 h488")
    contentEdit.Focus()
}

SaveSnippetFromDialog(dialog, snippet, *) {
    global Snippets, CurrentPage, DataDir, LastClientWidth, LastClientHeight, SnippetById, RootItems

    values := dialog.Submit(false)
    title := Trim(values.Title)
    content := Trim(values.Content, " `t`r`n")

    if (content = "") {
        MsgBox("请输入要保存的文本内容。", "无法保存", "Icon!")
        return
    }

    editing := IsObject(snippet)
    if editing && title = snippet.Title && content = snippet.Content {
        dialog.Destroy()
        return
    }

    EnsureSafetyBackup()
    if editing {
        id := snippet.Id
    } else {
        id := FormatTime(, "yyyyMMdd-HHmmss") "-" A_TickCount "-" Random(1000, 9999)
    }

    textPath := DataDir "\" id ".txt"
    titlePath := DataDir "\" id ".title"

    try {
        WriteTextAtomic(textPath, content)
        if (title != "")
            WriteTextAtomic(titlePath, title)
        else if FileExist(titlePath)
            FileDelete(titlePath)
    } catch as err {
        MsgBox("保存失败：`n" err.Message, "错误", "Iconx")
        return
    }

    if editing {
        snippet.Title := title
        snippet.Content := content
        snippet.Button.Text := GetButtonLabel(snippet)
        message := "文本已更新"
    } else {
        snippet := {Id: id, Title: title, Content: content, GroupId: "", Button: ""}
        Snippets.Push(snippet)
        SnippetById[id] := snippet
        RootItems.Push("s:" id)
        CreateButtonForSnippet(snippet)
        WriteOrder()
        CurrentPage := 999999
        message := "已保存新文本"
    }

    dialog.Destroy()
    LayoutCards(LastClientWidth, LastClientHeight)
    ShowTemporaryStatus(message)
}

CloseDialog(dialog, *) {
    try dialog.Destroy()
}

HandleContextMenu(wParam, lParam, msg, hwnd) {
    controlHwnd := wParam
    if !controlHwnd
        return

    if ((lParam & 0xFFFFFFFF) = 0xFFFFFFFF)
        MouseGetPos(&x, &y)
    else {
        x := SignedWord(lParam & 0xFFFF)
        y := SignedWord((lParam >> 16) & 0xFFFF)
    }

    ShowControlContextMenu(controlHwnd, x, y)
    return 0
}

HandleRightButtonUp(wParam, lParam, msg, hwnd) {
    global ButtonToSnippet, GroupControlToGroup

    MouseGetPos(&x, &y, &windowHwnd, &controlHwnd)
    if !controlHwnd
        controlHwnd := hwnd
    if !ButtonToSnippet.Has(controlHwnd) && !GroupControlToGroup.Has(controlHwnd)
        return

    ShowControlContextMenu(controlHwnd, x, y)
    return 0
}

ShowControlContextMenu(controlHwnd, x, y) {
    global ButtonToSnippet, GroupControlToGroup, LastContextMenuTick, LastContextMenuHwnd

    if !controlHwnd
        return false
    if (LastContextMenuHwnd = controlHwnd && A_TickCount - LastContextMenuTick < 250)
        return true

    contextMenu := Menu()
    if ButtonToSnippet.Has(controlHwnd) {
        snippet := ButtonToSnippet[controlHwnd]
        contextMenu.Add("编辑(&E)", OpenEditDialog.Bind(snippet))
        contextMenu.Add("删除(&D)", DeleteSnippet.Bind(snippet))
    } else if GroupControlToGroup.Has(controlHwnd) {
        target := GroupControlToGroup[controlHwnd]
        if (target.Type != "group")
            return false
        contextMenu.Add("重命名分组(&R)", OpenRenameGroup.Bind(target.Id))
        contextMenu.Add("设置网格(&G)", OpenGroupGridSettings.Bind(target.Id))
        contextMenu.Add("删除分组(&D)", DeleteGroup.Bind(target.Id))
    } else {
        return false
    }
    LastContextMenuHwnd := controlHwnd
    LastContextMenuTick := A_TickCount
    contextMenu.Show(x, y)
    return true
}

OpenGroupMenu(groupId, *) {
    global GroupById, SortModeActive

    if SortModeActive || !GroupById.Has(groupId)
        return
    MouseGetPos(&x, &y)
    ShowControlContextMenu(GroupById[groupId].MenuButton.Hwnd, x, y)
}

DeleteSnippet(snippet, *) {
    global Snippets, DataDir, TrashDir, ButtonToSnippet, LastClientWidth, LastClientHeight, SnippetById

    displayName := snippet.Title != "" ? snippet.Title : GetOneLinePreview(snippet.Content, 36)
    if (MsgBox("确定删除以下文本吗？`n`n" displayName "`n`n删除后可从应用回收站恢复。", "删除文本", "YesNo Icon!") != "Yes")
        return

    EnsureSafetyBackup()
    index := FindSnippetIndex(snippet.Id)
    if !index
        return

    itemDir := TrashDir "\" snippet.Id
    if DirExist(itemDir)
        itemDir .= "-" FormatTime(, "yyyyMMdd-HHmmss")
    textPath := DataDir "\" snippet.Id ".txt"
    titlePath := DataDir "\" snippet.Id ".title"

    try {
        DirCreate(itemDir)
        FileMove(textPath, itemDir "\content.txt")
        if FileExist(titlePath)
            FileMove(titlePath, itemDir "\title.txt")
        IniWrite(snippet.Id, itemDir "\meta.ini", "Trash", "Id")
        IniWrite(index, itemDir "\meta.ini", "Trash", "OriginalIndex")
        IniWrite(snippet.GroupId, itemDir "\meta.ini", "Trash", "GroupId")
        location := FindSnippetLocation(snippet.Id)
        groupIndex := location ? FindTokenIndex(location.Items, "s:" snippet.Id) : 0
        IniWrite(groupIndex, itemDir "\meta.ini", "Trash", "GroupIndex")
        IniWrite(FormatTime(, "yyyy-MM-dd HH:mm:ss"), itemDir "\meta.ini", "Trash", "DeletedAt")
    } catch as err {
        try {
            if FileExist(itemDir "\content.txt")
                FileMove(itemDir "\content.txt", textPath, 1)
            if FileExist(itemDir "\title.txt")
                FileMove(itemDir "\title.txt", titlePath, 1)
            DirDelete(itemDir, true)
        }
        MsgBox("删除失败：`n" err.Message, "错误", "Iconx")
        return
    }

    RemoveTokenFromLayout("s:" snippet.Id)
    snippet.Button.Visible := false
    ButtonToSnippet.Delete(snippet.Button.Hwnd)
    SnippetById.Delete(snippet.Id)
    Snippets.RemoveAt(index)
    WriteOrder()
    LayoutCards(LastClientWidth, LastClientHeight)
    ShowTemporaryStatus("文本已移入回收站")
}

FindSnippetIndex(id) {
    global Snippets

    for index, snippet in Snippets {
        if (snippet.Id = id)
            return index
    }
    return 0
}

OpenTrashManager(*) {
    global MainGui

    trashGui := Gui("+Owner" MainGui.Hwnd " +AlwaysOnTop", "文本回收站")
    trashGui.BackColor := "202124"
    trashGui.SetFont("s10 cE8EAED", "Microsoft YaHei UI")
    list := trashGui.AddListView("x20 y20 w700 h410 Grid -Multi", ["标题", "删除时间", "正文预览", "ID"])
    list.ModifyCol(1, 180)
    list.ModifyCol(2, 150)
    list.ModifyCol(3, 330)
    list.ModifyCol(4, 0)
    FillTrashList(list)

    restoreButton := trashGui.AddButton("x330 y450 w100 h38 Default", "恢复")
    deleteButton := trashGui.AddButton("x440 y450 w120 h38", "永久删除")
    emptyButton := trashGui.AddButton("x20 y450 w120 h38", "清空回收站")
    closeButton := trashGui.AddButton("x570 y450 w150 h38", "关闭")
    restoreButton.OnEvent("Click", RestoreSelectedTrash.Bind(trashGui, list))
    deleteButton.OnEvent("Click", PermanentlyDeleteTrash.Bind(list))
    emptyButton.OnEvent("Click", EmptyTrash.Bind(list))
    closeButton.OnEvent("Click", CloseDialog.Bind(trashGui))
    list.OnEvent("DoubleClick", RestoreSelectedTrash.Bind(trashGui, list))
    trashGui.OnEvent("Close", CloseDialog.Bind(trashGui))
    trashGui.OnEvent("Escape", CloseDialog.Bind(trashGui))

    EnableDarkWindow(trashGui)
    for control in [list, restoreButton, deleteButton, emptyButton, closeButton]
        EnableDarkControl(control)
    trashGui.Show("w740 h510")
}

FillTrashList(list) {
    global TrashDir

    list.Delete()
    Loop Files, TrashDir "\*", "D" {
        itemDir := A_LoopFileFullPath
        contentPath := itemDir "\content.txt"
        if !FileExist(contentPath)
            continue

        try content := FileRead(contentPath, "UTF-8")
        catch
            content := ""
        try title := FileRead(itemDir "\title.txt", "UTF-8")
        catch
            title := ""
        try id := IniRead(itemDir "\meta.ini", "Trash", "Id", A_LoopFileName)
        catch
            id := A_LoopFileName
        try deletedAt := IniRead(itemDir "\meta.ini", "Trash", "DeletedAt", "")
        catch
            deletedAt := ""

        label := Trim(title) != "" ? Trim(title) : GetOneLinePreview(content, 24)
        list.Add(, label, deletedAt, GetOneLinePreview(content, 54), id)
    }
}

GetSelectedTrash(list) {
    global TrashDir

    row := list.GetNext()
    if !row
        return 0
    id := list.GetText(row, 4)

    Loop Files, TrashDir "\*", "D" {
        itemDir := A_LoopFileFullPath
        try storedId := IniRead(itemDir "\meta.ini", "Trash", "Id", A_LoopFileName)
        catch
            storedId := A_LoopFileName
        if (storedId = id)
            return {Row: row, Id: id, Dir: itemDir}
    }
    return 0
}

RestoreSelectedTrash(trashGui, list, *) {
    global Snippets, DataDir, LastClientWidth, LastClientHeight, SnippetById, RootItems, GroupById

    selected := GetSelectedTrash(list)
    if !IsObject(selected) {
        MsgBox("请先选择要恢复的文本。", "回收站", "Icon!")
        return
    }

    itemDir := selected.Dir
    id := selected.Id
    if FileExist(DataDir "\" id ".txt")
        id := FormatTime(, "yyyyMMdd-HHmmss") "-" A_TickCount "-" Random(1000, 9999)

    try content := FileRead(itemDir "\content.txt", "UTF-8")
    catch as err {
        MsgBox("恢复失败：`n" err.Message, "错误", "Iconx")
        return
    }
    try title := FileRead(itemDir "\title.txt", "UTF-8")
    catch
        title := ""
    try originalIndexValue := IniRead(itemDir "\meta.ini", "Trash", "OriginalIndex", "")
    catch
        originalIndexValue := ""
    originalIndex := ParsePositiveInt(originalIndexValue, Snippets.Length + 1)
    try originalGroupId := IniRead(itemDir "\meta.ini", "Trash", "GroupId", "")
    catch
        originalGroupId := ""
    try originalGroupIndexValue := IniRead(itemDir "\meta.ini", "Trash", "GroupIndex", "")
    catch
        originalGroupIndexValue := ""
    originalGroupIndex := ParseNonNegativeInt(originalGroupIndexValue, 0)

    EnsureSafetyBackup()

    try {
        FileMove(itemDir "\content.txt", DataDir "\" id ".txt")
        if FileExist(itemDir "\title.txt")
            FileMove(itemDir "\title.txt", DataDir "\" id ".title")
        DirDelete(itemDir, true)
    } catch as err {
        MsgBox("恢复失败：`n" err.Message, "错误", "Iconx")
        return
    }

    snippet := {Id: id, Title: Trim(title), Content: content, GroupId: "", Button: ""}
    insertAt := Max(1, Min(originalIndex, Snippets.Length + 1))
    Snippets.InsertAt(insertAt, snippet)
    SnippetById[id] := snippet
    if (originalGroupId != "" && GroupById.Has(originalGroupId) && CountGroupSnippets(GroupById[originalGroupId]) < GroupById[originalGroupId].Rows * GroupById[originalGroupId].Cols) {
        targetGroup := GroupById[originalGroupId]
        insertAt := Max(1, Min(originalGroupIndex, targetGroup.Items.Length + 1))
        targetGroup.Items.InsertAt(insertAt, "s:" id)
        snippet.GroupId := originalGroupId
    } else {
        rootInsertAt := (originalGroupId = "" && originalGroupIndex > 0) ? Max(1, Min(originalGroupIndex, RootItems.Length + 1)) : RootItems.Length + 1
        RootItems.InsertAt(rootInsertAt, "s:" id)
    }
    CreateButtonForSnippet(snippet)
    WriteOrder()
    FillTrashList(list)
    LayoutCards(LastClientWidth, LastClientHeight)
    ShowTemporaryStatus("已从回收站恢复文本")
}

PermanentlyDeleteTrash(list, *) {
    selected := GetSelectedTrash(list)
    if !IsObject(selected) {
        MsgBox("请先选择要永久删除的文本。", "回收站", "Icon!")
        return
    }

    if (MsgBox("永久删除后无法从应用回收站恢复，确定继续吗？", "永久删除", "YesNo Icon!") != "Yes")
        return

    try DirDelete(selected.Dir, true)
    catch as err {
        MsgBox("永久删除失败：`n" err.Message, "错误", "Iconx")
        return
    }
    FillTrashList(list)
}

EmptyTrash(list, *) {
    global TrashDir

    hasItems := false
    Loop Files, TrashDir "\*", "D" {
        hasItems := true
        break
    }
    if !hasItems
        return

    if (MsgBox("确定永久清空应用回收站吗？此操作无法撤销。", "清空回收站", "YesNo Icon!") != "Yes")
        return

    Loop Files, TrashDir "\*", "D"
        try DirDelete(A_LoopFileFullPath, true)
    FillTrashList(list)
}

ToggleSortMode(*) {
    global SortModeActive, SortButton, SortOrderDirty, RootItems, Groups

    if SortModeActive {
        if SortOrderDirty && !PersistSortOrder()
            return

        SortModeActive := false
        SortButton.Text := "排序"
        ShowTemporaryStatus("已退出排序模式")
        return
    }

    if (CountLayoutItems() < 2) {
        ShowTemporaryStatus("至少需要两个文本段或分组才能排序")
        return
    }

    SortModeActive := true
    SortOrderDirty := false
    SortButton.Text := "完成排序"
    ShowTemporaryStatus("排序模式：直接拖动文本按钮调整顺序")
}

CountLayoutItems() {
    global RootItems, Groups

    count := 0
    for token in RootItems
        if (SubStr(token, 1, 2) = "s:" || SubStr(token, 1, 2) = "g:")
            count += 1
    for group in Groups
        for token in group.Items
            if (SubStr(token, 1, 2) = "s:" || SubStr(token, 1, 2) = "g:")
                count += 1
    return count
}

SortMouseDown(wParam, lParam, msg, hwnd) {
    global SortModeActive, SortDragFrom, SortDragTo, SortDragMoved, SortDragType, SortDragId, SortDropMessage, SortLastTargetKey
    global ButtonToSnippet, GroupControlToGroup, MainGui

    if !SortModeActive || SortDragFrom
        return

    if ButtonToSnippet.Has(hwnd) {
        snippet := ButtonToSnippet[hwnd]
        SortDragType := "snippet"
        SortDragId := snippet.Id
    } else if GroupControlToGroup.Has(hwnd) {
        target := GroupControlToGroup[hwnd]
        if (target.Type != "group")
            return
        SortDragType := "group"
        SortDragId := target.Id
    } else {
        return
    }

    SortDragFrom := 1
    SortDragTo := 1
    SortDragMoved := false
    SortDropMessage := ""
    SortLastTargetKey := ""
    DllCall("SetCapture", "Ptr", MainGui.Hwnd)
    return 0
}

SortMouseMove(wParam, lParam, msg, hwnd) {
    global SortModeActive, SortDragFrom, SortDragTo, SortDragMoved, SortOrderDirty, SortDragType, SortDragId, SortLastTargetKey
    global LastClientWidth, LastClientHeight

    if !SortModeActive || !SortDragFrom
        return

    MouseGetPos(&screenX, &screenY)
    target := GetDropTarget(screenX, screenY)
    if !IsObject(target)
        return 0
    targetKey := GetDropTargetKey(target)
    if (targetKey = SortLastTargetKey)
        return 0
    SortLastTargetKey := targetKey

    if (SortDragType = "snippet")
        moved := MoveSnippetToDropTarget(SortDragId, target)
    else
        moved := MoveGroupToDropTarget(SortDragId, target)
    if moved {
        SortDragMoved := true
        SortOrderDirty := true
        LayoutCards(LastClientWidth, LastClientHeight)
    }
    return 0
}

SortMouseUp(wParam, lParam, msg, hwnd) {
    global SortDragFrom, SortDragTo, SortDragMoved, SortDragType, SortDragId, SortDropMessage, SortLastTargetKey

    if !SortDragFrom
        return

    DllCall("ReleaseCapture")
    moved := SortDragMoved
    SortDragFrom := 0
    SortDragTo := 0
    SortDragMoved := false
    SortDragType := ""
    SortDragId := ""
    SortLastTargetKey := ""

    if moved {
        if PersistSortOrder()
            ShowTemporaryStatus("文本顺序已保存")
        else
            ShowTemporaryStatus("顺序暂未保存，请重试")
    } else if (SortDropMessage != "") {
        ShowTemporaryStatus(SortDropMessage)
    }
    SortDropMessage := ""
    return 0
}

GetDropTarget(screenX, screenY) {
    global LayoutRegions

    index := LayoutRegions.Length
    while (index >= 1) {
        region := LayoutRegions[index]
        if (screenX >= region.X && screenX < region.X + region.Width && screenY >= region.Y && screenY < region.Y + region.Height)
            return region
        index -= 1
    }
    return 0
}

GetDropTargetKey(target) {
    id := target.HasOwnProp("Id") ? target.Id : ""
    groupId := target.HasOwnProp("GroupId") ? target.GroupId : ""
    return target.Type "|" id "|" groupId
}

MoveSnippetToDropTarget(id, target) {
    global SnippetById, GroupById, RootItems, Groups, SortDropMessage

    if !SnippetById.Has(id)
        return false
    snippet := SnippetById[id]
    token := "s:" id
    if (target.Type = "snippet" && target.Id = id)
        return false
    if (target.Type = "group") {
        if !GroupById.Has(target.Id)
            return false
        group := GroupById[target.Id]
        if (snippet.GroupId = group.Id)
            return false
        if CountGroupSnippets(group) >= group.Rows * group.Cols {
            SortDropMessage := "目标分组已满，无法放入"
            return false
        }
        InsertSnippetIntoGroup(snippet, group)
    } else if (target.Type = "root") {
        if (snippet.GroupId = "")
            return false
        InsertSnippetIntoRoot(snippet)
    } else if (target.Type = "snippet") {
        if (target.GroupId != "" && GroupById.Has(target.GroupId)) {
            group := GroupById[target.GroupId]
            if (snippet.GroupId != group.Id && CountGroupSnippets(group) >= group.Rows * group.Cols) {
                SortDropMessage := "目标分组已满，无法放入"
                return false
            }
            targetToken := "s:" target.Id
            if (snippet.GroupId = group.Id)
                moved := MoveTokenRelative(group.Items, token, targetToken)
            else {
                RemoveTokenFromLayout(token)
                index := FindTokenIndex(group.Items, targetToken)
                if !index
                    return false
                group.Items.InsertAt(index, token)
                moved := true
            }
            if !moved
                return false
            snippet.GroupId := group.Id
        } else {
            if (snippet.GroupId = "")
                moved := MoveTokenRelative(RootItems, token, "s:" target.Id)
            else {
                RemoveTokenFromLayout(token)
                index := FindTokenIndex(RootItems, "s:" target.Id)
                if !index
                    return false
                RootItems.InsertAt(index, token)
                moved := true
            }
            if !moved
                return false
            snippet.GroupId := ""
        }
    }
    SortDropMessage := ""
    return true
}

MoveTokenRelative(items, token, targetToken) {
    sourceIndex := FindTokenIndex(items, token)
    targetIndex := FindTokenIndex(items, targetToken)
    if (!sourceIndex || !targetIndex || sourceIndex = targetIndex)
        return false

    items.RemoveAt(sourceIndex)
    insertAt := targetIndex - (sourceIndex < targetIndex ? 1 : 0)
    items.InsertAt(insertAt, token)
    return true
}

MoveGroupToDropTarget(id, target) {
    global GroupById, RootItems, SortDropMessage

    if (target.Type != "group" && target.Type != "root" && target.Type != "snippet")
        return false
    if !GroupById.Has(id)
        return false
    if (target.Type = "group") {
        if (target.Id = id || !GroupById.Has(target.Id))
            return false
        ; A group drop target means sibling reordering, never nesting.
        if (GroupById[target.Id].ParentId != "")
            return false
    }
    if (target.Type = "snippet" && target.GroupId != "")
        return false
    token := "g:" id
    index := FindTokenIndex(RootItems, token)
    if !index
        return false
    if (target.Type = "snippet" && target.GroupId = "")
        moved := MoveTokenRelative(RootItems, token, "s:" target.Id)
    else if (target.Type = "group")
        moved := MoveTokenRelative(RootItems, token, "g:" target.Id)
    else {
        RootItems.RemoveAt(index)
        RootItems.Push(token)
        moved := true
    }
    if !moved
        return false
    SortDropMessage := ""
    return true
}

PersistSortOrder() {
    global SortOrderDirty

    EnsureSafetyBackup()
    try WriteOrder()
    catch as err {
        MsgBox("保存排序失败：`n" err.Message, "错误", "Iconx")
        return false
    }

    SortOrderDirty := false
    return true
}

SignedWord(value) {
    value &= 0xFFFF
    return value >= 0x8000 ? value - 0x10000 : value
}

GetButtonLabel(snippet) {
    if (snippet.Title != "")
        return snippet.Title

    label := StrReplace(snippet.Content, "`r", "")
    label := StrReplace(label, "`t", "    ")
    if (StrLen(label) > 160)
        label := SubStr(label, 1, 157) "..."
    return label
}

GetOneLinePreview(text, maxLength := 60) {
    preview := RegExReplace(text, "\s+", " ")
    preview := Trim(preview)
    if (StrLen(preview) > maxLength)
        preview := SubStr(preview, 1, maxLength - 3) "..."
    return preview
}

PasteSnippet(snippet, *) {
    global LastTargetHwnd, MainGui, SortModeActive

    if SortModeActive
        return

    A_Clipboard := snippet.Content
    if !ClipWait(0.8) {
        ShowTemporaryStatus("无法写入剪贴板，请重试")
        return
    }

    targetHwnd := LastTargetHwnd
    if !targetHwnd || !WinExist("ahk_id " targetHwnd) {
        ShowTemporaryStatus("未找到可粘贴的活动窗口，正文已复制")
        return
    }

    try {
        WinActivate("ahk_id " targetHwnd)
        if !WinWaitActive("ahk_id " targetHwnd, , 1) {
            ShowTemporaryStatus("无法激活目标窗口，正文已复制")
            return
        }
        Send("^v")
        MainGui.Hide()
    } catch {
        ShowTemporaryStatus("自动粘贴失败，正文已复制")
    }
}

TrackActiveWindow(*) {
    global LastTargetHwnd

    hwnd := WinExist("A")
    if !hwnd
        return

    try activePid := WinGetPID("ahk_id " hwnd)
    catch
        return

    if (activePid != ProcessExist())
        LastTargetHwnd := hwnd
}

EnableDarkWindow(guiObj) {
    darkMode := 1
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "Int", 20, "Int*", darkMode, "Int", 4)
    catch
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "Int", 19, "Int*", darkMode, "Int", 4)
}

EnableDarkControl(control) {
    try DllCall("uxtheme\SetWindowTheme", "Ptr", control.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
}

EnableDarkEdit(control) {
    EnableDarkControl(control)
    try control.BackColor := "2B2D31"
    try control.SetFont("s10 cE8EAED", "Microsoft YaHei UI")
    RegisterDarkEdit(control)
}

RegisterDarkEdit(control) {
    global DarkEditHandles, DarkEditBrush

    DarkEditHandles[control.Hwnd] := true
    if !DarkEditBrush
        DarkEditBrush := DllCall("gdi32\CreateSolidBrush", "UInt", 0x00312D2B, "Ptr")
}

HandleEditControlColor(wParam, lParam, msg, hwnd) {
    global DarkEditHandles, DarkEditBrush

    if !DarkEditHandles.Has(lParam)
        return

    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0x00EDEAE8)
    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", 0x00312D2B)
    return DarkEditBrush
}

ChangePage(offset, *) {
    global CurrentPage, LastClientWidth, LastClientHeight

    CurrentPage += offset
    LayoutCards(LastClientWidth, LastClientHeight)
}

MainGuiSize(guiObj, minMax, width, height) {
    global LastClientWidth, LastClientHeight

    if (minMax = -1)
        return

    LastClientWidth := width
    LastClientHeight := height
    LayoutCards(width, height)
}

LayoutCards(width, height) {
    global Snippets, CurrentPage, AddButton, NewGroupButton, SortButton, TrashButton, SettingsButton
    global PrevButton, NextButton, StatusText, EmptyText, SortModeActive
    global RootItems, GroupById, Groups, UngroupedPanel, UngroupedTitle, LayoutRegions, MainGui

    margin := 20
    gap := 16
    top := 82
    bottom := 20
    targetWidth := 280
    cardHeight := 108
    columns := Max(1, Floor((width - margin * 2 + gap) / (targetWidth + gap)))
    cardWidth := Floor((width - margin * 2 - gap * (columns - 1)) / columns)
    availableHeight := Max(120, height - top - bottom)

    AddButton.Move(margin, 18, 140, 42)
    NewGroupButton.Move(170, 22, 96, 34)
    SortButton.Move(274, 22, 88, 34)
    TrashButton.Move(370, 22, 88, 34)
    SettingsButton.Move(466, 22, 100, 34)
    NextButton.Move(width - margin - 72, 22, 72, 34)
    PrevButton.Move(width - margin - 152, 22, 72, 34)
    StatusText.Move(574, 28, Max(100, width - 766), 28)

    for snippet in Snippets
        snippet.Button.Visible := false
    for group in Groups {
        group.Frame.Visible := false
        group.TitleControl.Visible := false
        group.MenuButton.Visible := false
    }
    UngroupedPanel.Visible := false
    UngroupedTitle.Visible := false
    LayoutRegions := []

    blocks := BuildLayoutBlocks(width, cardWidth, cardHeight, gap, availableHeight)
    pages := BuildLayoutPages(blocks, availableHeight, gap, width - margin * 2)
    totalPages := Max(1, pages.Length)
    CurrentPage := Max(1, Min(CurrentPage, totalPages))
    PrevButton.Enabled := CurrentPage > 1
    NextButton.Enabled := CurrentPage < totalPages
    PrevButton.Visible := totalPages > 1
    NextButton.Visible := totalPages > 1

    pageBlocks := pages[CurrentPage]
    WinGetClientPos(&mainX, &mainY, , , "ahk_id " MainGui.Hwnd)
    cursorY := top
    for row in pageBlocks {
        cursorX := margin
        for block in row.Items {
            blockWidth := block.HasOwnProp("Width") ? block.Width : width - margin * 2
            blockWidth := Min(blockWidth, width - margin * 2)
        if (block.Type = "root") {
            rootHeight := block.Height
            UngroupedPanel.Move(cursorX, cursorY, blockWidth, rootHeight)
            UngroupedTitle.Move(cursorX + 12, cursorY + 6, blockWidth - 24, 24)
            UngroupedPanel.Visible := true
            UngroupedTitle.Visible := true
            LayoutRegions.Push({Type: "root", Id: "", X: mainX + cursorX, Y: mainY + cursorY, Width: blockWidth, Height: rootHeight})
            if !block.DropOnly
                LayoutRootItems(block.Tokens, cursorX + 12, cursorY + 34, blockWidth - 24, cardWidth, cardHeight, gap, mainX, mainY)
        } else if (block.Type = "group" && GroupById.Has(block.Id)) {
            group := GroupById[block.Id]
            groupWidth := blockWidth
            group.Frame.Move(cursorX, cursorY, groupWidth, block.Height)
            group.TitleControl.Move(cursorX + 12, cursorY + 6, Max(60, groupWidth - 82), 24)
            group.MenuButton.Move(cursorX + groupWidth - 58, cursorY + 5, 46, 26)
            group.Frame.Visible := true
            group.TitleControl.Visible := true
            group.MenuButton.Visible := true
            LayoutRegions.Push({Type: "group", Id: group.Id, X: mainX + cursorX, Y: mainY + cursorY, Width: groupWidth, Height: block.Height})
            LayoutGroupItems(group, cursorX + 12, cursorY + 34, groupWidth - 24, cardWidth, cardHeight, gap, mainX, mainY)
        }
            cursorX += blockWidth + gap
        }
        cursorY += row.Height + gap
    }

    EmptyText.Visible := (Snippets.Length = 0 && Groups.Length = 0)
    if EmptyText.Visible
        EmptyText.Move(margin, top + 40, width - margin * 2, 80)

    if SortModeActive
        StatusText.Text := "排序模式 · 拖动文本或分组调整位置"
    else if (RootItems.Length = 0)
        StatusText.Text := "尚未保存文本"
    else if (totalPages = 1)
        StatusText.Text := Snippets.Length " 个文本段 · 左键粘贴，右键管理"
    else
        StatusText.Text := Snippets.Length " 个文本段 · 第 " CurrentPage "/" totalPages " 页"
}

BuildLayoutBlocks(width, cardWidth, cardHeight, gap, availableHeight) {
    global RootItems, GroupById

    blocks := []
    rootTokens := []
    rootCount := 0
    columns := Max(1, Floor((width - 64 + gap) / (cardWidth + gap)))
    maxRootRows := Max(1, Floor((availableHeight - 34 - 24 - 16 + gap) / (cardHeight + gap)))
    maxRootItems := Max(1, columns * maxRootRows)
    FlushRootBlocks(blocks, rootTokens, columns, maxRootItems, cardHeight, gap)
    rootTokens := []
    for token in RootItems {
        if (SubStr(token, 1, 2) = "s:") {
            rootCount += 1
            rootTokens.Push(token)
            if (rootTokens.Length >= maxRootItems) {
                FlushRootBlocks(blocks, rootTokens, columns, maxRootItems, cardHeight, gap)
                rootTokens := []
            }
        } else if (SubStr(token, 1, 2) = "g:" && GroupById.Has(SubStr(token, 3))) {
            FlushRootBlocks(blocks, rootTokens, columns, maxRootItems, cardHeight, gap)
            rootTokens := []
            group := GroupById[SubStr(token, 3)]
            blocks.Push({
                Type: "group",
                Id: group.Id,
                Width: GetGroupBlockWidth(group, cardWidth, gap, width - 40),
                Height: GetGroupBlockHeight(group, cardHeight, gap)
            })
        }
    }
    FlushRootBlocks(blocks, rootTokens, columns, maxRootItems, cardHeight, gap)
    if !rootCount
        blocks.InsertAt(1, {Type: "root", Id: "", Tokens: [], DropOnly: true, Height: 58})
    return blocks
}

FlushRootBlocks(blocks, tokens, columns, maxItems, cardHeight, gap) {
    if !tokens.Length
        return
    rows := Max(1, Ceil(tokens.Length / columns))
    copy := []
    for token in tokens
        copy.Push(token)
    blocks.Push({Type: "root", Id: "", Tokens: copy, DropOnly: false, Height: 34 + 24 + rows * cardHeight + (rows - 1) * gap + 16})
}

GetGroupBlockWidth(group, cardWidth, gap, availableWidth := 0) {
    desiredWidth := 24 + group.Cols * cardWidth + (group.Cols - 1) * gap
    return availableWidth > 0 ? Min(availableWidth, desiredWidth) : desiredWidth
}

GetGroupBlockHeight(group, cardHeight, gap) {
    return 34 + 24 + group.Rows * cardHeight + (group.Rows - 1) * gap + 16
}

BuildLayoutPages(blocks, availableHeight, gap, availableWidth) {
    rows := []
    rowItems := []
    rowWidth := 0
    rowHeight := 0

    for block in blocks {
        blockWidth := block.HasOwnProp("Width") ? block.Width : availableWidth
        blockWidth := Min(blockWidth, availableWidth)
        requiredWidth := rowItems.Length ? rowWidth + gap + blockWidth : blockWidth
        if (rowItems.Length && requiredWidth > availableWidth) {
            rows.Push({Items: rowItems, Width: rowWidth, Height: rowHeight})
            rowItems := []
            rowWidth := 0
            rowHeight := 0
        }

        rowItems.Push(block)
        rowWidth := rowItems.Length = 1 ? blockWidth : rowWidth + gap + blockWidth
        rowHeight := Max(rowHeight, block.Height)
    }
    if rowItems.Length
        rows.Push({Items: rowItems, Width: rowWidth, Height: rowHeight})

    pages := [[]]
    used := 0
    for row in rows {
        if (used > 0 && used + gap + row.Height > availableHeight) {
            pages.Push([])
            used := 0
        }
        pages[pages.Length].Push(row)
        used += row.Height + gap
    }
    return pages
}

LayoutRootItems(tokens, x, y, width, cardWidth, cardHeight, gap, mainX, mainY) {
    global SnippetById
    columns := Max(1, Floor((width + gap) / (cardWidth + gap)))
    cellWidth := Max(80, Floor((width - (columns - 1) * gap) / columns))
    for tokenIndex, token in tokens {
        snippet := SnippetById[SubStr(token, 3)]
        slot := tokenIndex - 1
        row := Floor(slot / columns)
        column := Mod(slot, columns)
        px := x + column * (cellWidth + gap)
        py := y + row * (cardHeight + gap)
        snippet.Button.Visible := true
        snippet.Button.Move(px, py, cellWidth, cardHeight)
        LayoutRegions.Push({Type: "snippet", Id: snippet.Id, GroupId: "", X: mainX + px, Y: mainY + py, Width: cellWidth, Height: cardHeight})
    }
}

LayoutGroupItems(group, x, y, width, cardWidth, cardHeight, gap, mainX, mainY) {
    global SnippetById

    cellWidth := Max(80, Floor((width - (group.Cols - 1) * gap) / group.Cols))
    visibleIndex := 0
    for tokenIndex, token in group.Items {
        if (SubStr(token, 1, 2) != "s:" || !SnippetById.Has(SubStr(token, 3)))
            continue
        snippet := SnippetById[SubStr(token, 3)]
        visibleIndex += 1
        slot := visibleIndex - 1
        row := Floor(slot / group.Cols)
        column := Mod(slot, group.Cols)
        px := x + column * (cellWidth + gap)
        py := y + row * (cardHeight + gap)
        snippet.Button.Visible := true
        snippet.Button.Move(px, py, cellWidth, cardHeight)
        LayoutRegions.Push({Type: "snippet", Id: snippet.Id, GroupId: group.Id, X: mainX + px, Y: mainY + py, Width: cellWidth, Height: cardHeight})
    }
}

GroupSizeFitsPage(rows, cols, width, height) {
    if (rows < 1 || cols < 1)
        return false
    margin := 20
    top := 82
    bottom := 20
    gap := 16
    targetWidth := 280
    cardHeight := 108
    columns := Max(1, Floor((width - margin * 2 + gap) / (targetWidth + gap)))
    cardWidth := Floor((width - margin * 2 - gap * (columns - 1)) / columns)
    desiredWidth := 24 + cols * cardWidth + (cols - 1) * gap
    groupWidth := Min(width - margin * 2, desiredWidth)
    groupHeight := 34 + 24 + rows * cardHeight + (rows - 1) * gap + 16
    innerWidth := groupWidth - 24
    minimumGridWidth := cols * 80 + (cols - 1) * gap
    availableHeight := Max(120, height - top - bottom)
    return groupWidth >= 160 && groupWidth <= width - margin * 2 && minimumGridWidth <= innerWidth && groupHeight <= availableHeight
}

ShowTemporaryStatus(message) {
    global StatusText

    StatusText.Text := message
    SetTimer(RestoreStatus, -1800)
}

RestoreStatus(*) {
    global LastClientWidth, LastClientHeight

    LayoutCards(LastClientWidth, LastClientHeight)
}
