//
//  CopyQueue.swift
//  QuadFinder — 백그라운드 복사·이동 대기열과 진행률
//
//  - 복사는 화면 뒤(백그라운드)에서 하나씩 차례로 진행합니다. 그동안 앱은 멈추지 않습니다.
//  - 진행률은 macOS의 copyfile 함수가 알려 주는 "지금까지 복사한 바이트"로 계산합니다.
//  - 취소하면 덜 복사된 항목은 휴지통으로 옮깁니다(완전 삭제하지 않음). 이미 끝난 항목은 남습니다.
//  - 다른 디스크로 "이동"할 때는 복사가 끝난 뒤 원본을 휴지통으로 옮깁니다.
//    (같은 디스크 안의 이동은 순간적으로 끝나므로 이 대기열을 거치지 않습니다)
//

import Foundation
import Combine
import Darwin

// MARK: - 복사 작업 하나

struct CopyJob: Identifiable, Sendable {
    let id = UUID()
    let sources: [URL]
    let destination: URL      // 넣을 폴더
    let move: Bool            // true면 끝난 뒤 원본을 휴지통으로
}

// MARK: - 백그라운드와 화면이 함께 보는 진행 상황 (잠금으로 보호)

nonisolated final class CopyProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _total: Int64 = 0
    private var _completed: Int64 = 0       // 끝난 파일들의 바이트 합
    private var _current: Int64 = 0         // 지금 복사 중인 파일에서 복사한 바이트
    private var _name = ""
    private var _cancelled = false

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    var total: Int64 {
        get { locked { _total } }
        set { locked { _total = newValue } }
    }
    var done: Int64 { locked { _completed + _current } }
    var name: String {
        get { locked { _name } }
        set { locked { _name = newValue } }
    }
    var cancelled: Bool {
        get { locked { _cancelled } }
        set { locked { _cancelled = newValue } }
    }
    func setCurrent(_ bytes: Int64) { locked { _current = bytes } }
    func fileFinished() { locked { _completed += _current; _current = 0 } }
    func setCompleted(_ bytes: Int64) { locked { _completed = bytes; _current = 0 } }
}

// MARK: - 대기열 (화면에서 보는 쪽)

@MainActor
final class CopyQueue: ObservableObject {
    static let shared = CopyQueue()

    @Published private(set) var current: CopyJob? = nil
    @Published private(set) var totalBytes: Int64 = 0      // 0이면 아직 "준비 중"
    @Published private(set) var doneBytes: Int64 = 0
    @Published private(set) var currentName = ""
    @Published private(set) var pendingCount = 0           // 뒤에서 기다리는 작업 수
    @Published var notice: String? = nil                    // 끝난 뒤 알림 (실패 목록 등)

    private var waiting: [CopyJob] = []
    private var progress: CopyProgress? = nil
    private var timer: Timer? = nil
    private var whenIdle: [() -> Void] = []

    var isBusy: Bool { current != nil || !waiting.isEmpty }

    private init() {}

    func enqueue(_ sources: [URL], to destination: URL, move: Bool) {
        guard !sources.isEmpty else { return }
        waiting.append(CopyJob(sources: sources, destination: destination, move: move))
        pendingCount = waiting.count
        startNextIfIdle()
    }

    func cancelCurrent() {
        progress?.cancelled = true
    }

    // 앱 종료 전: 기다리는 작업은 버리고, 진행 중인 것은 취소한 뒤 정리가 끝나면 알려 줌
    func cancelAll(then done: @escaping () -> Void) {
        waiting.removeAll()
        pendingCount = 0
        if current == nil {
            done()
        } else {
            whenIdle.append(done)
            cancelCurrent()
        }
    }

    private func startNextIfIdle() {
        guard current == nil else { return }
        guard !waiting.isEmpty else {
            let callbacks = whenIdle
            whenIdle.removeAll()
            callbacks.forEach { $0() }
            return
        }
        let job = waiting.removeFirst()
        pendingCount = waiting.count
        current = job
        totalBytes = 0
        doneBytes = 0
        currentName = job.sources.first?.lastPathComponent ?? ""
        notice = nil

        let box = CopyProgress()
        progress = box
        // 0.2초마다 진행 상황을 화면에 반영
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }

        Task.detached(priority: .userInitiated) {
            let failures = CopyQueue.run(job, box)
            await CopyQueue.shared.finish(job, failures: failures, cancelled: box.cancelled)
        }
    }

    private func poll() {
        guard let box = progress else { return }
        totalBytes = box.total
        doneBytes = box.done
        currentName = box.name
    }

    private func finish(_ job: CopyJob, failures: [String], cancelled: Bool) {
        poll()
        timer?.invalidate()
        timer = nil
        progress = nil
        current = nil

        var folders = [job.destination]
        if job.move { folders += job.sources.map { $0.deletingLastPathComponent() } }
        PaneModel.refreshPanes(showing: folders)

        if cancelled {
            notice = job.move ? "이동을 취소했습니다." : "복사를 취소했습니다."
        } else if !failures.isEmpty {
            notice = (job.move ? "이동 실패: " : "복사 실패: ") + failures.joined(separator: ", ")
        }
        startNextIfIdle()
    }

    // MARK: - 여기부터는 백그라운드에서 실행

    nonisolated private static func run(_ job: CopyJob, _ box: CopyProgress) -> [String] {
        let fm = FileManager.default

        // 1) 전체 크기 계산 (진행률의 분모)
        var sizes: [Int64] = []
        for src in job.sources {
            if box.cancelled { return [] }
            sizes.append(size(of: src, box))
        }
        box.total = max(sizes.reduce(0, +), 1)

        // 2) 하나씩 복사
        var failures: [String] = []
        var finishedBytes: Int64 = 0
        for (i, src) in job.sources.enumerated() {
            if box.cancelled { break }
            box.name = src.lastPathComponent
            let dest = uniqueDestination(job.destination.appendingPathComponent(src.lastPathComponent))
            let ok = copyWithProgress(src, to: dest, box)

            if box.cancelled {
                // 덜 복사된 것은 휴지통으로 (완전 삭제하지 않음)
                if fm.fileExists(atPath: dest.path) { try? fm.trashItem(at: dest, resultingItemURL: nil) }
                break
            }
            if !ok {
                failures.append(src.lastPathComponent)
                if fm.fileExists(atPath: dest.path) { try? fm.trashItem(at: dest, resultingItemURL: nil) }
            } else if job.move {
                // 다른 디스크로 이동: 복사가 끝났으니 원본은 휴지통으로
                do {
                    try fm.trashItem(at: src, resultingItemURL: nil)
                } catch {
                    failures.append(src.lastPathComponent + "(복사는 됐지만 원본을 휴지통으로 옮기지 못함)")
                }
            }
            finishedBytes += sizes[i]
            box.setCompleted(finishedBytes)
        }
        return failures
    }

    // 파일·폴더의 전체 크기 (하위 폴더 포함)
    nonisolated private static func size(of url: URL, _ box: CopyProgress) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        if v.isSymbolicLink == true { return 0 }
        if v.isDirectory != true { return Int64(v.fileSize ?? 0) }
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        var count = 0
        for case let child as URL in walker {
            count += 1
            if count % 500 == 0 && box.cancelled { return total }
            if let cv = try? child.resourceValues(forKeys: keys), cv.isRegularFile == true {
                total += Int64(cv.fileSize ?? 0)
            }
        }
        return total
    }

    // copyfile로 복사하면서 진행률을 box에 기록. 폴더면 안까지 전부 복사.
    nonisolated private static func copyWithProgress(_ src: URL, to dst: URL, _ box: CopyProgress) -> Bool {
        guard let state = copyfile_state_alloc() else { return false }
        defer { copyfile_state_free(state) }

        let callback: copyfile_callback_t = { what, stage, state, _, _, ctx in
            guard let ctx else { return COPYFILE_CONTINUE }
            let box = Unmanaged<CopyProgress>.fromOpaque(ctx).takeUnretainedValue()
            if box.cancelled { return COPYFILE_QUIT }
            if what == COPYFILE_COPY_DATA && stage == COPYFILE_PROGRESS {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                box.setCurrent(Int64(copied))
            } else if what == COPYFILE_RECURSE_FILE && stage == COPYFILE_FINISH {
                box.fileFinished()
            }
            return COPYFILE_CONTINUE
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(box).toOpaque())

        // ALL: 내용·권한·확장 속성 등 전부 / RECURSIVE: 폴더 안까지 / NOFOLLOW_SRC: 바로가기(심볼릭 링크)는 링크 그대로
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC | COPYFILE_EXCL)
        return copyfile(src.path, dst.path, state, flags) == 0
    }

    // 같은 이름이 있으면 덮어쓰지 않고 "이름 2.확장자" 식으로 새 이름을 만듦
    nonisolated static func uniqueDestination(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
