//
//  ContentView.swift
//  QuadFinder — 한 창에 폴더 4개를 띄우는 가벼운 파일 탐색기
//  전체 창: 2×2 칸 배치와 칸 병합 / 병합 해제
//

import SwiftUI
import AppKit

// MARK: - 병합할 수 있는 칸 짝
// 칸 번호:  0 | 1
//          ---+---
//           2 | 3

struct PanePair: Hashable {
    let a: Int   // 항상 작은 번호 (병합 후 남는 칸)
    let b: Int   // 항상 큰 번호 (병합 후 숨겨지는 칸)

    init(_ x: Int, _ y: Int) {
        a = min(x, y)
        b = max(x, y)
    }

    static let adjacent: [PanePair] = [PanePair(0, 1), PanePair(2, 3), PanePair(0, 2), PanePair(1, 3)]

    var isHorizontal: Bool { (a == 0 && b == 1) || (a == 2 && b == 3) }   // 좌우로 붙은 짝
}

// MARK: - 전체 창

private func homeFolder(_ sub: String) -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return sub.isEmpty ? home : home.appendingPathComponent(sub)
}

struct ContentView: View {
    @StateObject private var pane0 = PaneModel(index: 0, defaultURL: homeFolder("Desktop"))
    @StateObject private var pane1 = PaneModel(index: 1, defaultURL: homeFolder("Documents"))
    @StateObject private var pane2 = PaneModel(index: 2, defaultURL: homeFolder("Downloads"))
    @StateObject private var pane3 = PaneModel(index: 3, defaultURL: homeFolder(""))

    @State private var merges: Set<PanePair> = []        // 현재 병합된 짝들
    @State private var mergeSelection: [Int] = []         // ⌘ 클릭으로 고른 칸 (최대 2개)
    @State private var paneFrames: [Int: CGRect] = [:]    // 각 칸의 화면 위치 ("병합하기" 버튼 위치 계산용)
    @State private var hint: String? = nil                // 아래쪽 안내 문구
    @State private var activePane = 0                     // 키보드로 다루는 칸 (Tab으로 이동)

    var body: some View {
        ZStack {
            grid

            // 두 칸이 선택되면: 아무 데나 누르면 취소되는 투명 막 + 가운데 "병합하기" 버튼
            if mergeSelection.count == 2, let rect = selectionRect {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { mergeSelection = [] }

                Button { performMerge() } label: {
                    Label("병합하기", systemImage: "arrow.triangle.merge")
                        .font(.headline)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .shadow(radius: 8)
                .position(x: rect.midX, y: rect.midY)
            }

            if let hint {
                Text(hint)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(.named("grid"))
        .onExitCommand { mergeSelection = [] }     // esc 키로도 취소
        .onChange(of: merges) { _, _ in
            // 활성 칸이 병합으로 숨겨지면 남는 칸으로 옮김
            if let pair = merges.first(where: { $0.b == activePane }) { activePane = pair.a }
        }
        .frame(minWidth: 600, minHeight: 450)
    }

    // MARK: 칸 배치
    // 세로 병합(위아래)이 있으면 "왼쪽 열 | 오른쪽 열" 구조,
    // 그 외에는 "위쪽 줄 / 아래쪽 줄" 구조로 그립니다.

    @ViewBuilder
    private var grid: some View {
        if merges.contains(where: { !$0.isHorizontal }) {
            HSplitView {
                column(top: 0, bottom: 2)
                column(top: 1, bottom: 3)
            }
        } else {
            VSplitView {
                row(left: 0, right: 1)
                row(left: 2, right: 3)
            }
        }
    }

    @ViewBuilder
    private func row(left: Int, right: Int) -> some View {
        if merges.contains(PanePair(left, right)) {
            paneView(left)
        } else {
            HSplitView {
                paneView(left)
                paneView(right)
            }
        }
    }

    @ViewBuilder
    private func column(top: Int, bottom: Int) -> some View {
        if merges.contains(PanePair(top, bottom)) {
            paneView(top)
        } else {
            VSplitView {
                paneView(top)
                paneView(bottom)
            }
        }
    }

    private func model(_ i: Int) -> PaneModel {
        switch i {
        case 0: return pane0
        case 1: return pane1
        case 2: return pane2
        default: return pane3
        }
    }

    private func paneView(_ i: Int) -> some View {
        PaneView(
            model: model(i),
            isMergeSelected: mergeSelection.contains(i),
            isMerged: merges.contains(where: { $0.a == i }),
            isActive: activePane == i,
            onCmdClick: { cmdClick(i) },
            onPlainClick: {
                if !mergeSelection.isEmpty { mergeSelection = [] }
                activePane = i
            },
            onCmdDragEnd: { point in cmdDrag(from: i, to: point) },
            onUnmerge: { unmerge(i) },
            onActivate: { if activePane != i { activePane = i } },
            onTab: { backward in moveActivePane(from: i, backward: backward) },
            onEscape: { mergeSelection = [] }
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("grid"))
        } action: { frame in
            paneFrames[i] = frame
        }
    }

    // MARK: 활성 칸 이동 (Tab: 0 → 1 → 2 → 3 → 0, ⇧Tab: 반대, 숨겨진 칸은 건너뜀)

    private func moveActivePane(from i: Int, backward: Bool) {
        let order = visiblePanes
        guard let pos = order.firstIndex(of: i), order.count > 1 else { return }
        let next = backward ? (pos - 1 + order.count) % order.count : (pos + 1) % order.count
        activePane = order[next]
    }

    // MARK: 병합 로직

    private func isInMerge(_ i: Int) -> Bool {
        merges.contains(where: { $0.a == i || $0.b == i })
    }

    private var visiblePanes: [Int] {
        (0..<4).filter { i in !merges.contains(where: { $0.b == i }) }
    }

    private var selectionRect: CGRect? {
        guard mergeSelection.count == 2,
              let r1 = paneFrames[mergeSelection[0]],
              let r2 = paneFrames[mergeSelection[1]] else { return nil }
        return r1.union(r2)
    }

    private func cmdClick(_ i: Int) {
        if isInMerge(i) {
            mergeSelection = []
            showHint("이미 병합된 칸입니다. 병합을 먼저 해제하세요.")
            return
        }
        if mergeSelection.isEmpty || mergeSelection.count == 2 {
            mergeSelection = [i]
            return
        }
        let first = mergeSelection[0]
        if first == i {
            mergeSelection = []          // 같은 칸을 다시 ⌘ 클릭하면 선택 해제
            return
        }
        let pair = PanePair(first, i)
        guard PanePair.adjacent.contains(pair) else {
            mergeSelection = [i]
            showHint("상하 또는 좌우로 붙어 있는 칸만 병합할 수 있습니다.")
            return
        }
        guard model(first).currentURL.path == model(i).currentURL.path else {
            mergeSelection = [i]
            showHint("두 칸이 같은 폴더를 보고 있을 때만 병합할 수 있습니다.")
            return
        }
        mergeSelection = [first, i]
    }

    private func cmdDrag(from i: Int, to point: CGPoint) {
        guard let j = visiblePanes.first(where: { $0 != i && (paneFrames[$0]?.contains(point) ?? false) }) else { return }
        mergeSelection = []
        cmdClick(i)
        if mergeSelection == [i] {
            cmdClick(j)
        }
    }

    private func performMerge() {
        guard mergeSelection.count == 2 else { return }
        merges.insert(PanePair(mergeSelection[0], mergeSelection[1]))
        mergeSelection = []
    }

    private func unmerge(_ i: Int) {
        merges = merges.filter { $0.a != i }
    }

    private func showHint(_ text: String) {
        hint = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if hint == text { hint = nil }
        }
    }
}

#Preview {
    ContentView()
}
