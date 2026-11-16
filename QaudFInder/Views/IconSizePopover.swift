//
//  IconSizePopover.swift
//  QuadFinder — 아이콘 크기 슬라이더 창
//
//  - 아이콘 보기 버튼을 ⌘ 누른 채 클릭하면 열림
//  - 연속 슬라이더: Small(50%) · Normal(100%) · Big(150%) · Huge(200%), 움직이면 즉시 적용
//  - 아래 글자(Small 등)를 누르면 그 크기로 바로 이동
//  - 오른쪽 위 X, esc, 또는 창 바깥을 클릭하면 닫힘
//  - 칸별로 적용, 앱을 다시 켜면 Normal로 돌아감
//

import SwiftUI

struct IconSizePopover: View {
    @Binding var scale: Double
    var onClose: () -> Void

    private let stops: [(name: String, value: Double)] = [
        ("Small", 0.5), ("Normal", 1.0), ("Big", 1.5), ("Huge", 2.0),
    ]
    private let range: ClosedRange<Double> = 0.5...2.0
    private let thumbInset: CGFloat = 10     // 슬라이더 양 끝에서 손잡이 중심까지의 거리

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 제목 줄: 아이콘 크기 ……… 100%  (X)
            HStack(spacing: 8) {
                Text("아이콘 크기")
                    .font(.headline)
                Spacer()
                Text("\(Int((scale * 100).rounded()))%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)        // esc로도 닫힘
                .help("닫기")
            }

            // 슬라이더 + 아래 눈금 글자
            VStack(spacing: 6) {
                Slider(value: $scale, in: range)
                GeometryReader { geo in
                    let track = geo.size.width - thumbInset * 2
                    ForEach(stops, id: \.name) { stop in
                        let fraction = (stop.value - range.lowerBound) / (range.upperBound - range.lowerBound)
                        let isNearest = nearestStop == stop.name
                        Button { scale = stop.value } label: {
                            VStack(spacing: 3) {
                                // 눈금 표시
                                Capsule()
                                    .fill(isNearest ? Color.accentColor : Color.secondary.opacity(0.5))
                                    .frame(width: 2, height: 5)
                                Text(stop.name)
                                    .font(.caption.weight(isNearest ? .semibold : .regular))
                                    .foregroundStyle(isNearest ? Color.primary : Color.secondary)
                                    .fixedSize()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: thumbInset + track * fraction, y: 12)
                    }
                }
                .frame(height: 24)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // 지금 크기에 가장 가까운 눈금 (글자를 진하게 표시)
    private var nearestStop: String {
        stops.min { abs($0.value - scale) < abs($1.value - scale) }?.name ?? "Normal"
    }
}
