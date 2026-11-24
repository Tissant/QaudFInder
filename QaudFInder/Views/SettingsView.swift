//
//  SettingsView.swift
//  QuadFinder — 설정 창 (1.1.0)
//
//  여는 법: 앱 메뉴 "설정…"(⌘,) 또는 창 오른쪽 위 톱니바퀴 버튼
//  탭: 일반 / 보기 / 파일 조작 / 사이드바 / 단축키 / 고급
//  바꾸면 바로 적용되고 저장됩니다(macOS 설정 창 방식, "적용" 버튼 없음).
//

import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("일반", systemImage: "gearshape") { GeneralSettings() }
            Tab("보기", systemImage: "eye") { ViewSettings() }
            Tab("파일 조작", systemImage: "doc.on.doc") { FileSettings() }
            Tab("사이드바", systemImage: "sidebar.left") { SidebarSettings() }
            Tab("단축키", systemImage: "keyboard") { ShortcutSettings() }
            Tab("고급", systemImage: "gearshape.2") { AdvancedSettings() }
        }
        .frame(width: 480)
    }
}

// MARK: - 일반: 칸별 시작 폴더

private struct GeneralSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            StartLayoutSection()

            Section {
                ForEach(0..<settings.startFolders.count, id: \.self) { i in
                    LabeledContent("\(i + 1)번 칸") {
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: settings.startFolders[i]))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(FileManager.default.displayName(atPath: settings.startFolders[i]))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(settings.startFolders[i])
                            Button("선택…") { chooseStartFolder(i) }
                        }
                    }
                }
            } header: {
                Text("칸별 시작 폴더")
            } footer: {
                Text("번호는 위 미리보기의 칸 번호(왼쪽 위부터 글 읽는 순서)입니다. 「지난번 배치 그대로」일 때 첫 번째 창은 지난번에 보던 폴더를 그대로 엽니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 보기

private struct ViewSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("새 칸") {
                Picker("보기 방식", selection: $settings.newViewMode) {
                    Text("아이콘").tag(ViewMode.icon)
                    Text("리스트").tag(ViewMode.list)
                }
                PercentSlider(title: "기본 아이콘 크기", value: $settings.iconScale, range: 0.5...3.0)
                PercentSlider(title: "기본 격자 간격", value: $settings.gridSpacing, range: 0.5...1.5)
                Text("앱을 켤 때 각 칸이 이 크기·간격으로 시작합니다. 칸마다 바꾼 값(⌘+아이콘 보기 버튼)은 저장되지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("목록") {
                Toggle("파일 내용 미리보기(썸네일)", isOn: $settings.showThumbnails)
                Toggle("폴더를 항상 위로 정렬", isOn: $settings.foldersFirst)
                Toggle("파일 확장자 항상 보기", isOn: $settings.showExtensions)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 파일 조작

private struct FileSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("휴지통으로 이동하기 전에 확인", isOn: $settings.confirmTrash)
                Toggle("상태줄에 폴더 용량 계산해서 표시", isOn: $settings.folderSize)
            } footer: {
                Text("폴더 용량 계산은 큰 폴더나 외장 디스크에서 시간이 걸릴 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("칸끼리 끌어 놓기", selection: $settings.dragDefaultMove) {
                    Text("복사 (⌘ 누르면 이동)").tag(false)
                    Text("이동 (⌘ 누르면 복사)").tag(true)
                }
            } footer: {
                Text("Finder에서 끌어 온 파일과 Finder로 끌어 간 파일은 항상 복사됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 사이드바

private struct SidebarSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("사라진 즐겨찾기 자동 정리", isOn: $settings.cleanFavorites)
            } footer: {
                Text("휴지통으로 간 폴더와 없어진 폴더를 즐겨찾기에서 뺍니다(폴더 자체는 건드리지 않음). 연결이 끊긴 외장 디스크·NAS의 폴더는 지우지 않고 흐리게 표시합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 단축키: 바꿀 수 있는 것 + 고정된 것

private struct ShortcutSettings: View {
    @ObservedObject private var store = ShortcutStore.shared
    @State private var recording: ShortcutAction? = nil
    @State private var message: String? = nil
    @State private var monitor: Any? = nil

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 6) {
                            Button {
                                recording == action ? stopRecording() : startRecording(action)
                            } label: {
                                Text(recording == action ? "키를 누르세요…" : label(for: action))
                                    .monospacedDigit()
                                    .frame(minWidth: 96)
                            }
                            .help("눌러서 새 단축키 입력 (esc: 취소)")
                            Button {
                                store.reset(action)
                                message = nil
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!store.isCustom(action))
                            .help("기본값으로 (\(action.defaults.first?.display ?? ""))")
                        }
                    }
                }
            } header: {
                Text("바꿀 수 있는 단축키")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let message {
                        Text(message).foregroundStyle(.red)
                    }
                    HStack {
                        Text("단축키 칸을 누르고 새 키를 누르세요. ⌘, ⌥, ⌃ 중 하나와 함께 눌러야 합니다(Space·Return·⌫·기능키는 단독 가능).")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("모두 기본값으로") {
                            store.resetAll()
                            message = nil
                        }
                        .disabled(store.custom.isEmpty)
                    }
                }
                .font(.caption)
            }

            Section("고정된 단축키·마우스 동작") {
                ForEach(fixedShortcuts) { item in
                    LabeledContent(item.title) {
                        Text(item.keys)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .onDisappear(perform: stopRecording)
    }

    private func label(for action: ShortcutAction) -> String {
        store.combos(for: action).map(\.display).joined(separator: " , ")
    }

    // 다음에 누르는 키 하나를 가로채서 새 단축키로 (이 창 안에서만, 그 키는 다른 곳으로 가지 않음)
    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recording = action
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && event.modifierFlags.intersection(KeyCombo.relevant).isEmpty {
                stopRecording()                         // esc: 취소
                return nil
            }
            if let error = store.set(KeyCombo(event: event), for: action) {
                message = error
            } else {
                message = nil
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}

// MARK: - 고급: 초기화

private struct AdvancedSettings: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("모든 설정") {
                    Button("초기화…") {
                        confirm("모든 설정을 처음 상태로 되돌리겠습니까?",
                                detail: "바꾼 단축키도 기본값으로 돌아갑니다. 칸의 폴더와 즐겨찾기는 그대로 둡니다.",
                                action: "설정 초기화") { AppSettings.shared.resetAll() }
                    }
                }
                LabeledContent("즐겨찾기") {
                    Button("초기화…") {
                        confirm("즐겨찾기를 처음 상태로 되돌리겠습니까?",
                                detail: "데스크탑·문서·다운로드·홈·응용 프로그램 5개만 남습니다. 폴더 자체는 지워지지 않습니다.",
                                action: "즐겨찾기 초기화") { SidebarModel.shared.resetToDefaults() }
                    }
                }
            } footer: {
                Text("설정과 즐겨찾기는 이 맥에만 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func confirm(_ title: String, detail: String, action: String, run: () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "취소")
        if alert.runModal() == .alertFirstButtonReturn { run() }
    }
}

// MARK: - 이름 + 슬라이더 + 퍼센트

private struct PercentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: 0.05)
                    .frame(width: 180)
                Text("\(Int((value * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
