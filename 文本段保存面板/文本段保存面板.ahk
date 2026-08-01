#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

global MainGui := ""
global AddButton := ""
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
global TrashDir := ""
global BackupDir := ""
global SafetyBackupMade := false
global SortModeActive := false
global SortDragFrom := 0
global SortDragTo := 0
global SortDragMoved := false
global SortOrderDirty := false
global DarkEditHandles := Map()
global DarkEditBrush := 0

Initialize()

!+v::ToggleMainGui()

Initialize() {
    global MainGui, AddButton, SortButton, TrashButton, SettingsButton, PrevButton, NextButton
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
    SortButton := MainGui.AddButton("x170 y22 w88 h34", "排序")
    TrashButton := MainGui.AddButton("x268 y22 w88 h34", "回收站")
    SettingsButton := MainGui.AddButton("x366 y22 w88 h34", "存储位置")
    AddButton.SetFont("s11 Bold", "Microsoft YaHei UI")
    AddButton.OnEvent("Click", OpenAddDialog)
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

    CreateSnippetButtons()
    EnableDarkWindow(MainGui)
    for control in [AddButton, SortButton, TrashButton, SettingsButton, PrevButton, NextButton]
        EnableDarkControl(control)

    MainGui.OnEvent("Size", MainGuiSize)
    MainGui.OnEvent("Close", HideMainGui)
    MainGui.OnEvent("Escape", HideMainGui)

    ConfigureTrayMenu()
    OnMessage(0x007B, HandleContextMenu)
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
    global StorageRoot, DataDir, OrderPath, TrashDir, BackupDir

    StorageRoot := NormalizeStorageRoot(root)
    DataDir := StorageRoot "\文本段保存面板数据"
    OrderPath := DataDir "\order.txt"
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
    global Snippets, DataDir, OrderPath

    discovered := []
    byId := Map()

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
            Button: ""
        }
        discovered.Push(snippet)
        byId[id] := snippet
    }

    Snippets := []
    seen := Map()
    if FileExist(OrderPath) {
        try orderText := FileRead(OrderPath, "UTF-8")
        catch
            orderText := ""

        for line in StrSplit(StrReplace(orderText, "`r", ""), "`n") {
            id := Trim(line)
            if (id != "" && byId.Has(id) && !seen.Has(id)) {
                Snippets.Push(byId[id])
                seen[id] := true
            }
        }
    }

    for snippet in discovered {
        if !seen.Has(snippet.Id) {
            Snippets.Push(snippet)
            seen[snippet.Id] := true
        }
    }
}

WriteOrder() {
    global Snippets, OrderPath

    text := ""
    for snippet in Snippets
        text .= snippet.Id "`n"
    WriteTextAtomic(OrderPath, RTrim(text, "`n"))
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

CreateButtonForSnippet(snippet) {
    global MainGui, ButtonToSnippet

    button := MainGui.AddButton("Hidden", GetButtonLabel(snippet))
    button.SetFont("s10", "Microsoft YaHei UI")
    button.OnEvent("Click", PasteSnippet.Bind(snippet))
    EnableDarkControl(button)
    snippet.Button := button
    ButtonToSnippet[button.Hwnd] := snippet
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
    global Snippets, CurrentPage, DataDir, LastClientWidth, LastClientHeight

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

    if editing {
        EnsureSafetyBackup()
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
        snippet := {Id: id, Title: title, Content: content, Button: ""}
        Snippets.Push(snippet)
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
    global ButtonToSnippet

    controlHwnd := wParam
    if !controlHwnd || !ButtonToSnippet.Has(controlHwnd)
        return

    if ((lParam & 0xFFFFFFFF) = 0xFFFFFFFF)
        MouseGetPos(&x, &y)
    else {
        x := SignedWord(lParam & 0xFFFF)
        y := SignedWord((lParam >> 16) & 0xFFFF)
    }

    snippet := ButtonToSnippet[controlHwnd]
    contextMenu := Menu()
    contextMenu.Add("编辑(&E)", OpenEditDialog.Bind(snippet))
    contextMenu.Add("删除(&D)", DeleteSnippet.Bind(snippet))
    contextMenu.Show(x, y)
    return 0
}

DeleteSnippet(snippet, *) {
    global Snippets, DataDir, TrashDir, ButtonToSnippet, LastClientWidth, LastClientHeight

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

    snippet.Button.Visible := false
    ButtonToSnippet.Delete(snippet.Button.Hwnd)
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
    global Snippets, DataDir, LastClientWidth, LastClientHeight

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
    try originalIndex := IniRead(itemDir "\meta.ini", "Trash", "OriginalIndex", Snippets.Length + 1) + 0
    catch
        originalIndex := Snippets.Length + 1

    try {
        FileMove(itemDir "\content.txt", DataDir "\" id ".txt")
        if FileExist(itemDir "\title.txt")
            FileMove(itemDir "\title.txt", DataDir "\" id ".title")
        DirDelete(itemDir, true)
    } catch as err {
        MsgBox("恢复失败：`n" err.Message, "错误", "Iconx")
        return
    }

    snippet := {Id: id, Title: Trim(title), Content: content, Button: ""}
    insertAt := Max(1, Min(originalIndex, Snippets.Length + 1))
    Snippets.InsertAt(insertAt, snippet)
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
    global SortModeActive, SortButton, SortOrderDirty, Snippets

    if SortModeActive {
        if SortOrderDirty && !PersistSortOrder()
            return

        SortModeActive := false
        SortButton.Text := "排序"
        ShowTemporaryStatus("已退出排序模式")
        return
    }

    if (Snippets.Length < 2) {
        ShowTemporaryStatus("至少需要两个文本段才能排序")
        return
    }

    SortModeActive := true
    SortOrderDirty := false
    SortButton.Text := "完成排序"
    ShowTemporaryStatus("排序模式：直接拖动文本按钮调整顺序")
}

SortMouseDown(wParam, lParam, msg, hwnd) {
    global SortModeActive, SortDragFrom, SortDragTo, SortDragMoved, ButtonToSnippet, MainGui

    if !SortModeActive || SortDragFrom || !ButtonToSnippet.Has(hwnd)
        return

    snippet := ButtonToSnippet[hwnd]
    index := FindSnippetIndex(snippet.Id)
    if !index
        return

    SortDragFrom := index
    SortDragTo := index
    SortDragMoved := false
    DllCall("SetCapture", "Ptr", MainGui.Hwnd)
    return 0
}

SortMouseMove(wParam, lParam, msg, hwnd) {
    global SortModeActive, SortDragFrom, SortDragTo, SortDragMoved, SortOrderDirty
    global Snippets, LastClientWidth, LastClientHeight

    if !SortModeActive || !SortDragFrom
        return

    MouseGetPos(&screenX, &screenY)
    target := GetSortTargetIndex(screenX, screenY)
    if !target || target = SortDragTo
        return 0

    snippet := Snippets.RemoveAt(SortDragFrom)
    Snippets.InsertAt(target, snippet)
    SortDragFrom := target
    SortDragTo := target
    SortDragMoved := true
    SortOrderDirty := true
    LayoutCards(LastClientWidth, LastClientHeight)
    return 0
}

SortMouseUp(wParam, lParam, msg, hwnd) {
    global SortDragFrom, SortDragTo, SortDragMoved

    if !SortDragFrom
        return

    DllCall("ReleaseCapture")
    moved := SortDragMoved
    SortDragFrom := 0
    SortDragTo := 0
    SortDragMoved := false

    if moved {
        if PersistSortOrder()
            ShowTemporaryStatus("文本顺序已保存")
        else
            ShowTemporaryStatus("顺序暂未保存，请重试")
    }
    return 0
}

GetSortTargetIndex(screenX, screenY) {
    global Snippets

    visible := []
    for index, snippet in Snippets {
        if !snippet.Button.Visible
            continue

        try WinGetPos(&x, &y, &width, &height, "ahk_id " snippet.Button.Hwnd)
        catch
            continue
        if (width <= 0 || height <= 0)
            continue

        item := {
            Index: index,
            X: x,
            Y: y,
            Width: width,
            Height: height,
            CenterX: x + width / 2,
            CenterY: y + height / 2
        }
        visible.Push(item)

        if (screenX >= x && screenX < x + width && screenY >= y && screenY < y + height)
            return index
    }

    if !visible.Length
        return 0

    nearest := visible[1]
    nearestDistance := (screenX - nearest.CenterX) ** 2 + (screenY - nearest.CenterY) ** 2
    for index, item in visible {
        if (index = 1)
            continue
        distance := (screenX - item.CenterX) ** 2 + (screenY - item.CenterY) ** 2
        if (distance < nearestDistance) {
            nearest := item
            nearestDistance := distance
        }
    }
    return nearest.Index
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
    global Snippets, CurrentPage, AddButton, SortButton, TrashButton, SettingsButton
    global PrevButton, NextButton, StatusText, EmptyText, SortModeActive

    margin := 20
    gap := 16
    top := 82
    bottom := 20
    targetWidth := 280
    cardHeight := 108

    columns := Max(1, Floor((width - margin * 2 + gap) / (targetWidth + gap)))
    cardWidth := Floor((width - margin * 2 - gap * (columns - 1)) / columns)
    rows := Max(1, Floor((height - top - bottom + gap) / (cardHeight + gap)))
    pageSize := Max(1, columns * rows)
    totalPages := Max(1, Ceil(Snippets.Length / pageSize))
    CurrentPage := Max(1, Min(CurrentPage, totalPages))

    AddButton.Move(margin, 18, 140, 42)
    SortButton.Move(170, 22, 88, 34)
    TrashButton.Move(268, 22, 88, 34)
    SettingsButton.Move(366, 22, 88, 34)
    NextButton.Move(width - margin - 72, 22, 72, 34)
    PrevButton.Move(width - margin - 152, 22, 72, 34)
    StatusText.Move(464, 28, Max(100, width - 656), 28)

    PrevButton.Enabled := CurrentPage > 1
    NextButton.Enabled := CurrentPage < totalPages
    PrevButton.Visible := Snippets.Length > pageSize
    NextButton.Visible := Snippets.Length > pageSize

    startIndex := (CurrentPage - 1) * pageSize + 1
    endIndex := Min(Snippets.Length, startIndex + pageSize - 1)

    for index, snippet in Snippets {
        visible := index >= startIndex && index <= endIndex
        snippet.Button.Visible := visible
        if !visible
            continue

        slot := index - startIndex
        row := Floor(slot / columns)
        column := Mod(slot, columns)
        x := margin + column * (cardWidth + gap)
        y := top + row * (cardHeight + gap)
        snippet.Button.Move(x, y, cardWidth, cardHeight)
    }

    EmptyText.Visible := Snippets.Length = 0
    if EmptyText.Visible
        EmptyText.Move(margin, top + 40, width - margin * 2, 80)

    if SortModeActive
        StatusText.Text := "排序模式 · 直接拖动文本按钮调整顺序"
    else if (Snippets.Length = 0)
        StatusText.Text := "尚未保存文本"
    else if (totalPages = 1)
        StatusText.Text := Snippets.Length " 个文本段 · 左键粘贴，右键管理"
    else
        StatusText.Text := Snippets.Length " 个文本段 · 第 " CurrentPage "/" totalPages " 页"
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
