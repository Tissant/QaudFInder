//
//  StartLayoutPicker.swift
//  QuadFinder — 설정 창 일반 탭 "시작할 때 칸 배치" (1.2.0)
//
//  왼쪽: 가로 배열·세로 배열 선택(1~3). 한쪽이 3이면 다른 쪽은 1~2만 (최대 6칸).
//  오른쪽: 고른 배열대로 그린 미리보기. 칸을 누르면 그 칸의 시작 폴더를 고릅니다.
//

import SwiftUI
import AppKit

struct StartLayoutSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section {
            Picker("시작 방식", selection: $settings.startWithGrid) {
                Text("지난번 배치 그대로").tag(false)
                Text("이 배열로 시작").tag(true)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    countPicker("가로 배열", value: $settings.startColumns, other: settings.startRows)
                    countPicker("세로 배열", value: $settings.startRows, other: settings.startColumns)
                }
                .fixedSize()
                Spacer(minLength: 0)
                LayoutPreview(columns: settings.startColumns, rows: settings.startRows)
                    .frame(width: 220, height: 56)       // 선택 상자 2줄 높이에 맞춤
            }
        } header: {
            Text("시작할 때 칸 배치")
        } footer: {
            Text("「이 배열로 시작」은 앱을 켤 때마다 이 배열과 칸별 시작 폴더로 엽니다. 새 창(⌘N)은 항상 이 배열로 엽니다. 미리보기의 칸을 누르면 시작 폴더를 고를 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // 1~3 선택 상자. 다른 쪽이 3이면 3은 고를 수 없음
    private func countPicker(_ title: String, value: Binding<Int>, other: Int) -> some View {
        Picker(title, selection: value) {
            ForEach(1...3, id: \.self) { n in
                Text("\(n)").tag(n)
                    .selectionDisabled(n == 3 && other == 3)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 150)
    }
}

// 배열 미리보기: 칸마다 번호 + 시작 폴더 이름. 누르면 폴더 고르기
private struct LayoutPreview: View {
    let columns: Int
    let rows: Int
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        cell(r * columns + c)
                    }
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
    }

    private func cell(_ i: Int) -> some View {
        let path = i < settings.startFolders.count ? settings.startFolders[i] : ""
        return Button { chooseStartFolder(i) } label: {
            HStack(spacing: 3) {
                Text("\(i + 1)").bold()
                Text(FileManager.default.displayName(atPath: path))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 10))
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .controlBackgroundColor)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(i + 1)번 칸 시작 폴더: \(path)\n누르면 바꿀 수 있어요")
    }
}

// 칸 i(0~5)의 시작 폴더 고르기 (일반 탭 목록과 미리보기가 함께 씀)
@MainActor
func chooseStartFolder(_ i: Int) {
    let settings = AppSettings.shared
    guard i < settings.startFolders.count else { return }
    let panel = NSOpenPanel()
    panel.title = "\(i + 1)번 칸 시작 폴더"
    panel.prompt = "선택"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: settings.startFolders[i])
    guard panel.runModal() == .OK, let url = panel.url else { return }
    settings.startFolders[i] = url.standardizedFileURL.path
}
