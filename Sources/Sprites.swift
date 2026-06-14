import AppKit

struct Palette {
    let name: String
    let colors: [Character: NSColor]

    static let normal = Palette(name: "normal", colors: [
        "B": NSColor(deviceRed: 0.79, green: 0.56, blue: 0.31, alpha: 1),
        "M": NSColor(deviceRed: 0.42, green: 0.26, blue: 0.15, alpha: 1),
        "S": NSColor(deviceRed: 0.91, green: 0.79, blue: 0.63, alpha: 1),
        "H": NSColor(deviceRed: 0.29, green: 0.18, blue: 0.11, alpha: 1),
        "E": NSColor(deviceRed: 0.10, green: 0.10, blue: 0.12, alpha: 1),
    ])

    static let approval = Palette(name: "approval", colors: [
        "B": NSColor(deviceRed: 1.00, green: 0.84, blue: 0.04, alpha: 1),
        "M": NSColor(deviceRed: 0.66, green: 0.50, blue: 0.06, alpha: 1),
        "S": NSColor(deviceRed: 1.00, green: 0.94, blue: 0.55, alpha: 1),
        "H": NSColor(deviceRed: 0.55, green: 0.42, blue: 0.05, alpha: 1),
        "E": NSColor(deviceRed: 0.10, green: 0.10, blue: 0.12, alpha: 1),
    ])

    static let failed = Palette(name: "failed", colors: [
        "B": NSColor(deviceRed: 1.00, green: 0.27, blue: 0.23, alpha: 1),
        "M": NSColor(deviceRed: 0.62, green: 0.13, blue: 0.11, alpha: 1),
        "S": NSColor(deviceRed: 1.00, green: 0.62, blue: 0.58, alpha: 1),
        "H": NSColor(deviceRed: 0.50, green: 0.10, blue: 0.09, alpha: 1),
        "E": NSColor(deviceRed: 0.10, green: 0.10, blue: 0.12, alpha: 1),
    ])
}

enum PetFrame: Int, CaseIterable {
    case stand = 0, stretch, tuck, walk

    var name: String {
        switch self {
        case .stand: return "stand"
        case .stretch: return "stretch"
        case .tuck: return "tuck"
        case .walk: return "walk"
        }
    }
}

enum SpriteBank {
    static let artWidth = 17
    static let artHeight = 12

    // 17×12 像素小牛马，朝右。B=身体 M=鬃毛/尾巴 S=口鼻 E=眼睛 H=蹄
    static let standArt = [
        "........MM.......",
        ".......MBBBB.....",
        ".......MBBEBS....",
        ".M.....MBBBB.....",
        ".MM...MBBBB......",
        "..MBBBBBBBBB.....",
        "..BBBBBBBBBB.....",
        "...BBBBBBBB......",
        "...BB....BB......",
        "...BB....BB......",
        "...HH....HH......",
        ".................",
    ]

    static let stretchArt = [
        "........MM.......",
        ".......MBBBB.....",
        ".......MBBEBS....",
        ".M.....MBBBB.....",
        ".MM...MBBBB......",
        "..MBBBBBBBBB.....",
        "..BBBBBBBBBB.....",
        "...BBBBBBBB......",
        "..BB......BB.....",
        ".BB........BB....",
        ".HH..........HH..",
        ".................",
    ]

    static let tuckArt = [
        "........MM.......",
        ".......MBBBB.....",
        ".......MBBEBS....",
        ".M.....MBBBB.....",
        ".MM...MBBBB......",
        "..MBBBBBBBBB.....",
        "..BBBBBBBBBB.....",
        "...BBBBBBBB......",
        "....BB...BB......",
        "....HH...HH......",
        ".................",
        ".................",
    ]

    static let walkArt = [
        "........MM.......",
        ".......MBBBB.....",
        ".......MBBEBS....",
        ".M.....MBBBB.....",
        ".MM...MBBBB......",
        "..MBBBBBBBBB.....",
        "..BBBBBBBBBB.....",
        "...BBBBBBBB......",
        "...BB....BB......",
        "..B..B...B..B....",
        "..H..H...H..H....",
        ".................",
    ]

    static var frames: [[String]] { [standArt, stretchArt, tuckArt, walkArt] }

    private static var cache: [String: NSImage] = [:]

    static func bitmap(frame: PetFrame, palette: Palette, flipped: Bool, pixelSize: Int, dimLevel: Int = 0) -> NSBitmapImageRep? {
        let art = frames[frame.rawValue]
        let w = artWidth * pixelSize
        let h = artHeight * pixelSize
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        if let data = rep.bitmapData {
            memset(data, 0, rep.bytesPerRow * h)
        }
        let dim = max(0.4, 1.0 - 0.12 * Double(dimLevel))  // 疲倦 → 整体压暗（色相不变）
        for (ry, row) in art.enumerated() {
            for (rx, ch) in row.enumerated() {
                guard let base = palette.colors[ch] else { continue }
                let color = dimLevel == 0 ? base : NSColor(
                    deviceRed: base.redComponent * dim,
                    green: base.greenComponent * dim,
                    blue: base.blueComponent * dim,
                    alpha: base.alphaComponent)
                let ax = flipped ? (artWidth - 1 - rx) : rx
                for py in 0..<pixelSize {
                    for px in 0..<pixelSize {
                        rep.setColor(color, atX: ax * pixelSize + px, y: ry * pixelSize + py)
                    }
                }
            }
        }
        return rep
    }

    static func image(frame: PetFrame, palette: Palette, flipped: Bool, dim: Int = 0) -> NSImage? {
        let key = "\(frame.rawValue)-\(palette.name)-\(flipped)-\(dim)"
        if let img = cache[key] { return img }
        guard let rep = bitmap(frame: frame, palette: palette, flipped: flipped, pixelSize: 1, dimLevel: dim) else { return nil }
        let img = NSImage(size: NSSize(width: artWidth, height: artHeight))
        img.addRepresentation(rep)
        cache[key] = img
        return img
    }
}
