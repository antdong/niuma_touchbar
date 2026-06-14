import AppKit

final class PetView: NSView {
    let model: PetModel
    let drawScale: CGFloat
    let isPreview: Bool

    /// Touch Bar 远程布局以 intrinsicContentSize 为期望值，实际宽度以 bounds 为准
    var intrinsicWidth: CGFloat {
        didSet { if abs(intrinsicWidth - oldValue) > 0.5 { invalidateIntrinsicContentSize() } }
    }
    var onSteer: ((Double) -> Void)?   // 点击引导方向，参数 = 点击处的逻辑 x
    var onGeometry: (() -> Void)?

    init(model: PetModel, drawScale: CGFloat = 1, isPreview: Bool = false, intrinsicWidth: CGFloat = 150) {
        self.model = model
        self.drawScale = drawScale
        self.isPreview = isPreview
        self.intrinsicWidth = intrinsicWidth
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: CGFloat(model.travelWidth) * drawScale,
                                 height: CGFloat(PetModel.barHeight) * drawScale))
        allowedTouchTypes = [.direct]
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: intrinsicWidth, height: CGFloat(PetModel.barHeight))
    }

    override func layout() {
        super.layout()
        onGeometry?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onGeometry?()
    }

    override func touchesBegan(with event: NSEvent) {
        if let onSteer = onSteer {
            let ts = event.touches(matching: .began, in: self)
            if let t = ts.first {
                onSteer(Double(t.location(in: self).x / drawScale))   // 朝点击处引导
                return
            }
        }
        model.jump()
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x / drawScale
        onSteer?(Double(x))
    }

    override func draw(_ dirtyRect: NSRect) {
        let s = drawScale
        if isPreview {
            NSColor.black.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8 * s, yRadius: 8 * s).fill()
        }
        NSGraphicsContext.current?.imageInterpolation = .none

        let f = model.fatigue
        let effShrink = model.fatigueSize ? CGFloat(1 - 0.28 * f) : 1.0   // 大小可配
        let fullW = CGFloat(PetModel.spriteW) * s
        let w = fullW * effShrink
        let h = CGFloat(PetModel.spriteH) * s * effShrink
        let x = CGFloat(model.pos) * s + (fullW - w) / 2   // 缩放时水平居中
        let y = CGFloat(1 + model.bob + model.jumpY) * s   // 贴地，从底部缩

        if model.iconEmoji.isEmpty {
            let dim = model.fatigueColor ? Int((f * 4).rounded()) : 0     // 颜色（变暗）可配
            if let img = SpriteBank.image(frame: model.frame, palette: model.palette, flipped: model.dir < 0, dim: dim) {
                img.draw(in: NSRect(x: x, y: y, width: w, height: h))
            }
        } else if let ctx = NSGraphicsContext.current?.cgContext {
            let fontSize = CGFloat(PetModel.spriteH) * s * effShrink * 1.05
            let estr = NSAttributedString(string: model.iconEmoji,
                                          attributes: [.font: NSFont.systemFont(ofSize: fontSize)])
            let esz = estr.size()
            ctx.saveGState()
            if model.fatigueColor { ctx.setAlpha(1 - 0.55 * f) }          // emoji 不能变色，用透明度表「没精神」
            if model.dir > 0 {                                            // 向右走翻转（emoji 默认朝左）
                ctx.translateBy(x: x + esz.width, y: 0)
                ctx.scaleBy(x: -1, y: 1)
                estr.draw(at: NSPoint(x: 0, y: y))
            } else {
                estr.draw(at: NSPoint(x: x, y: y))
            }
            ctx.restoreGState()
        }

        if let mark = model.mark {
            let color: NSColor = model.state == .approval
                ? NSColor(deviceRed: 1.00, green: 0.84, blue: 0.04, alpha: CGFloat(model.markAlpha))
                : NSColor(deviceRed: 1.00, green: 0.27, blue: 0.23, alpha: CGFloat(model.markAlpha))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12 * s),
                .foregroundColor: color,
            ]
            let str = NSAttributedString(string: mark, attributes: attrs)
            let headX = model.dir >= 0 ? x + w - 8 * s : x + 2 * s
            str.draw(at: NSPoint(x: headX, y: CGFloat(PetModel.spriteH - 1) * s))
        }

        // 累计 token 消耗，固定在右侧显示
        if model.tokens > 0 {
            let tattrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5 * s, weight: .semibold),
                .foregroundColor: NSColor(white: 0.82, alpha: 0.9),
            ]
            let tstr = NSAttributedString(string: PetModel.fmtTokens(model.tokens), attributes: tattrs)
            let tsz = tstr.size()
            tstr.draw(at: NSPoint(x: bounds.width - tsz.width - 2 * s,
                                  y: (bounds.height - tsz.height) / 2))
        }
    }
}
