//
//  FileTableView.swift
//  QuadFinder — 리스트 보기: AppKit의 펼침 표(NSOutlineView)를 SwiftUI에서 쓰도록 감싼 것
//
//  표가 직접 해 주는 것
//  - 폴더 아이콘 왼쪽의 ">" 를 누르면 그 자리에서 폴더 내용이 펼쳐짐 (→ / ← 키로도 펼치기·접기,
//    ⌥ 누르고 ">" 클릭하면 안쪽 폴더까지 한꺼번에)
//  - 클릭 / ⌘클릭 / ⇧클릭 선택, 빈 곳에서 끌어서 범위 선택
//  - 방향키 ↑↓ 이동, ⇧+방향키 범위 선택, ⌘A 전체 선택
//  - 이름을 입력하면 그 파일로 바로 이동 (type-select)
//  - 열 제목 클릭으로 정렬, 열 너비 기억
//  직접 덧붙인 것
//  - 파일 내용 미리보기(썸네일) 아이콘
//  - 여러 파일 한꺼번에 끌기: 그냥 끌면 복사, ⌘ 누른 채 끌면 이동 (Finder로 끌 때는 항상 복사)
//  - 단축키·우클릭 메뉴 (ListSupport.swift의 ListKey, FileCommands)
//  - 이름 바꾸기: Return을 누르면 이름 글자가 그 자리에서 편집 상태가 됨
//

import SwiftUI
import AppKit
import Quartz

// MARK: - 펼침 표의 한 줄 (폴더면 안에 하위 줄들을 가짐)

@MainActor
final class FileNode {
    let item: FileItem
    var children: [FileNode]? = nil      // nil = 아직 읽지 않음 (펼칠 때 읽음)

    init(_ item: FileItem) {
        self.item = item
    }
}

struct FileTableView: NSViewRepresentable {
    @ObservedObject var model: PaneModel
    var isActive: Bool               // 활성 칸이면 키보드 입력을 받음
    var events: ListEvents

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FileTable()
        let c = context.coordinator
        c.table = table
        c.lastFocusRequest = model.focusRequest

        table.style = .fullWidth
        table.rowSizeStyle = .default
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsTypeSelect = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.indentationPerLevel = 16
        table.autoresizesOutlineColumn = false

        addColumn(to: table, id: .name, title: "이름", width: 220, minWidth: 80)
        addColumn(to: table, id: .modified, title: "수정일", width: 130, minWidth: 60)
        addColumn(to: table, id: .size, title: "크기", width: 70, minWidth: 40)
        addColumn(to: table, id: .kind, title: "종류", width: 110, minWidth: 40)
        table.outlineTableColumn = table.tableColumn(withIdentifier: .name)   // ">" 가 붙는 열

        // 열 너비·순서를 칸마다 기억
        if model.store != nil {                         // 첫 번째 창만
            table.autosaveName = "pane\(model.index).table"
            table.autosaveTableColumns = true
        }

        // 지난번 정렬 상태 표시 (delegate 연결 전에 넣어서 정렬 이벤트가 생기지 않게)
        table.sortDescriptors = [NSSortDescriptor(key: model.sortKey.rawValue, ascending: model.sortAscending)]

        table.dataSource = c
        table.delegate = c
        table.target = c
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))

        // 끌기: 앱 안(다른 칸)으로는 복사·이동 가능, Finder 등 바깥으로는 항상 "복사"만
        table.setDraggingSourceOperationMask([.copy, .move, .generic, .link], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        // 놓기: 다른 곳에서 끌어 온 파일을 받음
        table.registerForDraggedTypes([.fileURL, .quadFolder])
        table.draggingDestinationFeedbackStyle = .regular

        let commands = table.commands
        commands.model = model
        commands.host = c
        commands.events = events
        table.menu = commands.menu                      // 우클릭 메뉴
        table.onMouseDown = { [weak c] in c?.parent.events.mouseDown() }
        table.onBecameFirstResponder = { [weak c] in c?.parent.events.becameActive() }
        table.onKey = { [weak commands] key in commands?.handle(key) }
        table.isActivePane = isActive

        c.renamer.onCommit = { [weak c] url, name in c?.parent.model.rename(url, to: name) }
        c.renamer.onFinish = { [weak table] in table?.window?.makeFirstResponder(table) }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true

        c.apply(model: model)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(model: model)
        context.coordinator.table?.isActivePane = isActive
        context.coordinator.table?.commands.events = events
        // 사이드바 클릭 등으로 포커스를 돌려 달라는 요청
        if model.focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = model.focusRequest
            context.coordinator.table?.takeFocus()
        }
    }

    private func addColumn(to table: NSTableView, id: NSUserInterfaceItemIdentifier,
                           title: String, width: CGFloat, minWidth: CGFloat) {
        let column = NSTableColumn(identifier: id)
        column.title = title
        column.width = width
        column.minWidth = minWidth
        column.sortDescriptorPrototype = NSSortDescriptor(key: id.rawValue, ascending: true)
        if id == .size { column.headerCell.alignment = .right }
        table.addTableColumn(column)
    }

    // MARK: - 표와 모델(PaneModel) 사이를 이어 주는 연결자

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, FileListHost {
        var parent: FileTableView
        weak var table: FileTable?
        let renamer = RenameEditor()
        var lastFocusRequest = 0

        private var roots: [FileNode] = []
        private var expanded = Set<URL>()          // 펼쳐 둔 폴더 (새로고침해도 펼친 상태 유지)
        private var shownItems: [FileItem] = []
        private var shownReloadCount = -1
        private var shownFolder: URL? = nil
        private var isSyncing = false     // 모델 → 표로 반영하는 중에는 표 → 모델로 되돌려 보내지 않음

        init(_ parent: FileTableView) {
            self.parent = parent
        }

        // 모델의 목록·선택을 표에 반영
        func apply(model: PaneModel) {
            guard let table else { return }
            isSyncing = true
            defer { isSyncing = false }

            // 다른 폴더로 이동하면 펼친 상태는 초기화
            let folderChanged = shownFolder != model.currentURL
            if folderChanged {
                shownFolder = model.currentURL
                expanded.removeAll()
            }

            if folderChanged || shownItems != model.items || shownReloadCount != model.reloadCount {
                shownItems = model.items
                shownReloadCount = model.reloadCount
                rebuild(model: model, force: folderChanged)
                if folderChanged { table.scrollRowToVisible(0) }
            }

            let wanted = IndexSet((0..<table.numberOfRows).filter { row in
                guard let node = table.item(atRow: row) as? FileNode else { return false }
                return model.selection.contains(node.item.url)
            })
            if table.selectedRowIndexes != wanted {
                table.selectRowIndexes(wanted, byExtendingSelection: false)
            }
        }

        // 목록을 새로 만들고, 펼쳐 두었던 폴더는 다시 읽어서 펼침.
        // 내용이 그대로면 화면을 건드리지 않음 (이름 편집 중이 끊기지 않게)
        private func rebuild(model: PaneModel, force: Bool) {
            guard let table else { return }
            let newRoots = model.items.map { FileNode($0) }
            loadExpanded(newRoots, model: model)
            if !force && flatten(newRoots) == flatten(roots) { return }

            roots = newRoots
            table.reloadData()
            expandSaved(roots)
        }

        private func loadExpanded(_ nodes: [FileNode], model: PaneModel) {
            for node in nodes where node.item.isDirectory && expanded.contains(node.item.url) {
                let kids = (try? model.loadItems(in: node.item.url)) ?? []
                node.children = kids.map { FileNode($0) }
                loadExpanded(node.children ?? [], model: model)
            }
        }

        private func expandSaved(_ nodes: [FileNode]) {
            guard let table else { return }
            for node in nodes where node.children != nil && expanded.contains(node.item.url) {
                table.expandItem(node)
                expandSaved(node.children ?? [])
            }
        }

        // 화면에 보이는 내용 비교용: (깊이, 항목) 목록. 펼쳐 둔 폴더의 내용만 포함
        private func flatten(_ nodes: [FileNode], depth: Int = 0) -> [String] {
            nodes.flatMap { node -> [String] in
                let i = node.item
                let me = "\(depth)|\(i.url.path)|\(i.name)|\(i.size ?? -1)|\(i.modified?.timeIntervalSince1970 ?? 0)|\(i.isHidden)"
                let kids = expanded.contains(i.url) ? flatten(node.children ?? [], depth: depth + 1) : []
                return [me] + kids
            }
        }

        private func node(atRow row: Int) -> FileNode? {
            table?.item(atRow: row) as? FileNode
        }

        // MARK: FileListHost (단축키·우클릭 메뉴가 쓰는 것)

        var selectedURLs: [URL] {
            guard let table else { return [] }
            return table.selectedRowIndexes.compactMap { node(atRow: $0)?.item.url }
        }

        func syncFromModel() {
            apply(model: parent.model)
        }

        func prepareContextMenu() -> Bool {
            guard let table else { return false }
            table.window?.makeFirstResponder(table)
            let row = table.clickedRow
            guard row >= 0, node(atRow: row) != nil else {
                table.deselectAll(nil)                  // 빈 곳 우클릭: 선택 해제
                return false
            }
            if !table.selectedRowIndexes.contains(row) {
                table.selectRowIndexes([row], byExtendingSelection: false)
            }
            return true
        }

        func beginRename(_ url: URL) {
            guard let table,
                  let row = (0..<table.numberOfRows).first(where: { node(atRow: $0)?.item.url == url })
            else { return }
            let col = table.column(withIdentifier: .name)
            guard col >= 0 else { return }
            table.scrollRowToVisible(row)
            guard let cell = table.view(atColumn: col, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField else { return }
            renamer.begin(field: field, url: url)
        }

        @objc func doubleClicked(_ sender: NSOutlineView) {
            guard let node = node(atRow: sender.clickedRow) else { return }   // 빈 곳 더블클릭은 무시
            parent.model.activate([node.item.url])
        }

        // MARK: 펼침 표에 보여 줄 내용

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? FileNode else { return roots.count }
            if node.children == nil {
                // 처음 펼칠 때 폴더 내용을 읽음
                let kids = (try? parent.model.loadItems(in: node.item.url)) ?? []
                node.children = kids.map { FileNode($0) }
            }
            return node.children?.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? FileNode else { return roots[index] }
            return node.children![index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileNode)?.item.isDirectory ?? false
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let id = tableColumn?.identifier, let node = item as? FileNode else { return nil }
            let file = node.item
            let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? FileCell) ?? FileCell.make(id)
            cell.alphaValue = file.isHidden ? 0.5 : 1      // 숨김 파일은 흐리게

            switch id {
            case .name:
                cell.textField?.stringValue = file.name
                cell.showIcon(for: file)
            case .modified:
                cell.textField?.stringValue = file.modified.map { $0.formatted(date: .numeric, time: .shortened) } ?? "--"
            case .size:
                cell.textField?.stringValue = file.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--"
            default:
                cell.textField?.stringValue = file.kind
            }
            return cell
        }

        // 펼치기·접기를 기억 (새로고침 뒤에도 유지)
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isSyncing, let node = notification.userInfo?["NSObject"] as? FileNode else { return }
            expanded.insert(node.item.url)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isSyncing, let node = notification.userInfo?["NSObject"] as? FileNode else { return }
            expanded.remove(node.item.url)
        }

        // MARK: 선택 (표 → 모델)

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing, let table else { return }
            let urls = Set(table.selectedRowIndexes.compactMap { node(atRow: $0)?.item.url })
            let anchor = node(atRow: table.selectedRow)?.item.url   // 가장 마지막에 선택한 줄
            parent.model.setSelection(urls, anchor: anchor)
            table.commands.preview.refresh()
        }

        // MARK: 이름 입력으로 바로 찾기

        func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any) -> String? {
            guard tableColumn?.identifier == .name else { return nil }
            return (item as? FileNode)?.item.name
        }

        // MARK: 정렬 (열 제목 클릭)

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let first = outlineView.sortDescriptors.first,
                  let keyName = first.key,
                  let key = SortKey(rawValue: keyName) else { return }
            parent.model.setSort(key, ascending: first.ascending)
            parent.model.reload(keepError: true)       // 펼친 하위 폴더도 같은 기준으로 다시 정렬
        }

        // MARK: 끌기 (여러 파일 가능)

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            (item as? FileNode)?.item.url as NSURL?
        }

        // MARK: 놓기 (규칙은 ListSupport.swift의 PaneDrop)

        func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo,
                         proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            // 같은 표 안에서 끌어 놓는 것은 아무 일도 하지 않음
            if let source = info.draggingSource as? NSOutlineView, source === outlineView { return [] }
            guard let drop = PaneDrop(info) else { return [] }
            outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)   // 표 전체를 테두리로 표시
            return drop.operation(for: info)
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo,
                         item: Any?, childIndex index: Int) -> Bool {
            guard let drop = PaneDrop(info) else { return false }
            drop.perform(on: parent.model)
            return true
        }
    }
}

// MARK: - 열 이름

extension NSUserInterfaceItemIdentifier {
    static let name = NSUserInterfaceItemIdentifier("name")
    static let modified = NSUserInterfaceItemIdentifier("modified")
    static let size = NSUserInterfaceItemIdentifier("size")
    static let kind = NSUserInterfaceItemIdentifier("kind")
}

// MARK: - 표의 칸 하나 (이름 열이면 아이콘 포함)

final class FileCell: NSTableCellView {
    private var iconURL: URL? = nil       // 미리보기가 늦게 도착했을 때, 그사이 다른 줄로 재사용됐는지 확인용

    static func make(_ id: NSUserInterfaceItemIdentifier) -> FileCell {
        let cell = FileCell()
        cell.identifier = id

        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.addSubview(text)
        cell.textField = text

        if id == .name {
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyUpOrDown
            cell.addSubview(icon)
            cell.imageView = icon
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            ])
        } else {
            text.textColor = .secondaryLabelColor
            text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            if id == .size { text.alignment = .right }
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
        }
        NSLayoutConstraint.activate([
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // 먼저 기본 아이콘을 보여 주고, 내용 미리보기가 준비되면 바꿔 끼움
    func showIcon(for file: FileItem) {
        iconURL = file.url
        if let thumb = ThumbnailCache.shared.thumbnail(for: file, done: { [weak self] image in
            guard let self, self.iconURL == file.url else { return }
            self.imageView?.image = image
        }) {
            imageView?.image = thumb
        } else {
            imageView?.image = NSWorkspace.shared.icon(forFile: file.url.path)
        }
    }
}

// MARK: - 키보드·마우스를 조금 손본 펼침 표

final class FileTable: NSOutlineView {
    var onMouseDown: (() -> Void)?
    var onBecameFirstResponder: (() -> Void)?
    var onKey: ((ListKey) -> Void)?
    let commands = FileCommands()

    // 활성 칸이 되면 키보드 입력을 받도록 스스로 포커스를 가져옴
    var isActivePane = false {
        didSet { if isActivePane && !oldValue { takeFocus() } }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        commands.preview.keyTarget = self
        if isActivePane { takeFocus() }
    }

    func takeFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onBecameFirstResponder?() }
        return ok
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let key = ListKey(event) {
            onKey?(key)
        } else {
            super.keyDown(with: event)       // ← → 펼치기·접기, ↑↓ 이동 등은 표가 처리
        }
    }

    // 메뉴 막대의 편집 > 복사·붙여넣기(⌘C/⌘V)가 이쪽으로 올 때
    @objc func copy(_ sender: Any?) { onKey?(.copy) }
    @objc func paste(_ sender: Any?) { onKey?(.paste(move: false)) }

    // 훑어보기 창이 이 표에게 "내용을 대 줄래?"라고 물을 때
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { commands.preview.begin(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { commands.preview.end(panel) }

    // Finder처럼: 아이콘이나 이름 글자 위에서 끌면 "파일 끌기",
    // 그 밖의 빈 부분에서 끌면 "범위 선택"
    override func canDragRows(with rowIndexes: IndexSet, at mouseDownPoint: NSPoint) -> Bool {
        let row = self.row(at: mouseDownPoint)
        let col = self.column(at: mouseDownPoint)
        guard row >= 0, col >= 0,
              tableColumns[col].identifier == .name,
              let cell = view(atColumn: col, row: row, makeIfNecessary: false) as? NSTableCellView
        else { return false }

        let p = cell.convert(mouseDownPoint, from: self)
        if let icon = cell.imageView, icon.frame.insetBy(dx: -2, dy: -2).contains(p) {
            return super.canDragRows(with: rowIndexes, at: mouseDownPoint)
        }
        if let text = cell.textField {
            let textWidth = min(text.intrinsicContentSize.width, text.frame.width)
            let textRect = NSRect(x: text.frame.minX, y: cell.bounds.minY,
                                  width: textWidth + 4, height: cell.bounds.height)
            if textRect.contains(p) {
                return super.canDragRows(with: rowIndexes, at: mouseDownPoint)
            }
        }
        return false
    }
}
