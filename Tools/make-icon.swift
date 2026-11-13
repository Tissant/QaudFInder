//
//  make-icon.swift
//  QuadFinder 앱 아이콘을 코드로 그려서 PNG로 만드는 스크립트
//
//  사용법 (Mac 터미널, 프로젝트 폴더에서):
//    swift Tools/make-icon.swift QaudFInder/Assets.xcassets/AppIcon.appiconset
//
import AppKit

// 1024 기준 좌표로 그린 뒤 원하는 픽셀 크기로 축소
func render(size px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    let cs = CGColorSpaceCreateDeviceRGB()
    func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }

    // 1) 바탕: macOS 아이콘 규격 (824×824, 모서리 둥근 사각형) + 그림자
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: c(0x000000, 0.35))
    cg.addPath(bodyPath); cg.setFillColor(c(0x2B5FD9)); cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(bodyPath); cg.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [c(0x5B9BFF), c(0x2457D6)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // 위쪽 은은한 광택
    let gloss = CGGradient(colorsSpace: cs, colors: [c(0xFFFFFF, 0.18), c(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    cg.restoreGState()

    // 2) 2×2 칸: 폴더 모양 4개 (왼쪽 위 = 활성 칸, 노란색)
    let pad: CGFloat = 150, gap: CGFloat = 40
    let tile = (824 - pad * 2 - gap) / 2
    for row in 0..<2 {
        for col in 0..<2 {
            let x = 100 + pad + CGFloat(col) * (tile + gap)
            let y = 100 + pad + CGFloat(1 - row) * (tile + gap)
            let active = (row == 0 && col == 0)
            let tabW = tile * 0.42, tabH = tile * 0.13
            let bodyRect = CGRect(x: x, y: y, width: tile, height: tile - tabH * 0.75)
            // 탭 아래쪽을 몸통 안으로 깊게 겹쳐서 이음새가 매끈하게 보이도록
            let tabRect = CGRect(x: x, y: bodyRect.maxY - 60, width: tabW, height: tile - (bodyRect.maxY - 60 - y))
            let shape = CGMutablePath()
            shape.addPath(CGPath(roundedRect: bodyRect, cornerWidth: 30, cornerHeight: 30, transform: nil))
            shape.addPath(CGPath(roundedRect: tabRect, cornerWidth: 18, cornerHeight: 18, transform: nil))

            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: c(0x0A2A80, 0.35))
            cg.addPath(shape); cg.setFillColor(c(0xFFFFFF)); cg.fillPath()
            cg.restoreGState()

            cg.saveGState()
            cg.addPath(shape); cg.clip()
            let colors = active ? [c(0xFFD45C), c(0xF5A623)] : [c(0xFFFFFF), c(0xDCE8FF)]
            let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(g, start: CGPoint(x: x, y: y + tile), end: CGPoint(x: x, y: y), options: [])
            // 폴더 앞판 경계선 느낌
            cg.setFillColor(c(0xFFFFFF, active ? 0.28 : 0.55))
            cg.fill(CGRect(x: x, y: y + tile - tabH * 0.75 - 26, width: tile, height: 4))
            cg.restoreGState()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(size: px).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("ok")
