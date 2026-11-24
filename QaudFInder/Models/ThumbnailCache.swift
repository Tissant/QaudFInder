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

    // 두 단계 크기로 만듦 (1.1.0: 아이콘 크기를 300%까지 키울 수 있게 됨)
    //   보통: 96pt (아이콘 크기 200%까지 선명)   크게: 144pt (200% 초과~300%)
    // 레티나 화면이라 2배 픽셀로 요청
    static func pointSize(large: Bool) -> CGFloat { large ? 144 : 96 }
    private let cache = NSCache<NSString, NSImage>()
    private var waiting: [NSString: [(NSImage) -> Void]] = [:]
    // 미리보기가 없는 파일(일반 문서 등)은 다시 요청하지 않도록 기억
    private var noThumbnail = Set<NSString>()

    private init() {
        cache.countLimit = 2000
        cache.totalCostLimit = 200 * 1024 * 1024        // 미리보기 그림은 최대 약 200MB까지만 기억 (넘으면 오래된 것부터 버림)
    }

    // 바로 쓸 수 있으면 돌려주고, 없으면 nil (그동안은 기본 아이콘을 쓰고 완성되면 done이 불림)
    func thumbnail(for item: FileItem, large: Bool = false, done: @escaping (NSImage) -> Void) -> NSImage? {
        guard !item.isDirectory else { return nil }        // 폴더는 폴더 아이콘 그대로
        let key = Self.key(for: item, large: large)
        let side = Self.pointSize(large: large)
        if let image = cache.object(forKey: key) { return image }
        if noThumbnail.contains(key) { return nil }
        if waiting[key] != nil {
            waiting[key]?.append(done)
            return nil
        }
        waiting[key] = [done]

        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: side, height: side),
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
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
        cache.setObject(image, forKey: key, cost: max(pixels, 1) * 4)   // 픽셀당 4바이트
        callbacks.forEach { $0(image) }
    }

    // 파일이 바뀌면(수정일) 새로 만들도록 수정일까지 열쇠에 포함
    private static func key(for item: FileItem, large: Bool) -> NSString {
        "\(item.url.path)|\(item.modified?.timeIntervalSince1970 ?? 0)|\(large ? "L" : "M")" as NSString
    }
}
