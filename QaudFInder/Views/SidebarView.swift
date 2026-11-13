//
//  SidebarView.swift
//  QuadFinder — 왼쪽 사이드바 (즐겨찾기)
//
//  - 항목 클릭: 활성 칸이 그 폴더로 이동
//  - 항목을 칸에 끌어다 놓기: 그 칸이 그 폴더로 이동 (복사 아님)
//  - 칸·Finder의 폴더를 사이드바에 끌어다 놓기: 즐겨찾기에 추가
//  - 사이드바 안에서 끌기: 순서 변경
//  - 우클릭: "사이드바에서 제거"
//

import SwiftUI
import AppKit

struct SidebarView: View {
    @ObservedObject var sidebar = SidebarModel.shared
    @ObservedObject var activePane: PaneModel   // 활성 칸 (그 칸의 폴더와 같은 항목을 강조)
    var onOpen: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("즐겨찾기")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)
            SidebarTable(favorites: sidebar.favorites, activeURL: activePane.currentURL, onOpen: onOpen)
        }
    }
}

// MARK: - AppKit 표로 만든 즐겨찾기 목록

private struct SidebarTable: NSViewRepresentable {
    var favorites: [URL]
    var activeURL: URL
    var onOpen: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = NSTableView()
        c.table = table

        table.style = .sourceList
        table.headerView = nil
        table.backgroundColor = .clear
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.focusRingType = .none
        let column = NSTableColumn(identifier: .init("favorite"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        table.dataSource = c
        table.delegate = c
        table.target = c
        table.action = #selector(Coordinator.clicked(_:))

        // 끌기: 앱 안(칸·사이드바)으로만. Finder로는 끌려 나가지 않음
        table.setDraggingSourceOperationMask(.every, forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        // 놓기: 폴더 추가(.fileURL), 순서 바꾸기(.quadSidebarRow)
        table.registerForDraggedTypes([.fileURL, .quadSidebarRow])
        table.draggingDestinationFeedbackStyle = .gap

        // 우클릭 메뉴
        let menu = NSMenu()
        menu.delegate = c
        table.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        c.apply()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: SidebarTable
        weak var table: NSTableView?
        private var shown: [URL] = []

        init(_ parent: SidebarTable) {
            self.parent = parent
        }

        func apply() {
            guard let table else { return }
            if shown != parent.favorites {
                shown = parent.favorites
                table.reloadData()
            }
            // 활성 칸의 폴더와 같은 항목을 선택 표시
            let row = shown.firstIndex { SidebarModel.samePath($0, parent.activeURL) }
            let wanted = row.map { IndexSet(integer: $0) } ?? IndexSet()
            if table.selectedRowIndexes != wanted {
                table.selectRowIndexes(wanted, byExtendingSelection: false)
            }
        }

        @objc func clicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < shown.count else { return }
            parent.onOpen(shown[row])
        }

        // MARK: 보여 줄 내용

        func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("favoriteCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? Self.makeCell(id)
            let url = shown[row]
            cell.textField?.stringValue = FileManager.default.displayName(atPath: url.path)
            cell.imageView?.image = Self.symbol(for: url)
            cell.toolTip = url.path
            return cell
        }

        private static func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id
            let icon = NSImageView()
            icon.contentTintColor = .controlAccentColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            cell.addSubview(text)
            cell.imageView = icon
            cell.textField = text
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        // 잘 알려진 폴더는 Finder 사이드바처럼 SF Symbol, 나머지는 폴더 모양
        private static func symbol(for url: URL) -> NSImage? {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let name: String
            switch url.standardizedFileURL.path {
            case home.appendingPathComponent("Desktop").path:   name = "menubar.dock.rectangle"
            case home.appendingPathComponent("Documents").path: name = "doc"
            case home.appendingPathComponent("Downloads").path: name = "arrow.down.circle"
            case home.standardizedFileURL.path:                 name = "house"
            case "/Applications":                               name = "app.dashed"
            default:                                            name = "folder"
            }
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        }

        // MARK: 끌기 (칸에 놓으면 그 칸이 이 폴더로 이동)

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < shown.count else { return nil }
            let item = NSPasteboardItem()
            item.setString(shown[row].path, forType: .quadFolder)
            item.setString(String(row), forType: .quadSidebarRow)
            return item
        }

        // MARK: 놓기 (순서 바꾸기 / 폴더 추가)

        func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo,
                       proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            // 항목 "위"가 아니라 항목 "사이"에 끼워 넣기
            if dropOperation == .on { tableView.setDropRow(row, dropOperation: .above) }

            if info.draggingPasteboard.string(forType: .quadSidebarRow) != nil {
                return .move
            }
            let folders = draggedFileURLs(info).filter { SidebarModel.isFolder($0) }
            guard !folders.isEmpty else { return [] }
            let mask = info.draggingSourceOperationMask
            return mask.contains(.copy) ? .copy : (mask.contains(.link) ? .link : .generic)
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo,
                       row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            let model = SidebarModel.shared
            if let text = info.draggingPasteboard.string(forType: .quadSidebarRow), let from = Int(text) {
                model.move(from: from, to: row)
                return true
            }
            let folders = draggedFileURLs(info).filter { SidebarModel.isFolder($0) }
            guard !folders.isEmpty else { return false }
            model.add(folders, at: row)
            return true
        }

        // MARK: 우클릭 메뉴

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, table.clickedRow >= 0, table.clickedRow < shown.count else { return }
            let item = NSMenuItem(title: "사이드바에서 제거", action: #selector(removeClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = table.clickedRow
            menu.addItem(item)
        }

        @objc private func removeClicked(_ sender: NSMenuItem) {
            SidebarModel.shared.remove(at: sender.tag)
        }
    }
}
