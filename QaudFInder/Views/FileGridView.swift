//
//  FileGridView.swift
//  QuadFinder — 아이콘 보기: AppKit의 컬렉션 뷰(NSCollectionView)를 SwiftUI에서 쓰도록 감싼 것
//
//  컬렉션 뷰가 직접 해 주는 것
//  - 클릭 / ⌘클릭 / ⇧클릭 선택, 빈 곳에서 끌어서 범위 선택(러버밴드)
//  - 방향키 ←→↑↓ 이동, ⇧+방향키 범위 선택, ⌘A 전체 선택
//  직접 덧붙인 것
//  - 여러 파일 한꺼번에 끌기: 그냥 끌면 복사, ⌘ 누른 채 끌면 이동 (Finder로 끌 때는 항상 복사)
//  - 더블클릭 열기, 단축키·우클릭 메뉴 (ListSupport.swift의 ListKey, FileCommands)
//  - 이름 바꾸기: Return을 누르면 이름 글자가 그 자리에서 편집 상태가 됨
//  - 이름 입력으로 바로 찾기 (type-select)
//  - 파일 내용 미리보기(썸네일) 아이콘
//  - 아이콘 크기 조절 (칸별, PaneModel.iconScale: 0.5 ~ 3배)
//  - 격자 간격 조절 (칸별, PaneModel.gridSpacing: 0.5 ~ 1.5배)
//

import SwiftUI
import AppKit
import Quartz

struct FileGridView: NSViewRepresentable {
    @ObservedObject var model: PaneModel
    @ObservedObject var settings = AppSettings.shared     // 미리보기 켜기/끄기가 바뀌면 다시 그림
    var isActive: Bool
    var events: ListEvents

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let grid = FileCollection()
        c.grid = grid
        c.lastFocusRequest = model.focusRequest

        let layout = NSCollectionViewFlowLayout()
        IconMetrics(scale: model.iconScale, spacing: model.gridSpacing).apply(to: layout)
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        grid.collectionViewLayout = layout

        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.allowsEmptySelection = true
        grid.backgroundColors = [.controlBackgroundColor]
        grid.register(IconItem.self, forItemWithIdentifier: IconItem.id)

        grid.dataSource = c
        grid.delegate = c

        // 끌기: 앱 안(다른 칸)으로는 복사·이동 가능, 바깥으로는 항상 "복사"만 / 놓기: 다른 곳의 파일을 받음
        grid.setDraggingSourceOperationMask([.copy, .move, .generic, .link], forLocal: true)
        grid.setDraggingSourceOperationMask(.copy, forLocal: false)
        grid.registerForDraggedTypes([.fileURL, .quadFolder])

        let commands = grid.commands
        commands.model = model
        commands.host = c
        commands.events = events
        grid.menu = commands.menu                       // 우클릭 메뉴
        grid.onMouseDown = { [weak c] in c?.parent.events.mouseDown() }
        grid.onBecameFirstResponder = { [weak c] in c?.parent.events.becameActive() }
        grid.onKey = { [weak commands] key in commands?.handle(key) }
        c.renamer.onCommit = { [weak c] url, name in c?.parent.model.rename(url, to: name) }
        c.renamer.onFinish = { [weak grid] in grid?.window?.makeFirstResponder(grid) }
        grid.onDoubleClick = { [weak c] index in c?.openItem(at: index) }
        grid.onTypeSelect = { [weak c] text in c?.typeSelect(text) }
        grid.isActivePane = isActive

        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        c.apply(model: model)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(model: model)
        context.coordinator.grid?.isActivePane = isActive
        context.coordinator.grid?.commands.events = events
        // 사이드바 클릭 등으로 포커스를 돌려 달라는 요청
        if model.focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = model.focusRequest
            context.coordinator.grid?.takeFocus()
        }
    }

    // MARK: - 컬렉션 뷰와 모델(PaneModel) 사이를 이어 주는 연결자

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, FileListHost {
        var parent: FileGridView
        weak var grid: FileCollection?
        let renamer = RenameEditor()
        var lastFocusRequest = 0
        private var items: [FileItem] = []
        private var shownScale: Double = 1.0
        private var shownSpacing: Double = 1.0
        private var shownLarge = false            // 큰 미리보기(아이콘 크기 200% 초과)를 쓰는 중
        private var shownThumbnails = AppSettings.shared.showThumbnails

        init(_ parent: FileGridView) {
            self.parent = parent
        }

        // 모델의 목록·선택을 화면에 반영
        func apply(model: PaneModel) {
            guard let grid else { return }
            // 아이콘 크기가 바뀌면: 칸 크기를 바꾸고, 보이는 아이콘만 즉시 크기 조절 (선택·스크롤 유지)
            // 격자 간격이 바뀌어도 칸 크기·간격만 바꿈
            if model.iconScale != shownScale || model.gridSpacing != shownSpacing {
                shownScale = model.iconScale
                shownSpacing = model.gridSpacing
                let metrics = IconMetrics(scale: shownScale, spacing: shownSpacing)
                if let layout = grid.collectionViewLayout as? NSCollectionViewFlowLayout {
                    metrics.apply(to: layout)
                    layout.invalidateLayout()
                }
                let wasLarge = shownLarge
                shownLarge = shownScale > 2.0
                if wasLarge != shownLarge {
                    grid.reloadData()               // 200%를 넘나들면 미리보기를 알맞은 크기로 다시 받음
                } else {
                    for case let icon as IconItem in grid.visibleItems() {
                        icon.setIconSize(metrics.iconSize)
                    }
                }
            }
            if shownThumbnails != AppSettings.shared.showThumbnails {
                shownThumbnails = AppSettings.shared.showThumbnails
                grid.reloadData()
            }
            if items != model.items {
                let folderChanged = items.first?.url.deletingLastPathComponent() != model.items.first?.url.deletingLastPathComponent()
                items = model.items
                grid.reloadData()
                if folderChanged { grid.scroll(.zero) }
            }
            // 코드로 선택을 바꾸면 delegate가 다시 불리지 않으므로 되돌림 걱정 없음
            let wanted = Set(items.indices.filter { model.selection.contains(items[$0].url) }
                .map { IndexPath(item: $0, section: 0) })
            if grid.selectionIndexPaths != wanted {
                grid.selectionIndexPaths = wanted
            }
        }

        // MARK: FileListHost (단축키·우클릭 메뉴가 쓰는 것)

        var selectedURLs: [URL] {
            guard let grid else { return [] }
            return grid.selectionIndexPaths.sorted().compactMap { $0.item < items.count ? items[$0.item].url : nil }
        }

        func syncFromModel() {
            apply(model: parent.model)
        }

        func prepareContextMenu() -> Bool {
            guard let grid else { return false }
            grid.window?.makeFirstResponder(grid)
            guard let point = grid.lastMenuPoint,
                  let path = grid.indexPathForItem(at: point), path.item < items.count else {
                grid.selectionIndexPaths = []           // 빈 곳 우클릭: 선택 해제
                selectionChanged(last: nil)
                return false
            }
            if !grid.selectionIndexPaths.contains(path) {
                grid.selectionIndexPaths = [path]
                selectionChanged(last: path)
            }
            return true
        }

        func beginRename(_ url: URL) {
            guard let grid, let index = items.firstIndex(where: { $0.url == url }) else { return }
            let path = IndexPath(item: index, section: 0)
            grid.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
            grid.layoutSubtreeIfNeeded()
            guard let item = grid.item(at: path) as? IconItem else { return }
            renamer.begin(field: item.nameField, url: url)
        }

        func openItem(at index: Int) {
            guard index < items.count else { return }
            parent.model.activate([items[index].url])
        }

        // 입력한 글자로 시작하는 첫 파일 선택
        func typeSelect(_ text: String) {
            guard let grid,
                  let index = items.firstIndex(where: {
                      $0.name.range(of: text, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                  }) else { return }
            let path = IndexPath(item: index, section: 0)
            grid.selectionIndexPaths = [path]
            grid.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
            selectionChanged(last: path)
        }

        // MARK: 보여 줄 내용

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ collectionView: NSCollectionView,
                            itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: IconItem.id, for: indexPath)
            if let icon = item as? IconItem, indexPath.item < items.count {
                icon.configure(items[indexPath.item], iconSize: IconMetrics(scale: shownScale, spacing: shownSpacing).iconSize,
                               largeThumbnail: shownLarge)
            }
            return item
        }

        // MARK: 선택 (화면 → 모델)

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            selectionChanged(last: indexPaths.count == 1 ? indexPaths.first : nil)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            selectionChanged(last: nil)
        }

        private func selectionChanged(last: IndexPath?) {
            guard let grid else { return }
            let urls = Set(grid.selectionIndexPaths.compactMap { $0.item < items.count ? items[$0.item].url : nil })
            // 훑어보기 대상: 방금 고른 파일, 없으면 이전 것을 유지
            var anchor = parent.model.previewTarget
            if let last, last.item < items.count { anchor = items[last.item].url }
            parent.model.setSelection(urls, anchor: anchor)
            grid.commands.preview.refresh()
        }

        // MARK: 끌기 (여러 파일 가능)

        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>,
                            with event: NSEvent) -> Bool { true }

        func collectionView(_ collectionView: NSCollectionView,
                            pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
            guard indexPath.item < items.count else { return nil }
            return items[indexPath.item].url as NSURL
        }

        // MARK: 놓기 (규칙은 ListSupport.swift의 PaneDrop)

        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
                            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            // 같은 칸 안에서 끌어 놓는 것은 아무 일도 하지 않음
            if let source = draggingInfo.draggingSource as? NSCollectionView, source === collectionView {
                grid?.isDropHighlighted = false
                return []
            }
            guard let drop = PaneDrop(draggingInfo) else { return [] }
            // 특정 아이콘 "위"가 아니라 목록 끝에 놓는 것으로 처리 (폴더 안으로 들어가지 않음)
            proposedDropIndexPath.pointee = NSIndexPath(forItem: items.count, inSection: 0)
            proposedDropOperation.pointee = .before
            grid?.isDropHighlighted = true
            return drop.operation(for: draggingInfo)
        }

        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo,
                            indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            grid?.isDropHighlighted = false
            guard let drop = PaneDrop(draggingInfo) else { return false }
            drop.perform(on: parent.model)
            return true
        }
    }
}

// MARK: - 아이콘 크기·격자 간격 계산
// 배율 1·간격 1 = 1.0까지의 모습: 아이콘 48pt, 칸 88×94, 칸 사이 6pt
// 격자 간격(spacing)은 "눈에 보이는 간격" 전체를 바꿉니다:
//   아이콘 양옆의 이름 여백(40pt) + 칸 사이(6pt), 줄 사이(6pt)
//   좁게(0.5)는 이름이 들어갈 폭도 좁아져 긴 이름이 더 잘림 (Finder와 같음)

struct IconMetrics {
    let iconSize: CGFloat
    let itemSize: NSSize
    let interitemSpacing: CGFloat
    let lineSpacing: CGFloat

    init(scale: Double, spacing: Double = 1.0) {
        iconSize = (48 * scale).rounded()
        let margin = (40 * spacing).rounded()
        let width = max(80 * spacing, iconSize + margin)   // 이름 두 줄이 들어갈 너비
        itemSize = NSSize(width: width.rounded(), height: iconSize + 8 + 2 + 36)
        interitemSpacing = (6 * spacing).rounded()
        lineSpacing = max(0, (6 + 16 * (spacing - 1)).rounded())   // 0.5 → 0, 1 → 6, 1.5 → 14
    }

    func apply(to layout: NSCollectionViewFlowLayout) {
        layout.itemSize = itemSize
        layout.minimumInteritemSpacing = interitemSpacing
        layout.minimumLineSpacing = lineSpacing
    }
}

// MARK: - 아이콘 하나 (아이콘 + 이름 두 줄)

final class IconItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("IconItem")

    private let iconBackground = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    var nameField: NSTextField { label }                 // 이름 바꾸기 때 편집할 글자 칸
    private var iconSizeConstraints: [NSLayoutConstraint] = []
    private var backgroundSizeConstraints: [NSLayoutConstraint] = []
    private var shownURL: URL? = nil                     // 미리보기가 늦게 도착했을 때 확인용

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 88, height: 96))

        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 6
        iconBackground.translatesAutoresizingMaskIntoConstraints = false

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 11)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        label.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(iconBackground)
        root.addSubview(icon)
        root.addSubview(label)
        NSLayoutConstraint.activate([
            iconBackground.topAnchor.constraint(equalTo: root.topAnchor, constant: 2),
            iconBackground.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            label.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 3),
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -2),
        ])

        backgroundSizeConstraints = [
            iconBackground.widthAnchor.constraint(equalToConstant: 56),
            iconBackground.heightAnchor.constraint(equalToConstant: 56),
        ]
        iconSizeConstraints = [
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
        ]
        NSLayoutConstraint.activate(backgroundSizeConstraints + iconSizeConstraints)

        view = root
        imageView = icon
        textField = label
        updateLook()
    }

    func setIconSize(_ size: CGFloat) {
        iconSizeConstraints.forEach { $0.constant = size }
        backgroundSizeConstraints.forEach { $0.constant = size + 8 }
    }

    func configure(_ item: FileItem, iconSize: CGFloat, largeThumbnail: Bool = false) {
        setIconSize(iconSize)
        shownURL = item.url
        // 먼저 기본 아이콘, 내용 미리보기가 준비되면 바꿔 끼움
        if AppSettings.shared.showThumbnails,             // 설정에서 끄면 기본 아이콘만
           let thumb = ThumbnailCache.shared.thumbnail(for: item, large: largeThumbnail, done: { [weak self] image in
            guard let self, self.shownURL == item.url else { return }
            self.icon.image = image
        }) {
            icon.image = thumb
        } else {
            icon.image = NSWorkspace.shared.icon(forFile: item.url.path)
        }
        label.stringValue = item.name
        view.alphaValue = item.isHidden ? 0.5 : 1          // 숨김 파일은 흐리게
        updateLook()
    }

    override var isSelected: Bool {
        didSet { updateLook() }
    }

    // 선택되면 아이콘 뒤에 옅은 회색, 이름에 강조색 배경 (Finder와 비슷하게)
    private func updateLook() {
        let selected = isSelected
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            iconBackground.layer?.backgroundColor = selected
                ? NSColor.quaternaryLabelColor.cgColor : NSColor.clear.cgColor
            label.layer?.backgroundColor = selected
                ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        }
        label.textColor = selected ? .white : .labelColor
    }
}

// MARK: - 키보드·마우스를 조금 손본 컬렉션 뷰

final class FileCollection: NSCollectionView {
    var onMouseDown: (() -> Void)?
    var onBecameFirstResponder: (() -> Void)?
    var onKey: ((ListKey) -> Void)?
    var onDoubleClick: ((Int) -> Void)?
    var onTypeSelect: ((String) -> Void)?
    let commands = FileCommands()
    private(set) var lastMenuPoint: NSPoint?           // 우클릭한 위치

    private var typed = ""
    private var lastTypedAt = Date.distantPast

    // 활성 칸이 되면 키보드 입력을 받도록 스스로 포커스를 가져옴
    var isActivePane = false {
        didSet { if isActivePane && !oldValue { takeFocus() } }
    }

    // 다른 곳에서 파일을 끌고 들어왔을 때 테두리
    var isDropHighlighted = false {
        didSet {
            guard isDropHighlighted != oldValue, let scroll = enclosingScrollView else { return }
            scroll.wantsLayer = true
            scroll.layer?.borderWidth = isDropHighlighted ? 2 : 0
            scroll.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
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
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            if let path = indexPathForItem(at: point) {
                onDoubleClick?(path.item)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        let typing = Date().timeIntervalSince(lastTypedAt) < 1.0

        // 이름을 입력하는 중이면 스페이스도 글자로 취급
        if let key = ListKey(event), !(typing && event.keyCode == 49) {
            onKey?(key)
            return
        }

        // 글자 입력 → 이름으로 바로 찾기
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if flags.isEmpty, let chars = event.characters, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) {
            if !typing { typed = "" }
            typed += chars
            lastTypedAt = Date()
            onTypeSelect?(typed)
            return
        }
        super.keyDown(with: event)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        isDropHighlighted = false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        super.draggingEnded(sender)
        isDropHighlighted = false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        lastMenuPoint = convert(event.locationInWindow, from: nil)
        let menu = super.menu(for: event)
        commands.rebuildMenu()
        return menu
    }

    // 서비스: 선택한 파일이 있으면 "파일을 넘겨줄 수 있음"이라고 알림 (ListSupport.swift의 ServiceSupport)
    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        if returnType == nil, let sendType, ServiceSupport.sendTypes.contains(sendType),
           !(commands.host?.selectedURLs.isEmpty ?? true) {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        ServiceSupport.write(commands.host?.selectedURLs ?? [], to: pboard)
    }

    // 메뉴 막대의 편집 > 복사·붙여넣기(⌘C/⌘V)가 이쪽으로 올 때
    @objc func copy(_ sender: Any?) { onKey?(.copy) }
    @objc func paste(_ sender: Any?) { onKey?(.paste(move: false)) }

    // 훑어보기 창 연결
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { commands.preview.begin(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { commands.preview.end(panel) }
}
