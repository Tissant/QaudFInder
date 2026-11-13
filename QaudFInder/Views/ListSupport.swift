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

// MARK: - 목록에서 일어난 일을 바깥(PaneView/ContentView)으로 알리는 통로

struct ListEvents {
    var mouseDown: () -> Void                 // 목록을 클릭함 (병합 선택 취소 + 활성 칸으로)
    var becameActive: () -> Void              // 목록이 키보드 입력을 받게 됨 → 활성 칸
    var tab: (_ backward: Bool) -> Void       // Tab / ⇧Tab → 다음·이전 칸
    var escape: () -> Void                    // esc → 병합 선택 취소
}

// MARK: - 단축키

enum ListKey {
    case preview          // 스페이스
    case open             // Return, 숫자패드 Enter, ⌘↓
    case goUp             // ⌘↑
    case tab(backward: Bool)
    case escape

    init?(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch event.keyCode {
        case 49 where flags.isEmpty:                 self = .preview
        case 36, 76:                                 self = .open
        case 125 where flags == .command:            self = .open
        case 126 where flags == .command:            self = .goUp
        case 48 where flags.isEmpty:                 self = .tab(backward: false)
        case 48 where flags == .shift:               self = .tab(backward: true)
        case 53:                                     self = .escape
        default: return nil
        }
    }

    // 훑어보기 창이 떠 있을 때 목록으로 넘길 방향키(←→↑↓, ⇧ 포함)
    static func isArrow(_ event: NSEvent) -> Bool {
        [123, 124, 125, 126].contains(event.keyCode)
            && !event.modifierFlags.contains(.command)
    }
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

    // 선택이 바뀌었을 때 창이 떠 있으면 새 파일로 바꿔 보여 줌
    func refresh() {
        guard isControlling, QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        if model?.previewTarget == nil {
            panel.orderOut(nil)
        } else {
            panel.reloadData()
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
