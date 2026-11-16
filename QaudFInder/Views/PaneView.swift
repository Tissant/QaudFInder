//
//  PaneView.swift
//  QuadFinder — 칸 하나의 화면: 위쪽 막대, 파일 목록, 경로 막대, 상태줄
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 칸 하나의 화면

struct PaneView: View {
    @ObservedObject var model: PaneModel
    var isMergeSelected: Bool              // 병합하려고 ⌘ 클릭으로 고른 칸인지 (파란 테두리)
    var isMerged: Bool                     // 병합된 칸인지 (병합 해제 버튼 표시)
    var isActive: Bool                     // 지금 키보드로 다루는 칸인지 (강조색 테두리)
    var onCmdClick: () -> Void
    var onPlainClick: () -> Void           // 칸을 그냥 클릭 → 병합 선택 취소 + 활성 칸으로
    var onCmdDragEnd: (CGPoint) -> Void
    var onUnmerge: () -> Void
    var onActivate: () -> Void             // 목록이 키보드 입력을 받게 됨
    var onTab: (_ backward: Bool) -> Void  // Tab / ⇧Tab
    var onEscape: () -> Void

    @State private var isDropTarget = false
    @State private var showIconSize = false     // 아이콘 크기 슬라이더 창

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let msg = model.errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(4)
            }

            fileArea

            Divider()
            pathBar
            statusBar
        }
        // 파일을 끌고 이 칸 위에 왔을 때 테두리
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor, lineWidth: isDropTarget ? 2 : 0)
                .allowsHitTesting(false)
        }
        // 활성 칸 표시: 얇은 강조색 테두리
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor.opacity(0.7), lineWidth: isActive ? 2 : 0)
                .allowsHitTesting(false)
        }
        // 병합하려고 선택된 칸의 파란 테두리
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.blue, lineWidth: isMergeSelected ? 3 : 0)
                .allowsHitTesting(false)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget) { providers in
            let target = model
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        target.copyIn([url])
                    }
                }
            }
            return true
        }
        .frame(minWidth: 260, minHeight: 200)
    }

    // MARK: 파일 목록 (리스트 / 아이콘)
    // 둘 다 AppKit 부품입니다: FileTableView.swift, FileGridView.swift
    // 훑어보기(스페이스)도 각 목록이 직접 처리합니다.

    @ViewBuilder
    private var fileArea: some View {
        let events = ListEvents(
            mouseDown: { onPlainClick() },
            becameActive: { onActivate() },
            tab: { backward in onTab(backward) },
            escape: { onEscape() }
        )
        if model.viewMode == .list {
            FileTableView(model: model, isActive: isActive, events: events)
        } else {
            FileGridView(model: model, isActive: isActive, events: events)
        }
    }

    // MARK: 위쪽 막대
    // ‹ › ↑  /Users/tissant/Desktop      [아이콘|리스트] ⟳ (병합 해제)
    // 이 막대를 ⌘ 클릭(또는 ⌘ 드래그)하면 병합할 칸을 고를 수 있습니다.

    private var header: some View {
        HStack(spacing: 8) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack)
                .help("뒤로")
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward)
                .help("앞으로")
            Button { model.goUp() } label: { Image(systemName: "arrow.up") }
                .help("상위 폴더")

            Text(model.currentURL.path)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 0)

            // 보기 방식 전환 (Finder처럼 아이콘만)
            // 보기 방식 전환 [아이콘|리스트] — ⌘ 누른 채 아이콘 버튼을 누르면 아이콘 크기 슬라이더
            HStack(spacing: 2) {
                viewModeButton(.icon, symbol: "square.grid.2x2",
                               help: "아이콘 보기 (⌘ 누른 채 클릭: 아이콘 크기 조절)")
                    .popover(isPresented: $showIconSize, arrowEdge: .bottom) {
                        IconSizePopover(scale: $model.iconScale) { showIconSize = false }
                    }
                viewModeButton(.list, symbol: "list.bullet", help: "리스트 보기")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))

            Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                .help("새로고침")

            if isMerged {
                Button { onUnmerge() } label: {
                    // 끊어진 링크 모양: 링크 아이콘 위에 빨간 사선
                    Image(systemName: "link")
                        .overlay(
                            Image(systemName: "line.diagonal")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.red)
                        )
                }
                .help("병합 해제")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isMergeSelected ? Color.blue.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                onCmdClick()
            } else {
                onPlainClick()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named("grid"))
                .onEnded { value in
                    if NSEvent.modifierFlags.contains(.command) {
                        onCmdDragEnd(value.location)
                    }
                }
        )
    }

    // 보기 방식 버튼 하나 (선택된 쪽은 강조색 바탕에 흰 아이콘)
    private func viewModeButton(_ mode: ViewMode, symbol: String, help: String) -> some View {
        let selected = model.viewMode == mode
        return Button {
            if mode == .icon && NSEvent.modifierFlags.contains(.command) {
                model.viewMode = .icon
                showIconSize = true
            } else {
                model.viewMode = mode
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 28, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: 아래쪽 경로 막대: Macintosh HD › 사용자 › tissant › 데스크탑

    private var pathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.pathComponents.enumerated()), id: \.offset) { i, url in
                    if i > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button { model.open(url) } label: {
                        HStack(spacing: 3) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(FileManager.default.displayName(atPath: url.path))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // 맨 아래: 2개의 항목, 3.2GB (이 폴더가 차지하는 용량, 하위 폴더 포함)
    private var statusBar: some View {
        Text("\(model.items.count)개의 항목"
             + (model.folderSizeText.isEmpty ? "" : ", \(model.folderSizeText)")
             + (model.showHidden ? " · 숨김 파일 표시 중" : ""))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
    }
}
