//
//  FileGridView.swift
//  QuadFinder — 아이콘 보기: AppKit의 컬렉션 뷰(NSCollectionView)를 SwiftUI에서 쓰도록 감싼 것
//
//  컬렉션 뷰가 직접 해 주는 것
//  - 클릭 / ⌘클릭 / ⇧클릭 선택, 빈 곳에서 끌어서 범위 선택(러버밴드)
//  - 방향키 ←→↑↓ 이동, ⇧+방향키 범위 선택, ⌘A 전체 선택
//  직접 덧붙인 것
//  - 여러 파일 한꺼번에 끌기 (항상 "복사"로만 끌림)
//  - 더블클릭·Return·⌘↓ 열기, ⌘↑ 상위 폴더, 스페이스 훑어보기, Tab 다음 칸
//  - 이름 입력으로 바로 찾기 (type-select)
//

import SwiftUI
import AppKit
import Quartz

struct FileGridView: NSViewRepresentable {
    @ObservedObject var model: PaneModel
    var isActive: Bool
    var events: ListEvents

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let grid = FileCollection()
        c.grid = grid

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 88, height: 96)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        grid.collectionViewLayout = layout

        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.allowsEmptySelection = true
        grid.backgroundColors = [.controlBackgroundColor]
        grid.register(IconItem.self, forItemWithIdentifier: IconItem.id)

        grid.dataSource = c
        grid.delegate = c

        // 끌기: 항상 "복사"만 허용 / 놓기: 다른 곳의 파일을 받음
        grid.setDraggingSourceOperationMask(.copy, forLocal: true)
        grid.setDraggingSourceOperationMask(.copy, forLocal: false)
        grid.registerForDraggedTypes([.fileURL])

        grid.preview.model = model
        grid.onMouseDown = { [weak c] in c?.parent.events.mouseDown() }
        grid.onBecameFirstResponder = { [weak c] in c?.parent.events.becameActive() }
        grid.onKey = { [weak c] key in c?.handle(key) }
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
    }

    // MARK: - 컬렉션 뷰와 모델(PaneModel) 사이를 이어 주는 연결자

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: FileGridView
        weak var grid: FileCollection?
        private var items: [FileItem] = []

        init(_ parent: FileGridView) {
            self.parent = parent
        }

        // 모델의 목록·선택을 화면에 반영
        func apply(model: PaneModel) {
            guard let grid else { return }
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

        func handle(_ key: ListKey) {
            guard let grid else { return }
            switch key {
            case .preview: grid.preview.toggle()
            case .open:    parent.model.activate(grid.selectionIndexPaths.map { items[$0.item].url })
            case .goUp:    parent.model.goUp()
            case .tab(let backward): parent.events.tab(backward)
            case .escape:  parent.events.escape()
            }
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
                icon.configure(items[indexPath.item])
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
            grid.preview.refresh()
        }

        // MARK: 끌기 (여러 파일 가능)

        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>,
                            with event: NSEvent) -> Bool { true }

        func collectionView(_ collectionView: NSCollectionView,
                            pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
            guard indexPath.item < items.count else { return nil }
            return items[indexPath.item].url as NSURL
        }

        // MARK: 놓기 (항상 이 칸의 현재 폴더로 복사)

        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
                            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            // 같은 칸 안에서 끌어 놓는 것은 아무 일도 하지 않음
            if let source = draggingInfo.draggingSource as? NSCollectionView, source === collectionView {
                grid?.isDropHighlighted = false
                return []
            }
            guard !draggedFileURLs(draggingInfo).isEmpty else { return [] }
            // 특정 아이콘 "위"가 아니라 목록 끝에 놓는 것으로 처리 (폴더 안으로 들어가지 않음)
            proposedDropIndexPath.pointee = NSIndexPath(forItem: items.count, inSection: 0)
            proposedDropOperation.pointee = .before
            grid?.isDropHighlighted = true
            return .copy
        }

        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo,
                            indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            grid?.isDropHighlighted = false
            let urls = draggedFileURLs(draggingInfo)
            guard !urls.isEmpty else { return false }
            parent.model.copyIn(urls)
            return true
        }
    }
}

// MARK: - 아이콘 하나 (아이콘 + 이름 두 줄)

final class IconItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("IconItem")

    private let iconBackground = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

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
            iconBackground.widthAnchor.constraint(equalToConstant: 56),
            iconBackground.heightAnchor.constraint(equalToConstant: 56),
            icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            label.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 3),
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -2),
        ])

        view = root
        imageView = icon
        textField = label
        updateLook()
    }

    func configure(_ item: FileItem) {
        icon.image = NSWorkspace.shared.icon(forFile: item.url.path)
        label.stringValue = item.name
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
    let preview = PreviewController()

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
        preview.keyTarget = self
        if isActivePane { takeFocus() }
    }

    private func takeFocus() {
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

    // 훑어보기 창 연결
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { preview.begin(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { preview.end(panel) }
}
