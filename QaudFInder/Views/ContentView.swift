//
//  ContentView.swift
//  QuadFinder — 한 창에 여러 폴더를 띄우는 가벼운 파일 탐색기
//  전체 창: 왼쪽 사이드바(접기/펼치기) + 칸 배치(최대 6칸, 자유 분할)
//
//  칸 나누기·합치기 (1.2.0):
//  - 활성 칸(또는 ⌘로 고른 칸)의 위쪽 막대를 ⌘+클릭 → 그 칸 왼쪽 위에 「좌우로 분할 / 상하로 분할」 버튼
//  - 활성 칸과 붙은 다른 칸을 ⌘+클릭 → 바로 「병합하기」 버튼 (합치면 직사각형이 되는 두 칸, 폴더가 달라도 됨)
//  - 합칠 수 없는 칸을 ⌘+클릭하면 아무 반응 없음
//  - 남는 칸은 왼쪽/위쪽 칸. 버튼 밖을 누르거나 esc → 취소
//

import SwiftUI
import AppKit
import Combine

private func homeFolder(_ sub: String) -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return sub.isEmpty ? home : home.appendingPathComponent(sub)
}

// MARK: - 창 하나의 칸들
// 첫 번째 창: 지난번 상태(폴더·보기 방식·정렬 등)를 복원하고 저장함.
// ⌘N으로 더 연 창: 설정의 시작 배열·칸별 시작 폴더로 시작하고 저장하지 않음.
// 첫 번째 창을 닫으면, 그다음에 여는 창이 "첫 번째 창" 역할을 이어받음.

@MainActor
final class WindowPanes: ObservableObject {
    private static var rememberingWindowOpen = false
    private static let layoutKey = "layout.tree"
    let remembers: Bool
    @Published private(set) var layout: PaneLayout {
        didSet { if remembers && layout != oldValue { Self.saveLayout(layout) } }
    }
    @Published private(set) var panes: [Int: PaneModel] = [:]

    // 시작 배치
    // - 첫 번째 창 + "지난번 배치 그대로": 저장한 나눈 모양과 칸별 폴더 (없으면 아래 배열로)
    // - 첫 번째 창 + "이 배열로 시작": 설정의 가로×세로 배열 + 칸별 시작 폴더 (보기 방식·정렬은 기억)
    // - ⌘N으로 연 창: 설정의 배열 + 칸별 시작 폴더, 저장 안 함
    init() {
        let first = !Self.rememberingWindowOpen
        if first { Self.rememberingWindowOpen = true }
        remembers = first
        let settings = AppSettings.shared
        let grid = PaneLayout.grid(columns: settings.startColumns, rows: settings.startRows)
        let restore = first && !settings.startWithGrid
        layout = (restore ? Self.loadLayout() : nil) ?? grid
        for id in layout.paneIDs {
            panes[id] = PaneModel(index: id, defaultURL: Self.startFolder(id), remembers: first, useSavedFolder: restore)
        }
        if first { Self.saveLayout(layout) }
    }

    // 칸별 시작 폴더 (설정). 없어진 폴더면 기본 폴더
    private static func startFolder(_ id: Int) -> URL {
        let folders = AppSettings.shared.startFolders
        if id < folders.count {
            let url = URL(fileURLWithPath: folders[id])
            if SidebarModel.isFolder(url) { return url }
        }
        let fallback = [homeFolder("Desktop"), homeFolder("Documents"), homeFolder("Downloads")]
        return id < fallback.count ? fallback[id] : homeFolder("")
    }

    // 저장한 배치 읽기. 깨져 있으면 지우지 않고 "layout.tree.broken"으로 옮겨 두고 nil
    private static func loadLayout() -> PaneLayout? {
        let store = UserDefaults.standard
        guard let data = store.data(forKey: layoutKey) else { return nil }   // 처음 켬(1.1.0에서 올라옴) → 배열로
        if let layout = try? JSONDecoder().decode(PaneLayout.self, from: data), layout.version == 1, layout.isValid {
            return layout
        }
        store.set(data, forKey: layoutKey + ".broken")
        store.removeObject(forKey: layoutKey)
        return nil
    }

    private static func saveLayout(_ layout: PaneLayout) {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: layoutKey)
        }
    }

    // 활성 칸만 폴더 용량을 계산하도록 알려 줌
    func setActive(_ id: Int) {
        for (i, pane) in panes { pane.isActivePane = (i == id) }
    }

    func model(_ id: Int) -> PaneModel {
        panes[id] ?? panes[layout.paneIDs[0]]!
    }

    // 칸 id를 나눔. 새 칸은 같은 폴더·보기 방식으로 오른쪽/아래쪽에
    func split(_ id: Int, _ axis: SplitAxis, paneRect: CGRect) -> Result<Int, PaneLayout.SplitProblem> {
        var next = layout
        let result = next.split(id, axis, paneRect: paneRect)
        if case .success(let newID) = result {
            let source = model(id)
            if remembers { PaneModel.forgetSaved(newID) }
            let pane = PaneModel(index: newID, defaultURL: source.currentURL, remembers: remembers)
            pane.copyViewSettings(from: source)
            panes[newID] = pane
            layout = next
        }
        return result
    }

    // 두 칸을 합침. 남는 칸·사라진 칸을 돌려줌 (합칠 수 없으면 nil)
    func merge(_ a: Int, _ b: Int) -> (keep: Int, remove: Int)? {
        var next = layout
        guard let plan = next.merge(a, b) else { return nil }
        layout = next
        panes[plan.remove]?.stopWatching()
        panes[plan.remove] = nil
        if remembers { PaneModel.forgetSaved(plan.remove) }
        return plan
    }

    func moveDivider(_ d: LayoutDivider, to point: CGPoint) {
        layout.moveDivider(d, to: point)
    }

    func windowClosed() {
        panes.values.forEach { $0.stopWatching() }
        if remembers { Self.rememberingWindowOpen = false }
    }
}

struct ContentView: View {
    @StateObject private var window = WindowPanes()

    @State private var selection: [Int] = []              // ⌘ 클릭으로 고른 칸 (1개 = 나누기, 2개 = 합치기)
    @State private var areaSize: CGSize = .zero           // 칸 영역 크기
    @State private var hint: String? = nil                // 아래쪽 안내 문구
    @State private var activePane = 0                     // 키보드로 다루는 칸 (Tab으로 이동)
    // 사이드바 접힘 상태 (앱을 다시 켜도 기억)
    @State private var sidebarVisibility: NavigationSplitViewVisibility =
        UserDefaults.standard.bool(forKey: "sidebar.collapsed") ? .detailOnly : .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView(activePane: window.model(activePane)) { url in
                let pane = window.model(activePane)
                pane.open(url)
                pane.requestFocus()               // 사이드바를 누른 뒤에도 바로 키보드로 칸을 다루도록
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 280)
        } detail: {
            paneArea
                .toolbar {
                    // 오른쪽 위 설정 버튼 (앱 메뉴 "설정…" ⌘, 와 같음)
                    ToolbarItem {
                        SettingsLink {
                            Image(systemName: "gearshape")
                        }
                        .help("설정 (⌘,)")
                    }
                }
        }
        .onChange(of: sidebarVisibility) { _, visibility in
            if window.remembers {
                UserDefaults.standard.set(visibility == .detailOnly, forKey: "sidebar.collapsed")
            }
        }
        .onDisappear { window.windowClosed() }     // 창을 닫을 때
        // 활성 칸이 배치에 없으면(지난번 배치를 불러왔을 때 등) 왼쪽 위 칸으로
        .onAppear {
            if window.panes[activePane] == nil, let first = window.layout.readingOrder.first { activePane = first }
            window.setActive(activePane)
        }
        .onChange(of: activePane) { _, id in window.setActive(id) }
        // 메뉴 막대 "이동 > 폴더로 이동…"(⇧⌘G)이 이 창의 활성 칸 경로 입력칸을 열도록
        .focusedSceneValue(\.goToFolder, GoToFolderAction { window.model(activePane).requestPathEdit() })
        // 즐겨찾기를 정리했으면 아래쪽에 잠깐 안내
        .onReceive(SidebarModel.shared.$notice.compactMap { $0 }) { text in
            showHint(text)
        }
    }

    // MARK: 칸 배치 + 나누기/합치기 버튼 + 안내 문구

    private var rects: [Int: CGRect] {
        window.layout.rects(in: CGRect(origin: .zero, size: areaSize))
    }

    private var paneArea: some View {
        ZStack(alignment: .topLeading) {
            // GeometryReader: 창 크기가 줄어들 때도 칸 영역이 함께 줄도록 (칸 크기가 바깥 크기를 붙잡지 않게)
            GeometryReader { geo in
                PaneLayoutView(layout: window.layout, size: geo.size,
                               onMoveDivider: { d, p in window.moveDivider(d, to: p) }) { id in
                    paneView(id)
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { areaSize = $0 }

            // 두 칸이 선택되면: 아무 데나 누르면 취소되는 투명 막
            if selection.count == 2 {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = [] }
            }

            // 나누기/합치기 버튼: 고른 칸(합칠 때는 남는 칸)의 왼쪽 위, 위쪽 막대 바로 아래
            if let target = buttonPane, let r = rects[target] {
                actionButtons
                    .offset(x: r.minX + 8, y: r.minY + 38)
            }

            // 복사·이동 진행률 (오른쪽 아래)
            CopyProgressBar()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16)
                .padding(.bottom, 36)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(.named("grid"))
        .onExitCommand { selection = [] }     // esc 키로도 취소
        .frame(minWidth: max(600, window.layout.minimumSize.width),
               minHeight: max(450, window.layout.minimumSize.height))
    }

    // 버튼을 띄울 칸: 1개 고름 → 그 칸, 2개 고름 → 합친 뒤 남는 칸(왼쪽/위쪽)
    private var buttonPane: Int? {
        switch selection.count {
        case 1: return selection[0]
        case 2: return window.layout.mergePlan(selection[0], selection[1])?.keep
        default: return nil
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if selection.count == 2 {
            Button { performMerge() } label: {
                Label("병합하기", systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            HStack(spacing: 6) {
                Button { performSplit(.horizontal) } label: {
                    Label("좌우로 분할", systemImage: "rectangle.split.2x1")
                }
                Button { performSplit(.vertical) } label: {
                    Label("상하로 분할", systemImage: "rectangle.split.1x2")
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(window.layout.isFull)
            .help(window.layout.isFull ? "칸은 6개까지예요" : "")
        }
    }

    private func paneView(_ i: Int) -> some View {
        PaneView(
            model: window.model(i),
            isMergeSelected: selection.contains(i),
            isActive: activePane == i,
            onCmdClick: { cmdClick(i) },
            onPlainClick: {
                if !selection.isEmpty { selection = [] }
                activePane = i
            },
            onCmdDragEnd: { point in cmdDrag(from: i, to: point) },
            onActivate: { if activePane != i { activePane = i } },
            onTab: { backward in moveActivePane(from: i, backward: backward) },
            onEscape: { selection = [] }
        )
        .id(i)
    }

    // MARK: 활성 칸 이동 (Tab: 왼쪽 위 → 오른쪽 아래, ⇧Tab: 반대)

    private func moveActivePane(from i: Int, backward: Bool) {
        let order = window.layout.readingOrder
        guard let pos = order.firstIndex(of: i), order.count > 1 else { return }
        let next = backward ? (pos - 1 + order.count) % order.count : (pos + 1) % order.count
        activePane = order[next]
    }

    // MARK: 나누기·합치기

    // ⌘+클릭 기준 칸: 이미 ⌘로 고른 칸이 있으면 그 칸, 없으면 지금 활성 칸(강조색 테두리)
    // - 기준 칸 자신을 ⌘+클릭 → 나누기 버튼 (한 번 더 누르면 취소)
    // - 기준 칸과 합칠 수 있는 칸을 ⌘+클릭 → 바로 병합하기 버튼
    // - 합칠 수 없는 칸(붙어 있지 않음 등)을 ⌘+클릭 → 아무 반응 없음
    private func cmdClick(_ i: Int) {
        let base = selection.count == 1 ? selection[0] : activePane
        if i == base {
            selection = selection == [i] ? [] : [i]
            return
        }
        if window.layout.mergePlan(base, i) != nil {
            selection = [base, i]
        }
    }

    // ⌘+드래그: 끌기 시작한 칸과 놓은 칸을 합칠 수 있으면 병합하기 버튼
    private func cmdDrag(from i: Int, to point: CGPoint) {
        guard let j = rects.first(where: { $0.key != i && $0.value.contains(point) })?.key,
              window.layout.mergePlan(i, j) != nil else { return }
        selection = [i, j]
    }

    private func performSplit(_ axis: SplitAxis) {
        guard selection.count == 1, let rect = rects[selection[0]] else { return }
        switch window.split(selection[0], axis, paneRect: rect) {
        case .success:
            selection = []
        case .failure(.tooSmall):
            showHint("칸이 좁아서 나눌 수 없어요. 창을 넓혀 주세요.")
        case .failure(.full):
            showHint("칸은 6개까지예요.")
        case .failure(.notFound):
            selection = []
        }
    }

    private func performMerge() {
        guard selection.count == 2 else { return }
        if let plan = window.merge(selection[0], selection[1]), activePane == plan.remove {
            activePane = plan.keep           // 활성 칸이 사라지면 남는 칸으로
        }
        selection = []
    }

    func showHint(_ text: String) {
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

// MARK: - 메뉴 막대 "이동 > 폴더로 이동…" (⇧⌘G) 연결

struct GoToFolderAction {
    let run: () -> Void
}

extension FocusedValues {
    @Entry var goToFolder: GoToFolderAction? = nil
}
