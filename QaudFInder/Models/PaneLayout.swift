//
//  PaneLayout.swift
//  QuadFinder — 칸 배치 (1.2.0 자유 분할)
//
//  칸 배치를 "나무 구조"로 기록합니다. 큰 영역을 좌우 또는 상하로 둘로 나누고,
//  나눈 쪽을 또 둘로 나누는 식입니다. 나무의 끝(잎)이 칸 하나이고, 칸 번호(0~5)를 가집니다.
//
//      상하로 나눔 (위 50%)
//      ├─ 좌우로 나눔 (왼쪽 50%) ─ 칸 0 | 칸 1
//      └─ 좌우로 나눔 (왼쪽 50%) ─ 칸 2 | 칸 3          = 2×2
//
//  화면과 상관없는 계산만 합니다(칸 위치, 경계선 위치, 나누기·합치기, Tab 순서, 최소 크기).
//  칸 번호는 저장 키 "pane{번호}.…"에 그대로 쓰입니다.
//

import Foundation
import CoreGraphics

// 나누는 방향
enum SplitAxis: String, Codable {
    case horizontal   // 좌우로 나눔 (칸이 가로로 나란히)
    case vertical     // 상하로 나눔 (칸이 세로로 쌓임)
}

// 나무의 마디 하나: 칸(pane) 또는 둘로 나눈 영역(axis + children 2개)
struct LayoutNode: Codable, Equatable {
    var pane: Int? = nil
    var axis: SplitAxis? = nil
    var ratio: Double = 0.5            // 첫째(왼쪽/위쪽)가 차지하는 비율
    var children: [LayoutNode] = []

    static func leaf(_ id: Int) -> LayoutNode { LayoutNode(pane: id) }

    static func split(_ axis: SplitAxis, _ ratio: Double, _ first: LayoutNode, _ second: LayoutNode) -> LayoutNode {
        LayoutNode(axis: axis, ratio: ratio, children: [first, second])
    }

    var isLeaf: Bool { pane != nil }
}

// 칸 사이 경계선 하나 (끌어서 크기 조절)
struct LayoutDivider: Identifiable {
    let path: [Int]          // 나무에서 이 경계선을 가진 마디의 위치 (0 = 첫째, 1 = 둘째)
    let axis: SplitAxis
    let line: CGRect         // 경계선 위치 (두께 0)
    let area: CGRect         // 이 경계선이 나누는 영역 전체
    var id: String { path.map(String.init).joined(separator: ".") + "/" + axis.rawValue }
}

struct PaneLayout: Codable, Equatable {
    static let maxPanes = 6
    static let minPaneSize = CGSize(width: 260, height: 200)   // 칸 하나의 최소 크기 (PaneView와 같음)

    var version = 1
    var root: LayoutNode

    // MARK: 만들기

    // 가로 columns × 세로 rows 격자. 칸 번호는 글 읽는 순서(0, 1, 2 …)
    static func grid(columns: Int, rows: Int) -> PaneLayout {
        let c = min(max(columns, 1), 3)
        var r = min(max(rows, 1), 3)
        if c * r > maxPanes { r = maxPanes / c }
        var next = 0
        let rowNodes: [LayoutNode] = (0..<r).map { _ in
            let cells = (0..<c).map { _ -> LayoutNode in
                defer { next += 1 }
                return .leaf(next)
            }
            return chain(cells, .horizontal)
        }
        return PaneLayout(root: chain(rowNodes, .vertical))
    }

    // 여러 개를 같은 크기로 나란히: A | (B | C) — 첫째 비율 1/개수
    private static func chain(_ nodes: [LayoutNode], _ axis: SplitAxis) -> LayoutNode {
        guard nodes.count > 1 else { return nodes[0] }
        return .split(axis, 1.0 / Double(nodes.count), nodes[0], chain(Array(nodes.dropFirst()), axis))
    }

    // MARK: 조회

    var paneIDs: [Int] {
        var ids: [Int] = []
        func walk(_ n: LayoutNode) {
            if let p = n.pane { ids.append(p) } else { n.children.forEach(walk) }
        }
        walk(root)
        return ids
    }

    var paneCount: Int { paneIDs.count }
    var isFull: Bool { paneCount >= Self.maxPanes }

    // 각 칸의 위치. 비율은 양쪽 칸이 최소 크기를 지키도록 (가능하면) 조정해서 계산
    func rects(in area: CGRect) -> [Int: CGRect] {
        var result: [Int: CGRect] = [:]
        func walk(_ n: LayoutNode, _ r: CGRect) {
            if let p = n.pane { result[p] = r; return }
            let (a, b) = Self.divide(n, r)
            walk(n.children[0], a)
            walk(n.children[1], b)
        }
        walk(root, area)
        return result
    }

    // 글 읽는 순서 (위 → 아래, 같은 높이면 왼쪽 → 오른쪽). Tab 이동에 씀
    var readingOrder: [Int] {
        let r = rects(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return r.keys.sorted { i, j in
            let a = r[i]!, b = r[j]!
            if abs(a.minY - b.minY) > 0.001 { return a.minY < b.minY }
            return a.minX < b.minX
        }
    }

    func dividers(in area: CGRect) -> [LayoutDivider] {
        var result: [LayoutDivider] = []
        func walk(_ n: LayoutNode, _ r: CGRect, _ path: [Int]) {
            guard let axis = n.axis, n.children.count == 2 else { return }
            let (a, b) = Self.divide(n, r)
            let line = axis == .horizontal
                ? CGRect(x: a.maxX, y: r.minY, width: 0, height: r.height)
                : CGRect(x: r.minX, y: a.maxY, width: r.width, height: 0)
            result.append(LayoutDivider(path: path, axis: axis, line: line, area: r))
            walk(n.children[0], a, path + [0])
            walk(n.children[1], b, path + [1])
        }
        walk(root, area, [])
        return result
    }

    // 배치 전체가 필요한 최소 크기 (창의 최소 크기로 씀)
    var minimumSize: CGSize { Self.minSize(root) }

    static func minSize(_ n: LayoutNode) -> CGSize {
        guard let axis = n.axis, n.children.count == 2 else { return minPaneSize }
        let a = minSize(n.children[0]), b = minSize(n.children[1])
        return axis == .horizontal
            ? CGSize(width: a.width + b.width, height: max(a.height, b.height))
            : CGSize(width: max(a.width, b.width), height: a.height + b.height)
    }

    // 마디 하나의 영역을 첫째·둘째로 나눔
    private static func divide(_ n: LayoutNode, _ r: CGRect) -> (CGRect, CGRect) {
        let axis = n.axis ?? .horizontal
        let ratio = clampedRatio(n.ratio, node: n, length: axis == .horizontal ? r.width : r.height)
        if axis == .horizontal {
            let w = r.width > 1 ? (r.width * ratio).rounded() : r.width * ratio   // 화면 좌표는 점 단위로 반올림
            return (CGRect(x: r.minX, y: r.minY, width: w, height: r.height),
                    CGRect(x: r.minX + w, y: r.minY, width: r.width - w, height: r.height))
        } else {
            let h = r.height > 1 ? (r.height * ratio).rounded() : r.height * ratio
            return (CGRect(x: r.minX, y: r.minY, width: r.width, height: h),
                    CGRect(x: r.minX, y: r.minY + h, width: r.width, height: r.height - h))
        }
    }

    // 양쪽이 최소 크기를 지키는 비율 범위로 자름 (길이가 1 이하면 = 비율 계산용 단위 사각형이면 그대로)
    static func clampedRatio(_ ratio: Double, node n: LayoutNode, length: CGFloat) -> Double {
        guard length > 1, let axis = n.axis, n.children.count == 2 else { return ratio }
        let a = minSize(n.children[0]), b = minSize(n.children[1])
        let lo = (axis == .horizontal ? a.width : a.height) / length
        let hi = 1 - (axis == .horizontal ? b.width : b.height) / length
        guard lo <= hi else { return ratio }       // 영역이 너무 작으면 원래 비율 (창 최소 크기가 막아 줌)
        return min(max(ratio, lo), hi)
    }

    // MARK: 경계선 끌기

    func node(at path: [Int]) -> LayoutNode? {
        var n = root
        for i in path {
            guard i < n.children.count else { return nil }
            n = n.children[i]
        }
        return n
    }

    // 경계선을 point까지 끌었을 때 (area = 그 경계선이 나누는 영역)
    mutating func moveDivider(_ d: LayoutDivider, to point: CGPoint) {
        guard let n = node(at: d.path) else { return }
        let length = d.axis == .horizontal ? d.area.width : d.area.height
        guard length > 0 else { return }
        let raw = d.axis == .horizontal ? (point.x - d.area.minX) / length : (point.y - d.area.minY) / length
        let r = Self.clampedRatio(min(max(raw, 0.05), 0.95), node: n, length: length)
        update(at: d.path) { $0.ratio = r }
    }

    private mutating func update(at path: [Int], _ change: (inout LayoutNode) -> Void) {
        func go(_ n: inout LayoutNode, _ rest: ArraySlice<Int>) {
            guard let i = rest.first else { change(&n); return }
            go(&n.children[i], rest.dropFirst())
        }
        go(&root, path[...])
    }

    // MARK: 나누기

    enum SplitProblem: Error { case full, tooSmall, notFound }

    // 칸 id를 반으로 나눔. 새 칸은 오른쪽/아래쪽, 새 칸 번호를 돌려줌.
    // paneRect를 주면 나눈 뒤 두 칸이 최소 크기보다 작아지는지 검사
    mutating func split(_ id: Int, _ axis: SplitAxis, paneRect: CGRect? = nil) -> Result<Int, SplitProblem> {
        guard !isFull else { return .failure(.full) }
        if let r = paneRect {
            let need = axis == .horizontal ? Self.minPaneSize.width * 2 : Self.minPaneSize.height * 2
            if (axis == .horizontal ? r.width : r.height) < need { return .failure(.tooSmall) }
        }
        let used = Set(paneIDs)
        guard let newID = (0..<Self.maxPanes).first(where: { !used.contains($0) }),
              let path = pathTo(id) else { return .failure(.notFound) }
        update(at: path) { $0 = .split(axis, 0.5, .leaf(id), .leaf(newID)) }
        return .success(newID)
    }

    private func pathTo(_ id: Int) -> [Int]? {
        func find(_ n: LayoutNode, _ path: [Int]) -> [Int]? {
            if n.pane == id { return path }
            for (i, c) in n.children.enumerated() {
                if let p = find(c, path + [i]) { return p }
            }
            return nil
        }
        return find(root, [])
    }

    // MARK: 합치기
    // 두 칸이 한 변 전체로 맞닿아 있어 합치면 직사각형이 되면 합칠 수 있습니다(D1).
    // 경계선이 조금(4% 이내) 어긋나 있으면 맞춰서 합칩니다.
    // 남는 칸은 왼쪽/위쪽 칸. 합친 뒤에는 칸 위치로 나무 구조를 새로 짭니다.

    private static let snap: CGFloat = 0.04
    private static let eps: CGFloat = 0.0001

    // 합칠 수 있으면 (남는 칸, 사라지는 칸)
    func mergePlan(_ a: Int, _ b: Int) -> (keep: Int, remove: Int)? {
        guard a != b else { return nil }
        let r = rects(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let ra = r[a], let rb = r[b] else { return nil }
        func near(_ x: CGFloat, _ y: CGFloat) -> Bool { abs(x - y) <= Self.snap }
        func touch(_ x: CGFloat, _ y: CGFloat) -> Bool { abs(x - y) <= Self.eps }
        // 좌우로 붙음: 위·아래 변이 거의 같고, 한쪽 오른쪽 변 = 다른 쪽 왼쪽 변
        if near(ra.minY, rb.minY) && near(ra.maxY, rb.maxY) {
            if touch(ra.maxX, rb.minX) { return (a, b) }
            if touch(rb.maxX, ra.minX) { return (b, a) }
        }
        // 상하로 붙음
        if near(ra.minX, rb.minX) && near(ra.maxX, rb.maxX) {
            if touch(ra.maxY, rb.minY) { return (a, b) }
            if touch(rb.maxY, ra.minY) { return (b, a) }
        }
        return nil
    }

    // 합치고 (남는 칸, 사라진 칸)을 돌려줌. 합칠 수 없으면 nil (배치는 그대로)
    mutating func merge(_ a: Int, _ b: Int) -> (keep: Int, remove: Int)? {
        guard let plan = mergePlan(a, b) else { return nil }
        var r = rects(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let union = r[plan.keep]!.union(r[plan.remove]!)
        r[plan.remove] = nil
        r[plan.keep] = union
        // 조금 어긋난 경계를 합친 칸의 변에 맞춤 (다른 칸의 같은 경계도 함께)
        let edgesX = [union.minX, union.maxX], edgesY = [union.minY, union.maxY]
        func snapped(_ v: CGFloat, _ edges: [CGFloat]) -> CGFloat {
            edges.first(where: { abs($0 - v) <= Self.snap }) ?? v
        }
        for (id, rect) in r {
            let x0 = snapped(rect.minX, edgesX), x1 = snapped(rect.maxX, edgesX)
            let y0 = snapped(rect.minY, edgesY), y1 = snapped(rect.maxY, edgesY)
            r[id] = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
        guard let tree = Self.build(r.map { ($0.key, $0.value) }, in: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
            return nil
        }
        root = tree
        return plan
    }

    // 칸 위치들로 나무 구조를 짬: 영역을 끝까지 가로지르면서 어느 칸도 자르지 않는 선을 찾아 둘로 나눔.
    // 가로선(상하로 나눔)을 먼저 찾아서, 격자는 "줄 → 칸" 순서가 됩니다.
    static func build(_ items: [(Int, CGRect)], in area: CGRect) -> LayoutNode? {
        if items.count == 1 { return .leaf(items[0].0) }
        guard items.count > 1 else { return nil }
        for axis in [SplitAxis.vertical, .horizontal] {
            let cuts = items
                .map { axis == .vertical ? $0.1.maxY : $0.1.maxX }
                .filter { $0 < (axis == .vertical ? area.maxY : area.maxX) - eps }
                .sorted()
            for c in cuts {
                let crosses = items.contains { item in
                    let lo = axis == .vertical ? item.1.minY : item.1.minX
                    let hi = axis == .vertical ? item.1.maxY : item.1.maxX
                    return lo < c - eps && hi > c + eps
                }
                if crosses { continue }
                let first = items.filter { (axis == .vertical ? $0.1.maxY : $0.1.maxX) <= c + eps }
                let second = items.filter { (axis == .vertical ? $0.1.maxY : $0.1.maxX) > c + eps }
                guard !first.isEmpty, !second.isEmpty else { continue }
                let (a, b): (CGRect, CGRect)
                let ratio: Double
                if axis == .vertical {
                    ratio = (c - area.minY) / area.height
                    a = CGRect(x: area.minX, y: area.minY, width: area.width, height: c - area.minY)
                    b = CGRect(x: area.minX, y: c, width: area.width, height: area.maxY - c)
                } else {
                    ratio = (c - area.minX) / area.width
                    a = CGRect(x: area.minX, y: area.minY, width: c - area.minX, height: area.height)
                    b = CGRect(x: c, y: area.minY, width: area.maxX - c, height: area.height)
                }
                guard let n1 = build(first, in: a), let n2 = build(second, in: b) else { return nil }
                return .split(axis, ratio, n1, n2)
            }
        }
        return nil       // 어떤 선으로도 나눌 수 없는 배치 (바람개비 모양 등)
    }

    // MARK: 저장한 배치 검사 (깨진 값이면 nil)

    var isValid: Bool {
        let ids = paneIDs
        guard (1...Self.maxPanes).contains(ids.count),
              Set(ids).count == ids.count,
              ids.allSatisfy({ (0..<Self.maxPanes).contains($0) }) else { return false }
        func ok(_ n: LayoutNode) -> Bool {
            if n.pane != nil { return n.children.isEmpty && n.axis == nil }
            return n.axis != nil && n.children.count == 2 && (0.05...0.95).contains(n.ratio) && n.children.allSatisfy(ok)
        }
        return ok(root)
    }
}
