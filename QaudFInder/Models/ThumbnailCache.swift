//
//  ThumbnailCache.swift
//  QuadFinder — 파일 내용 미리보기(썸네일)
//
//  사진·PDF·동영상 등은 내용이 보이는 작은 그림을, 그 밖의 파일은 기본 아이콘을 보여 줍니다.
//  macOS 기본 기능(QuickLookThumbnailing)으로 화면 뒤에서 만들고, 한 번 만든 것은 기억해 둡니다.
//  아이콘 크기를 바꿀 때마다 새로 만들지 않도록 항상 가장 큰 크기(Huge)로 한 번만 만듭니다.
//

import AppKit
import QuickLookThumbnailing

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    // 아이콘 보기 Huge(48pt × 2배) 기준. 레티나 화면이라 2배 픽셀로 요청
    private let pointSize = CGSize(width: 96, height: 96)
    private let cache = NSCache<NSString, NSImage>()
    private var waiting: [NSString: [(NSImage) -> Void]] = [:]
    // 미리보기가 없는 파일(일반 문서 등)은 다시 요청하지 않도록 기억
    private var noThumbnail = Set<NSString>()

    private init() {
        cache.countLimit = 2000
    }

    // 바로 쓸 수 있으면 돌려주고, 없으면 nil (그동안은 기본 아이콘을 쓰고 완성되면 done이 불림)
    func thumbnail(for item: FileItem, done: @escaping (NSImage) -> Void) -> NSImage? {
        guard !item.isDirectory else { return nil }        // 폴더는 폴더 아이콘 그대로
        let key = Self.key(for: item)
        if let image = cache.object(forKey: key) { return image }
        if noThumbnail.contains(key) { return nil }
        if waiting[key] != nil {
            waiting[key]?.append(done)
            return nil
        }
        waiting[key] = [done]

        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: pointSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail            // 내용 미리보기만 (없으면 실패 → 기본 아이콘 유지)
        )
        Task { [weak self] in
            let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            self?.finish(key, image: rep?.nsImage)
        }
        return nil
    }

    private func finish(_ key: NSString, image: NSImage?) {
        let callbacks = waiting.removeValue(forKey: key) ?? []
        guard let image else {
            noThumbnail.insert(key)
            return
        }
        cache.setObject(image, forKey: key)
        callbacks.forEach { $0(image) }
    }

    // 파일이 바뀌면(수정일) 새로 만들도록 수정일까지 열쇠에 포함
    private static func key(for item: FileItem) -> NSString {
        "\(item.url.path)|\(item.modified?.timeIntervalSince1970 ?? 0)" as NSString
    }
}
