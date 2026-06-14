import AppKit

func runCLIIfNeeded() -> Bool {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--render-sprites") {
        let dir = (i + 1 < args.count && !args[i + 1].hasPrefix("--")) ? args[i + 1] : "/tmp/niumabar-sprites"
        renderSprites(to: dir)
        return true
    }
    if args.contains("--check-touchbar") { checkTouchBar(); return true }
    if args.contains("--dump-state") { dumpState(); return true }
    if args.contains("--test-steer") { testSteer(); return true }
    if let i = args.firstIndex(of: "--render-energy") {
        let path = (i + 1 < args.count && !args[i + 1].hasPrefix("--")) ? args[i + 1] : "/tmp/niumabar-energy.png"
        renderEnergy(to: path)
        return true
    }
    return false
}

private func renderEnergy(to path: String) {
    let levels: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
    let scale: CGFloat = 6
    let cellW = CGFloat(SpriteBank.artWidth) * scale + 24
    let cellH = CGFloat(SpriteBank.artHeight) * scale + 34
    let W = Int(cellW * CGFloat(levels.count))
    let H = Int(cellH)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H)).fill()
    gctx.imageInterpolation = .none
    for (i, f) in levels.enumerated() {
        let ox = CGFloat(i) * cellW + 12
        let dim = Int((f * 4).rounded())
        guard let img = SpriteBank.image(frame: .stretch, palette: .normal, flipped: false, dim: dim) else { continue }
        let shrink = CGFloat(1 - 0.28 * f)
        let fullW = CGFloat(SpriteBank.artWidth) * scale
        let w = fullW * shrink
        let h = CGFloat(SpriteBank.artHeight) * scale * shrink
        img.draw(in: NSRect(x: ox + (fullW - w) / 2, y: 28, width: w, height: h))
        let label = "精力 \(Int((1 - f) * 100))%"
        NSAttributedString(string: label, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
        ]).draw(at: NSPoint(x: ox, y: 7))
    }
    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

private func renderSprites(to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for frame in PetFrame.allCases {
        for palette in [Palette.normal, .approval, .failed] {
            guard let rep = SpriteBank.bitmap(frame: frame, palette: palette, flipped: false, pixelSize: 12),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let path = "\(dir)/\(frame.name)-\(palette.name).png"
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }
}

private func checkTouchBar() {
    var model = [CChar](repeating: 0, count: 256)
    var size = model.count
    sysctlbyname("hw.model", &model, &size, nil, 0)
    print("hw.model: \(String(cString: model))")

    let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)
    print("DFRFoundation dlopen: \(dfr != nil ? "ok" : "FAIL")")
    if let dfr = dfr {
        let sym = dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier")
        print("DFRElementSetControlStripPresenceForIdentifier: \(sym != nil ? "ok" : "FAIL")")
    }
    let cls: AnyObject = NSTouchBarItem.self
    let ok = cls.responds(to: NSSelectorFromString("addSystemTrayItem:"))
    print("NSTouchBarItem.addSystemTrayItem: \(ok ? "ok" : "FAIL")")

    let barCls: AnyObject = NSTouchBar.self
    let modalOK = barCls.responds(to: NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:"))
    print("NSTouchBar.presentSystemModalTouchBar: \(modalOK ? "ok" : "FAIL")")
}

private func testSteer() {
    let m = PetModel()
    m.travelWidth = 150
    m.state = .approval   // 静止状态，点击也应让它朝引导方向冲
    print("初始: pos=\(Int(m.pos)) dir=\(Int(m.dir)) (approval 静止)")
    m.steer(towardX: 0)
    print("点最左(x=0):   dir=\(Int(m.dir))  期望 -1  \(m.dir < 0 ? "✓" : "✗")")
    m.steer(towardX: 140)
    print("点最右(x=140): dir=\(Int(m.dir))  期望 +1  \(m.dir > 0 ? "✓" : "✗")")
    let p0 = m.pos
    for _ in 0..<15 { m.tick(1.0 / 30.0) }
    print("引导后(approval 也动): pos \(Int(p0))→\(Int(m.pos))  应朝右  \(m.pos > p0 ? "✓" : "✗")")
}

private func dumpState() {
    let store = StateStore()
    store.reload()
    print("aggregate: \(store.aggregate.rawValue) | totalTokens: \(store.totalTokens)")
    for e in store.entries {
        print("  \(e.key): \(e.state.rawValue) (source=\(e.source), tokens=\(e.tokens), ts=\(Int(e.ts)))")
    }
}
