//
//  PaneLayoutView.swift
//  QuadFinder — 칸 배치 그리기 (1.2.0 자유 분할)
//
//  나무 구조(PaneLayout)로 계산한 위치에 칸을 한 판 위에 직접 놓습니다.
//  SplitView를 겹쳐 쓰지 않으므로, 칸을 나누거나 합쳐도 다른 칸의 파일 목록이 새로 만들어지지 않습니다.
//  칸 사이 경계선도 직접 그리고, 끌어서 크기를 바꿉니다(최소 크기 260×200 유지).
//

import SwiftUI
import AppKit

struct PaneLayoutView<Pane: View>: View {
    let layout: PaneLayout
    let size: CGSize
    let onMoveDivider: (LayoutDivider, CGPoint) -> Void
    @ViewBuilder let pane: (Int) -> Pane

    var body: some View {
        let area = CGRect(origin: .zero, size: size)
        let rects = layout.rects(in: area)
        ZStack(alignment: .topLeading) {
            ForEach(layout.paneIDs, id: \.self) { id in
                if let r = rects[id] {
                    pane(id)
                        .frame(width: r.width, height: r.height, alignment: .topLeading)
                        .clipped()
                        .offset(x: r.minX, y: r.minY)
                }
            }
            ForEach(layout.dividers(in: area)) { d in
                DividerHandle(divider: d) { point in onMoveDivider(d, point) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// 칸 사이 경계선: 보이는 선은 1pt, 잡을 수 있는 폭은 7pt
private struct DividerHandle: View {
    let divider: LayoutDivider
    let onDrag: (CGPoint) -> Void

    private let grab: CGFloat = 7

    var body: some View {
        let leftRight = divider.axis == .horizontal       // 좌우로 나눈 경계 = 세로선
        let line = divider.line
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: leftRight ? 1 : line.width, height: leftRight ? line.height : 1)
            .frame(width: leftRight ? grab : line.width, height: leftRight ? line.height : grab)
            .contentShape(Rectangle())
            .pointerStyle(leftRight ? .columnResize : .rowResize)
            .offset(x: leftRight ? line.minX - grab / 2 : line.minX,
                    y: leftRight ? line.minY : line.minY - grab / 2)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("grid"))
                    .onChanged { onDrag($0.location) }
            )
    }
}
