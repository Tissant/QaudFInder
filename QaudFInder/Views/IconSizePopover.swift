//
//  IconSizePopover.swift
//  QuadFinder — 아이콘 크기·격자 간격 슬라이더 창
//
//  - 아이콘 보기 버튼을 ⌘ 누른 채 클릭하면 열림
//  - 아이콘 크기: 50~300% (1.1.0에서 최대 300%로 늘림). 눈금 6개(50%부터 50%씩, 같은 간격)만, 글자 없이
//  - 격자 간격(1.1.0): 좁게(50%) · 보통(100%) · 넓게(150%) — Finder 보기 옵션의 "격자 간격"과 같은 뜻
//  - 움직이면 즉시 적용, 아래 글자를 누르면 그 값으로 바로 이동
//  - 오른쪽 위 X, esc, 또는 창 바깥을 클릭하면 닫힘
//  - 칸별로 적용, 앱을 다시 켜면 보통(100%)으로 돌아감
//

import SwiftUI

struct IconSizePopover: View {
    @Binding var scale: Double
    @Binding var spacing: Double
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StopSlider(title: "아이콘 크기", value: $scale, range: 0.5...3.0,
                       stops: [("50%", 0.5), ("100%", 1.0), ("150%", 1.5), ("200%", 2.0), ("250%", 2.5), ("300%", 3.0)],
                       showsNames: false,
                       closeButton: onClose)
            Divider()
            StopSlider(title: "격자 간격", value: $spacing, range: 0.5...1.5,
                       stops: [("좁게", 0.5), ("보통", 1.0), ("넓게", 1.5)],
                       closeButton: nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 192)                  // 1.1.0: 처음 만든 크기(320)의 60%로 줄임
    }
}

// MARK: - 제목 + 퍼센트 + 슬라이더 + 아래 눈금 글자

private struct StopSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let stops: [(name: String, value: Double)]
    var showsNames = true                    // false면 눈금만 (이름은 마우스를 올리면 보임)
    var closeButton: (() -> Void)?

    private let thumbInset: CGFloat = 6      // 슬라이더 양 끝에서 손잡이 중심까지의 거리 (작은 슬라이더)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 제목 줄: 아이콘 크기 ……… 100%  (X)
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))          // 1.1.0: 10pt → 11pt (10% 키움)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                if let closeButton {
                    Button(action: closeButton) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)        // esc로도 닫힘
                    .help("닫기")
                }
            }

            VStack(spacing: 0) {
                Slider(value: $value, in: range)
                    .controlSize(.mini)
                GeometryReader { geo in
                    let track = geo.size.width - thumbInset * 2
                    ForEach(stops, id: \.name) { stop in
                        let fraction = (stop.value - range.lowerBound) / (range.upperBound - range.lowerBound)
                        let isNearest = nearestStop == stop.name
                        Button { value = stop.value } label: {
                            VStack(spacing: 1) {
                                Capsule()
                                    .fill(isNearest ? Color.accentColor : Color.secondary.opacity(0.5))
                                    .frame(width: 1.5, height: showsNames ? 3 : 5)
                                if showsNames {
                                Text(stop.name)
                                    .font(.system(size: 10, weight: isNearest ? .semibold : .regular))
                                    .foregroundStyle(isNearest ? Color.primary : Color.secondary)
                                    .fixedSize()
                                }
                            }
                            .frame(minWidth: 12, minHeight: 10)          // 눈금만 있어도 누르기 쉽게
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(stop.name)
                        .position(x: thumbInset + track * fraction, y: showsNames ? 8 : 4)
                    }
                }
                .frame(height: showsNames ? 15 : 8)
            }
        }
    }

    // 지금 값에 가장 가까운 눈금 (글자를 진하게 표시)
    private var nearestStop: String {
        stops.min { abs($0.value - value) < abs($1.value - value) }?.name ?? ""
    }
}
