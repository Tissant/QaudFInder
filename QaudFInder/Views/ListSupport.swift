//
//  ListSupport.swift
//  QuadFinder — 리스트 보기(표)와 아이콘 보기가 함께 쓰는 부품
//  - 칸 → 화면 전체로 알리는 이벤트 묶음 (ListEvents)
//  - 키보드 단축키 해석 (ListKey)
//  - 끌어 온 파일 주소 읽기
//  - 훑어보기 창(QLPreviewPanel) 연결 (PreviewController)
//

import AppKit
import Quartz
import UniformTypeIdentifiers

// MARK: - 목록에서 일어난 일을 바깥(PaneView/ContentView)으로 알리는 통로

struct ListEvents {
    var mouseDown: () -> Void                 // 목록을 클릭함 (병합 선택 취소 + 활성 칸으로)
    var becameActive: () -> Void              // 목록이 키보드 입력을 받게 됨 → 활성 칸
    var tab: (_ backward: Bool) -> Void       // Tab / ⇧Tab → 다음·이전 칸
    var escape: () -> Void                    // esc → 병합 선택 취소
}

// MARK: - 단축키
// 키 위치 번호(keyCode)로 판별합니다. 한글 입력 상태에서도 똑같이 동작하게 하려고.

enum ListKey {
    case preview                 // 스페이스
    case open                    // ⌘↓, ⌘O
    case rename                  // Return, 숫자패드 Enter (Finder와 같음)
    case goUp                    // ⌘↑
    case trash                   // ⌘⌫ 휴지통으로 이동
    case newFolder               // ⇧⌘N
    case copy                    // ⌘C
    case paste(move: Bool)       // ⌘V 복사해서 붙여넣기 / ⌥⌘V 옮기기
    case copyPath                // ⌥⌘C 경로 복사
    case toggleHidden            // ⇧⌘. 숨김 파일 보기/가리기
    case tab(backward: Bool)     // Tab / ⇧Tab
    case escape

    // 1.1.0: 바꿀 수 있는 단축키는 설정 창 "단축키" 탭의 값(ShortcutStore)을 따름
    init?(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        // 고정 단축키 (macOS 편집 메뉴·칸 이동과 같음)
        switch (event.keyCode, flags) {
        case (8, .command):       self = .copy; return                 // ⌘C
        case (9, .command):       self = .paste(move: false); return   // ⌘V
        case (48, []):            self = .tab(backward: false); return
        case (48, [.shift]):      self = .tab(backward: true); return
        case (53, _):             self = .escape; return
        default: break
        }
        switch ShortcutStore.shared.action(for: event) {
        case .open:         self = .open
        case .preview:      self = .preview
        case .rename:       self = .rename
        case .goUp:         self = .goUp
        case .trash:        self = .trash
        case .newFolder:    self = .newFolder
        case .pasteMove:    self = .paste(move: true)
        case .copyPath:     self = .copyPath
        case .toggleHidden: self = .toggleHidden
        case .goToFolder, nil: return nil        // 폴더로 이동은 메뉴 막대(이동 메뉴)가 처리
        }
    }

    // 훑어보기 창이 떠 있을 때 목록으로 넘길 방향키(←→↑↓, ⇧ 포함)
    static func isArrow(_ event: NSEvent) -> Bool {
        [123, 124, 125, 126].contains(event.keyCode)
            && !event.modifierFlags.contains(.command)
    }
}

// MARK: - 끌어 놓기 규칙 (칸에 무언가를 놓았을 때)
//
//  끄는 것              놓는 곳   동작
//  사이드바 항목        칸        그 칸이 해당 폴더로 이동
//  칸의 파일·폴더       다른 칸   복사 (끌기 시작 후 ⌘ 누르면 이동)
//  칸의 폴더 + ⌥        다른 칸   그 칸이 해당 폴더로 이동
//  Finder의 파일        칸        복사

extension NSPasteboard.PasteboardType {
    // 사이드바에서 끈 폴더 (파일 주소가 아니라 "이 폴더로 가라"는 뜻이라 따로 구분)
    static let quadFolder = NSPasteboard.PasteboardType("net.tissant.quadfinder.folder")
    // 사이드바 안에서 순서를 바꿀 때 (몇 번째 줄인지)
    static let quadSidebarRow = NSPasteboard.PasteboardType("net.tissant.quadfinder.sidebar-row")
}

enum PaneDrop {
    case navigate(URL)      // 칸이 그 폴더로 이동
    case copy([URL])
    case move([URL])

    init?(_ info: any NSDraggingInfo) {
        if let path = info.draggingPasteboard.string(forType: .quadFolder) {
            self = .navigate(URL(fileURLWithPath: path))
            return
        }
        let urls = draggedFileURLs(info)
        guard !urls.isEmpty else { return nil }
        if NSEvent.modifierFlags.contains(.option), urls.count == 1, SidebarModel.isFolder(urls[0]) {
            self = .navigate(urls[0])
        } else if dropWantsMove(info) != (AppSettings.shared.dragDefaultMove && info.draggingSource != nil) {
            // 설정 "끌어 놓기 기본 동작 = 이동"이면 앱 안에서 끌 때만 반대로 (Finder에서 온 파일은 항상 복사)
            self = .move(urls)
        } else {
            self = .copy(urls)
        }
    }

    // 마우스 커서 모양 (복사: +, 이동: 없음, 폴더로 이동: 화살표)
    func operation(for info: any NSDraggingInfo) -> NSDragOperation {
        switch self {
        case .copy: return .copy
        case .move: return .move
        case .navigate:
            return info.draggingSourceOperationMask.contains(.link) ? .link : .copy
        }
    }

    @MainActor
    func perform(on model: PaneModel) {
        switch self {
        case .navigate(let url): model.open(url)
        case .copy(let urls):    model.copyIn(urls)
        case .move(let urls):    model.moveIn(urls)
        }
    }

    var isNavigate: Bool {
        if case .navigate = self { return true }
        return false
    }
}

// 그냥 끌면 복사, ⌘를 누른 채 끌면 이동 (macOS는 ⌘를 누르면 "generic"으로 알려 줌)
func dropWantsMove(_ info: any NSDraggingInfo) -> Bool {
    let mask = info.draggingSourceOperationMask
    return !mask.contains(.copy) && (mask.contains(.move) || mask.contains(.generic))
}

// MARK: - 끌어 온 파일 주소 읽기

func draggedFileURLs(_ info: any NSDraggingInfo) -> [URL] {
    let objects = info.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) ?? []
    return objects.compactMap { $0 as? URL }
}

// MARK: - 훑어보기(Quick Look) 창 연결
// 한 번에 한 파일만 보여 줍니다(마지막으로 선택한 파일).
// 창이 떠 있는 동안 방향키를 누르면 목록의 선택이 움직이고, 창도 그 파일로 바뀝니다.

@MainActor
final class PreviewController: NSObject {
    weak var model: PaneModel?
    weak var keyTarget: NSView?               // 방향키를 넘겨줄 목록(표 또는 아이콘 보기)
    private(set) var isControlling = false

    func toggle() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else if model?.previewTarget != nil {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func begin(_ panel: QLPreviewPanel) {
        isControlling = true
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    func end(_ panel: QLPreviewPanel) {
        isControlling = false
        panel.dataSource = nil
        panel.delegate = nil
    }

    // 선택이 바뀌었을 때 창이 떠 있으면 새 파일로 바꿔 보여 줌.
    // 아이콘 보기는 방향키로 움직이면 "예전 것 선택 해제 → 새 것 선택" 두 단계로 알려 주는데,
    // 그 사이 잠깐 선택이 비어 보여서 창이 닫히던 문제가 있었음.
    // → 바로 판단하지 않고 한 박자 미뤘다가, 두 단계가 다 끝난 최종 선택으로 판단.
    private var refreshPending = false

    func refresh() {
        guard isControlling, !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            guard self.isControlling, QLPreviewPanel.sharedPreviewPanelExists(),
                  let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
            if self.model?.previewTarget == nil {
                panel.orderOut(nil)
            } else {
                panel.reloadData()
            }
        }
    }
}

extension PreviewController: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        model?.previewTarget == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        model?.previewTarget as NSURL?
    }
}

extension PreviewController: @preconcurrency QLPreviewPanelDelegate {
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown, ListKey.isArrow(event), let keyTarget else { return false }
        keyTarget.keyDown(with: event)
        return true
    }
}

// MARK: - 표·아이콘 보기가 공통으로 제공해야 하는 것

@MainActor
protocol FileListHost: AnyObject {
    var selectedURLs: [URL] { get }
    func prepareContextMenu() -> Bool     // 우클릭한 항목을 선택. 항목 위에서 눌렀으면 true
    func beginRename(_ url: URL)          // 이름 칸을 편집 상태로
    func syncFromModel()                  // 모델의 목록을 화면에 즉시 반영
}

// MARK: - 단축키·우클릭 메뉴가 실제로 하는 일 (표·아이콘 보기 공통)

@MainActor
final class FileCommands: NSObject {
    weak var model: PaneModel? {
        didSet { preview.model = model }
    }
    weak var host: (any FileListHost)?
    var events: ListEvents?
    let preview = PreviewController()
    let menu = NSMenu()

    override init() {
        super.init()
        menu.autoenablesItems = false
    }

    func handle(_ key: ListKey) {
        guard let model, let host else { return }
        switch key {
        case .preview:           preview.toggle()
        case .open:              model.activate(host.selectedURLs)
        case .rename:            renameSelection()
        case .goUp:              model.goUp()
        case .trash:             trashSelection(host.selectedURLs, model: model)
        case .newFolder:         newFolder()
        case .copy:              model.copyToPasteboard(host.selectedURLs)
        case .paste(let move):   model.pasteFromPasteboard(move: move)
        case .copyPath:          model.copyPaths(host.selectedURLs)
        case .toggleHidden:      model.toggleHidden()
        case .tab(let backward): events?.tab(backward)
        case .escape:            events?.escape()
        }
    }

    // 설정 "휴지통으로 보내기 전 확인"이 켜져 있으면 먼저 물어봄
    private func trashSelection(_ urls: [URL], model: PaneModel) {
        guard !urls.isEmpty else { return }
        if AppSettings.shared.confirmTrash {
            let alert = NSAlert()
            alert.messageText = urls.count == 1
                ? "'\(urls[0].lastPathComponent)'을(를) 휴지통으로 이동하겠습니까?"
                : "\(urls.count)개 항목을 휴지통으로 이동하겠습니까?"
            alert.informativeText = "휴지통에서 되돌려 놓을 수 있습니다."
            alert.addButton(withTitle: "휴지통으로 이동")
            alert.addButton(withTitle: "취소")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        model.moveToTrash(urls)
    }

    private func renameSelection() {
        guard let urls = host?.selectedURLs, urls.count == 1 else { return }
        host?.beginRename(urls[0])
    }

    private func newFolder() {
        guard let host, let url = model?.makeNewFolder() else { return }
        host.syncFromModel()
        host.beginRename(url)
    }

    // MARK: 우클릭 메뉴
    // 표·아이콘 보기의 menu(for:)에서 메뉴를 보여 주기 직전에 부릅니다.
    // (그 뒤에 macOS가 "서비스" 항목을 자동으로 덧붙입니다 → ServiceSupport)

    func rebuildMenu() {
        menu.removeAllItems()
        guard let host else { return }
        if host.prepareContextMenu() {
            let single = host.selectedURLs.count == 1
            add("열기", #selector(menuOpen), action: .open)
            addOpenWith(host.selectedURLs)
            add("훑어보기", #selector(menuPreview), enabled: single, action: .preview)
            menu.addItem(.separator())
            add("이름 바꾸기", #selector(menuRename), enabled: single, action: .rename)
            add("복사", #selector(menuCopy), key: "c")
            add("휴지통으로 이동", #selector(menuTrash), action: .trash)
            menu.addItem(.separator())
            add("경로 복사", #selector(menuCopyPath), action: .copyPath)
            add("Finder에서 보기", #selector(menuReveal))
            let folders = host.selectedURLs.filter { SidebarModel.isFolder($0) }
            if !folders.isEmpty && folders.count == host.selectedURLs.count {
                add("사이드바에 추가", #selector(menuAddToSidebar))
            }
        } else {
            // 빈 곳을 우클릭
            let canPaste = NSPasteboard.general.canReadObject(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            add("새 폴더", #selector(menuNewFolder), action: .newFolder)
            add("붙여넣기", #selector(menuPaste), enabled: canPaste, key: "v")
            menu.addItem(.separator())
            add("경로 복사", #selector(menuCopyPath), action: .copyPath)
            add("Finder에서 보기", #selector(menuReveal))
            add("이 폴더를 사이드바에 추가", #selector(menuAddToSidebar))
            menu.addItem(.separator())
            add(model?.showHidden == true ? "숨김 파일 가리기" : "숨김 파일 보기",
                #selector(menuToggleHidden), action: .toggleHidden)
        }
    }

    // shortcut: 메뉴 오른쪽에 보여 줄 단축키 (설정에서 바꾼 값)
    private func add(_ title: String, _ action: Selector, enabled: Bool = true,
                     key: String = "", flags: NSEvent.ModifierFlags = .command,
                     action shortcut: ShortcutAction? = nil) {
        var key = key, flags = flags
        if let shortcut, let combo = ShortcutStore.shared.primary(for: shortcut) {
            key = combo.menuKey
            flags = combo.flags
        }
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : flags
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc private func menuOpen()      { handle(.open) }
    @objc private func menuPreview()   { handle(.preview) }
    @objc private func menuRename()    { handle(.rename) }
    @objc private func menuCopy()      { handle(.copy) }
    @objc private func menuTrash()     { handle(.trash) }
    @objc private func menuCopyPath()  { handle(.copyPath) }
    @objc private func menuNewFolder() { handle(.newFolder) }
    @objc private func menuPaste()     { handle(.paste(move: false)) }
    @objc private func menuReveal()    { model?.revealInFinder(host?.selectedURLs ?? []) }
    @objc private func menuToggleHidden() { handle(.toggleHidden) }
    @objc private func menuAddToSidebar() {
        guard let model else { return }
        let urls = host?.selectedURLs ?? []
        SidebarModel.shared.add(urls.isEmpty ? [model.currentURL] : urls)
    }

    // MARK: 다음으로 열기 ▸
    // Finder와 같은 모양: 기본 앱(맨 위, "(기본)") → 구분선 → 다른 앱(이름순) → 구분선 → 기타…
    // 여러 파일을 골랐으면 모두 열 수 있는 앱만 보여 줍니다.
    // ("항상 이 앱으로 열기"는 나중에 넣을 수 있게 비워 둠)

    private var openWithTargets: [URL] = []

    private func addOpenWith(_ urls: [URL]) {
        let files = urls.filter { !SidebarModel.isFolder($0) || $0.pathExtension == "app" }
        guard !files.isEmpty, files.count == urls.count else { return }   // 폴더가 섞이면 넣지 않음
        openWithTargets = files

        let ws = NSWorkspace.shared
        var common: [URL]? = nil
        for file in files {
            let apps = ws.urlsForApplications(toOpen: file).map { $0.standardizedFileURL }
            common = common.map { prev in prev.filter { apps.contains($0) } } ?? apps
        }
        let defaultApp = ws.urlForApplication(toOpen: files[0])?.standardizedFileURL
        let others = (common ?? [])
            .filter { $0 != defaultApp }
            .reduce(into: [URL]()) { list, url in            // 같은 앱이 여러 위치에 있으면 하나만
                if !list.contains(where: { Self.appName($0) == Self.appName(url) }) { list.append(url) }
            }
            .sorted { Self.appName($0).localizedStandardCompare(Self.appName($1)) == .orderedAscending }

        let sub = NSMenu()
        sub.autoenablesItems = false
        if let defaultApp, common?.contains(defaultApp) ?? false {
            sub.addItem(appItem(defaultApp, title: Self.appName(defaultApp) + " (기본)"))
            if !others.isEmpty { sub.addItem(.separator()) }
        }
        for app in others { sub.addItem(appItem(app, title: Self.appName(app))) }
        if sub.numberOfItems > 0 { sub.addItem(.separator()) }
        let other = NSMenuItem(title: "기타…", action: #selector(openWithOther), keyEquivalent: "")
        other.target = self
        sub.addItem(other)

        let item = NSMenuItem(title: "다음으로 열기", action: nil, keyEquivalent: "")
        item.submenu = sub
        menu.addItem(item)
    }

    private func appItem(_ app: URL, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openWithApp(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = app
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 16, height: 16)
        item.image = icon
        return item
    }

    private static func appName(_ app: URL) -> String {
        FileManager.default.displayName(atPath: app.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        open(openWithTargets, with: app)
    }

    @objc private func openWithOther() {
        let files = openWithTargets
        let panel = NSOpenPanel()
        panel.title = "다음으로 열기"
        panel.prompt = "열기"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let app = panel.url else { return }
            self?.open(files, with: app)
        }
    }

    private func open(_ files: [URL], with app: URL) {
        let model = self.model
        NSWorkspace.shared.open(files, withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor in
                model?.errorMessage = "열지 못함: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 서비스 (우클릭 메뉴 맨 아래 "서비스 ▸")
// 표·아이콘 보기가 "선택한 파일을 다른 앱에 넘겨줄 수 있다"고 macOS에 알리면,
// 파일을 받는 다른 앱의 서비스와 사용자가 만든 단축어·빠른 동작이 Finder처럼 자동으로 붙습니다.
// (반디집처럼 "Finder에서만"으로 정해 둔 서비스는 macOS가 보여 주지 않습니다)

enum ServiceSupport {
    static let sendTypes: [NSPasteboard.PasteboardType] = [.fileURL]

    @MainActor static func register() {
        NSApp.registerServicesMenuSendTypes(sendTypes, returnTypes: [])
    }

    // 선택한 파일 주소를 서비스에 넘겨줄 클립보드에 적기
    static func write(_ urls: [URL], to pboard: NSPasteboard) -> Bool {
        guard !urls.isEmpty else { return false }
        pboard.clearContents()
        return pboard.writeObjects(urls as [NSURL])
    }
}

// MARK: - 이름 바꾸기 편집기
// 목록의 이름 글자를 그 자리에서 편집 상태로 바꿉니다.
// Return 또는 다른 곳 클릭: 확정 / esc: 취소

@MainActor
final class RenameEditor: NSObject, NSTextFieldDelegate {
    private weak var field: NSTextField?
    private var url: URL?
    private var shownName = ""
    private var savedColor: NSColor?
    private var savedDrawsBackground = false
    private var cancelled = false

    var onCommit: ((URL, String) -> Void)?
    var onFinish: (() -> Void)?             // 편집이 끝나면 (목록으로 포커스 되돌리기 등)

    var isEditing: Bool { field != nil }

    func begin(field: NSTextField, url: URL) {
        finish()
        self.field = field
        self.url = url
        shownName = field.stringValue
        savedColor = field.textColor
        savedDrawsBackground = field.drawsBackground
        cancelled = false

        // 화면에는 확장자가 숨겨져 있을 수 있으니, 편집할 때는 실제 파일 이름 전체를 보여 줌
        field.stringValue = url.lastPathComponent
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.textColor = .labelColor
        field.delegate = self
        field.window?.makeFirstResponder(field)

        // Finder처럼 확장자 앞부분만 선택 (폴더는 전체)
        if let editor = field.currentEditor() {
            let full = url.lastPathComponent as NSString
            let base = url.pathExtension.isEmpty || url.hasDirectoryPath
                ? full : (full.deletingPathExtension as NSString)
            editor.selectedRange = NSRange(location: 0, length: base.length)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field, let url else { return }
        let newName = field.stringValue
        let wasCancelled = cancelled
        finish()
        if !wasCancelled { onCommit?(url, newName) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelled = true
            field?.abortEditing()
            finish()
            return true
        }
        return false
    }

    private func finish() {
        guard let field else { return }
        self.field = nil
        field.delegate = nil
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = savedDrawsBackground
        field.textColor = savedColor
        field.stringValue = shownName
        onFinish?()
    }
}
