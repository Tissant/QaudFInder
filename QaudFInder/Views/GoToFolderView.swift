//
//  GoToFolderView.swift
//  QuadFinder — ⇧⌘G "폴더로 이동": 경로를 직접 입력해서 활성 칸을 이동
//
//  - /Applications 처럼 전체 경로, ~/Documents 처럼 홈 기준 경로 모두 가능
//  - 앞에 / 나 ~ 가 없으면 활성 칸의 지금 폴더 기준으로 찾음
//  - 파일 경로를 넣으면 그 파일이 있는 폴더로 가서 파일을 선택
//

import SwiftUI

struct GoToFolderView: View {
    var onGo: (String) -> String?          // 이동 시도. 실패하면 안내 문구를 돌려줌
    @State private var path: String
    @State private var error: String? = nil
    @Environment(\.dismiss) private var dismiss

    init(startPath: String, onGo: @escaping (String) -> String?) {
        self.onGo = onGo
        _path = State(initialValue: startPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("폴더로 이동")
                .font(.headline)
            TextField("예: ~/Documents 또는 /Applications", text: $path)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
                .onSubmit(go)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("이동", action: go)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func go() {
        if let message = onGo(path) {
            error = message
        } else {
            dismiss()
        }
    }
}
