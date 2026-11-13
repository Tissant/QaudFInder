//
//  ContentView.swift
//  QuadFinder — 한 창에 폴더 4개를 띄우는 가벼운 파일 탐색기
//
//  v2 변경 사항
//  - [수정] 파일을 다른 칸으로 끌어다 놓기(드래그 앤 드롭)
//  - [추가] 칸별 보기 방식 전환 (아이콘 / 리스트)
//  - [추가] 훑어보기(Quick Look): 파일 선택 후 스페이스
//  - [추가] 칸 병합 / 병합 해제
//
//  이 파일 하나에 앱 화면 전체가 들어 있습니다.
//  Xcode에서 기존 ContentView.swift 내용을 전부 지우고 이 내용으로 바꾸세요.
//

import SwiftUI
import AppKit
import Combine
import QuickLook
import UniformTypeIdentifiers

// MARK: - 보기 방식

enum ViewMode: String {
    case list
    case icon
}

// MARK: - 파일/폴더 한 개의 정보

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool   // 들어갈 수 있는 폴더인지 (.app 같은 패키지는 파일로 취급)
    let size: Int64?        // 폴더는 nil
    let modified: Date?
    var id: URL { url }
}

// MARK: - 칸(패널) 하나의 상태: 현재 폴더, 파일 목록, 선택, 뒤로/앞으로 기록

@MainActor
final class PaneModel: ObservableObject {
    let index: Int
    @Published private(set) var currentURL: URL
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var freeSpaceText: String = ""
    @Published var errorMessage: String? = nil
    @Published var selection = Set<URL>()
    @Published var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "pane\(index).viewMode") }
    }

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var anchor: URL? = nil          // 마지막으로 클릭한 파일 (Shift 범위 선택, 훑어보기 대상)

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    init(index: Int, defaultURL: URL) {
        self.index = index

        // 지난번에 열어 둔 폴더가 있으면 그 폴더로 시작
        var start = defaultURL
        if let saved = UserDefaults.standard.string(forKey: "pane\(index).path") {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: saved, isDirectory: &isDir), isDir.boolValue {
                start = URL(fileURLWithPath: saved)
            }
        }
        _currentURL = Published(initialValue: start)

        // 지난번 보기 방식 기억
        let savedMode = UserDefaults.standard.string(forKey: "pane\(index).viewMode")
            .flatMap { ViewMode(rawValue: $0) } ?? .list
        _viewMode = Published(initialValue: savedMode)

        reload()
    }

    // MARK: 이동

    func open(_ url: URL) {
        guard url.standardizedFileURL.path != currentURL.standardizedFileURL.path else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        setCurrent(url)
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        setCurrent(prev)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        setCurrent(next)
    }

    func goUp() {
        guard currentURL.standardizedFileURL.path != "/" else { return }
        open(currentURL.deletingLastPathComponent())
    }

    private func setCurrent(_ url: URL) {
        currentURL = url.standardizedFileURL
        selection.removeAll()
        anchor = nil
        UserDefaults.standard.set(currentURL.path, forKey: "pane\(index).path")
        reload()
    }

    // MARK: 선택 (Finder와 같은 규칙)
    // 그냥 클릭: 하나만 선택 / ⌘ 클릭: 추가·해제 / ⇧ 클릭: 범위 선택

    func click(_ item: FileItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(item.url) {
                selection.remove(item.url)
            } else {
                selection.insert(item.url)
            }
            anchor = item.url
        } else if flags.contains(.shift),
                  let anchor,
                  let from = items.firstIndex(where: { $0.url == anchor }),
                  let to = items.firstIndex(where: { $0.url == item.url }) {
            let range = min(from, to)...max(from, to)
            selection = Set(items[range].map { $0.url })
        } else {
            selection = [item.url]
            anchor = item.url
        }
    }

    // 훑어보기 대상: 한 번에 하나만 (마지막으로 클릭한 파일 우선)
    var previewTarget: URL? {
        if let anchor, selection.contains(anchor) { return anchor }
        return selection.first
    }

    // MARK: 목록 읽기

    func reload() {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .fileSizeKey,
            .contentModificationDateKey, .localizedNameKey
        ]
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]          // 숨김 파일은 표시하지 않음
            )
            items = urls.map { u in
                let v = try? u.resourceValues(forKeys: Set(keys))
                let isDir = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
                return FileItem(
                    url: u,
                    name: v?.localizedName ?? u.lastPathComponent,
                    isDirectory: isDir,
                    size: isDir ? nil : v?.fileSize.map { Int64($0) },
                    modified: v?.contentModificationDate
                )
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory } // 폴더 먼저
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            items = []
            errorMessage = "이 폴더를 열 수 없습니다: \(error.localizedDescription)"
        }

        // 지워진 파일은 선택에서 빼기
        let existing = Set(items.map { $0.url })
        selection = selection.filter { existing.contains($0) }

        // 아래 상태줄의 "OO GB 사용 가능"
        if let v = try? currentURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = v.volumeAvailableCapacityForImportantUsage {
            freeSpaceText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " 사용 가능"
        } else {
            freeSpaceText = ""
        }
    }

    // 아래쪽 경로 막대용: [/, /Users, /Users/tissant, /Users/tissant/Desktop]
    var pathComponents: [URL] {
        var result: [URL] = []
        var u = currentURL.standardizedFileURL
        var guardCount = 0
        while u.path != "/" && !u.path.isEmpty && guardCount < 100 {
            result.append(u)
            u = u.deletingLastPathComponent().standardizedFileURL
            guardCount += 1
        }
        result.append(URL(fileURLWithPath: "/"))
        return result.reversed()
    }

    // MARK: 복사 (다른 칸이나 Finder에서 끌어다 놓았을 때)
    // 안전을 위해 "이동"이 아니라 항상 "복사"만 합니다. 원본은 그대로 남습니다.

    func copyIn(_ sources: [URL]) {
        var failed: [String] = []
        for src in sources {
            // 같은 폴더에 다시 놓은 경우는 무시
            if src.deletingLastPathComponent().standardizedFileURL.path == currentURL.standardizedFileURL.path {
                continue
            }
            let dest = uniqueDestination(currentURL.appendingPathComponent(src.lastPathComponent))
            do {
                try FileManager.default.copyItem(at: src, to: dest)
            } catch {
                failed.append(src.lastPathComponent)
            }
        }
        reload()
        if !failed.isEmpty {
            errorMessage = "복사 실패: " + failed.joined(separator: ", ")
        }
    }

    // 같은 이름이 있으면 덮어쓰지 않고 "이름 2.확장자" 식으로 새 이름을 만듦
    private func uniqueDestination(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}

// MARK: - 리스트 보기의 한 줄

struct ListRow: View {
    let item: FileItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 16, height: 16)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(item.modified.map { $0.formatted(date: .numeric, time: .shortened) } ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())   // 줄의 빈 곳을 잡아도 클릭·드래그가 되게
    }
}

// MARK: - 아이콘 보기의 한 칸

struct IconCell: View {
    let item: FileItem
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 48, height: 48)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.secondary.opacity(0.25) : Color.clear)
                )
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .frame(width: 88, height: 96, alignment: .top)
        .contentShape(Rectangle())
    }
}

// MARK: - 칸 하나의 화면

struct PaneView: View {
    @ObservedObject var model: PaneModel
    var isMergeSelected: Bool              // 병합하려고 ⌘ 클릭으로 고른 칸인지 (파란 테두리)
    var isMerged: Bool                     // 병합된 칸인지 (병합 해제 버튼 표시)
    var onCmdClick: () -> Void
    var onPlainClick: () -> Void
    var onCmdDragEnd: (CGPoint) -> Void
    var onUnmerge: () -> Void

    @State private var isDropTarget = false
    @State private var previewURL: URL? = nil
    @FocusState private var isFocused: Bool

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
        // 훑어보기(Quick Look) 창: previewURL에 파일이 들어가면 열리고, nil이면 닫힘
        .quickLookPreview($previewURL)
        .frame(minWidth: 260, minHeight: 200)
    }

    // MARK: 파일 목록 (리스트 / 아이콘)

    private var fileArea: some View {
        ScrollView {
            if model.viewMode == .list {
                LazyVStack(spacing: 0) {
                    ForEach(model.items) { item in
                        ListRow(item: item, selected: model.selection.contains(item.url))
                            .onTapGesture { tapped(item) }
                            .onDrag { NSItemProvider(object: item.url as NSURL) }
                    }
                }
                .padding(4)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
                    ForEach(model.items) { item in
                        IconCell(item: item, selected: model.selection.contains(item.url))
                            .onTapGesture { tapped(item) }
                            .onDrag { NSItemProvider(object: item.url as NSURL) }
                    }
                }
                .padding(8)
            }
        }
        .contentShape(Rectangle())
        // 빈 곳 클릭: 선택 해제
        .onTapGesture {
            isFocused = true
            onPlainClick()
            model.selection.removeAll()
        }
        // 키보드 입력을 받을 수 있게 (스페이스 → 훑어보기)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            togglePreview()
            return .handled
        }
    }

    private func tapped(_ item: FileItem) {
        isFocused = true
        onPlainClick()
        let clickCount = NSApp.currentEvent?.clickCount ?? 1
        if clickCount >= 2 {
            // 더블클릭: 폴더면 들어가고, 파일이면 기본 앱으로 열기
            if item.isDirectory {
                model.open(item.url)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        } else {
            model.click(item)
        }
    }

    private func togglePreview() {
        if previewURL != nil {
            previewURL = nil
        } else {
            previewURL = model.previewTarget
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
            Picker("보기 방식", selection: $model.viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.icon)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("보기 방식")

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

    // 맨 아래: 2개의 항목, 43.66GB 사용 가능
    private var statusBar: some View {
        Text("\(model.items.count)개의 항목" + (model.freeSpaceText.isEmpty ? "" : ", \(model.freeSpaceText)"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
    }
}

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
            onCmdClick: { cmdClick(i) },
            onPlainClick: { if !mergeSelection.isEmpty { mergeSelection = [] } },
            onCmdDragEnd: { point in cmdDrag(from: i, to: point) },
            onUnmerge: { unmerge(i) }
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("grid"))
        } action: { frame in
            paneFrames[i] = frame
        }
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
