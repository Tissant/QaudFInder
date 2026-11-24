//
//  PathField.swift
//  QuadFinder — 칸 위쪽 막대의 경로 표시 겸 입력칸 (1.1.0, 예전 "폴더로 이동" 창을 대신함)
//
//  - 경로 글자를 더블클릭(또는 ⇧⌘G) → 입력칸으로 바뀌고 전체 경로가 선택됨 (한 번 클릭은 칸 활성화만)
//  - Return: 이동 / esc 또는 다른 곳 클릭: 취소
//  - ~/Documents, /Applications, 지금 폴더 기준 상대 경로, 파일 경로(그 파일 선택) 모두 가능
//  - ⌘ 누른 채 클릭하면 입력칸 대신 병합 선택 (위쪽 막대의 ⌘클릭 규칙이 우선)
//

import SwiftUI
import AppKit

struct PathField: View {
    @ObservedObject var model: PaneModel
    var onCmdClick: () -> Void
    var onPlainClick: () -> Void            // 칸을 활성 칸으로

    @State private var editing = false
    @State private var text = ""
    @State private var shownError: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("예: ~/Documents 또는 /Applications", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { finish(refocus: true) }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused && editing { finish(refocus: false) }   // 다른 곳을 클릭함
                    }
                    .onAppear { focused = true }
            } else {
                Text(model.currentURL.path)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            onCmdClick()
                        } else {
                            onPlainClick()
                            // 두 번째 클릭이면 입력칸으로 (기다림 없이 바로 판단하려고 클릭 횟수를 직접 확인)
                            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { begin() }
                        }
                    }
                    .help("더블클릭해서 경로 입력 (⇧⌘G)")
            }
        }
        .onChange(of: model.pathEditRequest) { _, _ in begin() }
    }

    private func begin() {
        text = model.currentURL.path
        editing = true
        focused = true
    }

    private func commit() {
        if let message = model.goTo(text) {
            shownError = message
            model.errorMessage = message             // 칸 위쪽에 빨간 글씨로 안내, 입력칸은 그대로
            focused = true
            return
        }
        finish(refocus: true)
    }

    private func finish(refocus: Bool) {
        if let shownError, model.errorMessage == shownError { model.errorMessage = nil }
        shownError = nil
        editing = false
        if refocus { model.requestFocus() }          // 키보드 입력을 다시 파일 목록으로
    }
}
