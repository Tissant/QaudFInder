//
//  CopyProgressBar.swift
//  QuadFinder — 창 오른쪽 아래에 뜨는 복사·이동 진행률 막대
//

import SwiftUI

struct CopyProgressBar: View {
    @ObservedObject private var queue = CopyQueue.shared

    var body: some View {
        if let job = queue.current {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: job.move ? "arrow.right.doc.on.clipboard" : "doc.on.doc")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(job.move ? "옮기는" : "복사하는") 중: \(queue.currentName)")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if queue.totalBytes > 0 {
                        ProgressView(value: Double(min(queue.doneBytes, queue.totalBytes)),
                                     total: Double(queue.totalBytes))
                        Text(detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                        Text("크기 계산 중…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button { queue.cancelCurrent() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("이 작업 취소")
            }
            .padding(12)
            .frame(width: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 6)
        } else if let notice = queue.notice {
            HStack(spacing: 8) {
                Text(notice)
                    .font(.callout)
                    .lineLimit(3)
                Button { queue.notice = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("닫기")
            }
            .padding(12)
            .frame(maxWidth: 340, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 6)
        }
    }

    // "1.2 GB / 4 GB · 30% · 대기 2개"
    private var detailText: String {
        let done = ByteCountFormatter.string(fromByteCount: queue.doneBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: queue.totalBytes, countStyle: .file)
        let percent = Int(Double(queue.doneBytes) / Double(max(queue.totalBytes, 1)) * 100)
        var text = "\(done) / \(total) · \(min(percent, 100))%"
        if queue.pendingCount > 0 { text += " · 대기 \(queue.pendingCount)개" }
        return text
    }
}
