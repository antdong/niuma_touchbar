import Foundation

enum PetState: String {
    case idle, working, approval, failed

    var label: String {
        switch self {
        case .idle: return "空闲"
        case .working: return "工作中"
        case .approval: return "等待审批"
        case .failed: return "任务失败"
        }
    }
}

final class PetModel {
    static let pixel: Double = 1.5
    static let spriteW = Double(SpriteBank.artWidth) * pixel
    static let spriteH = Double(SpriteBank.artHeight) * pixel
    static let barHeight: Double = 30

    var state: PetState = .idle
    var travelWidth: Double = 150
    var fatigue: Double = 0  // 0=精力充沛 1=精疲力竭（由 token 消耗驱动）
    var tokens: Int = 0      // 累计 token 消耗，显示在小牛马旁边
    var rightReserve: Double = 0  // 右侧给 token 数字预留的宽度

    // 疲劳表现：可分别配置是否影响颜色/大小/速度（全关 = 消耗 token 不改变外观）
    var fatigueColor = true
    var fatigueSize = true
    var fatigueSpeed = true
    var iconEmoji = ""   // 空 = 内置像素牛马；否则用该 emoji 当图标

    static func fmtTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1000)k" }
        return "\(n)"
    }

    var speedMult: Double {
        didSet { UserDefaults.standard.set(speedMult, forKey: "speedMult") }
    }

    private(set) var pos: Double = 4
    private(set) var dir: Double = 1
    private(set) var frame: PetFrame = .stand
    private(set) var bob: Double = 0
    private(set) var jumpY: Double = 0
    private var jumpV: Double = 0
    private var phase: Double = 0
    private var markClock: Double = 0
    private var steerClock: Double = 0
    private var idleMoving = true
    private var idleClock: Double = 0
    private var idleSpan: Double = 3

    init() {
        let saved = UserDefaults.standard.double(forKey: "speedMult")
        speedMult = saved == 0 ? 1.0 : min(3.0, max(0.5, saved))
    }

    var palette: Palette {
        switch state {
        case .approval: return .approval
        case .failed: return .failed
        default: return .normal
        }
    }

    var mark: String? {
        switch state {
        case .approval: return "?"
        case .failed: return "!"
        default: return nil
        }
    }

    var markAlpha: Double { 0.6 + 0.4 * sin(markClock * 5) }

    func tick(_ dt: Double) {
        markClock += dt
        let ef = fatigueSpeed ? max(0.25, 1.0 - 0.45 * fatigue) : 1.0  // 疲倦减速（可关）
        var speed: Double = 0

        switch state {
        case .working:
            speed = 60 * speedMult * ef
            phase += dt * (5 + 3 * speedMult) * ef
            frame = (Int(phase * 2) % 2 == 0) ? .stretch : .tuck
            bob = abs(sin(phase * .pi)) * 2
        case .idle:
            idleClock += dt
            if idleClock > idleSpan {
                idleMoving.toggle()
                idleClock = 0
                idleSpan = Double.random(in: idleMoving ? 2...5 : 1.5...4)
            }
            if idleMoving {
                speed = 11 * ef
                phase += dt * 2.6 * ef
                frame = (Int(phase * 2) % 2 == 0) ? .walk : .stand
            } else {
                frame = .stand
            }
            bob = 0
        case .approval, .failed:
            frame = .stand
            bob = 0
        }

        if steerClock > 0 {
            steerClock -= dt
            let boost = fatigueSpeed ? max(0.3, 1.0 - 0.45 * fatigue) : 1.0
            speed = max(speed, 70 * boost)          // 被引导时朝 dir 冲刺，即使原本静止也动
            phase += dt * 7
            frame = (Int(phase * 2) % 2 == 0) ? .stretch : .tuck
            bob = abs(sin(phase * .pi)) * 2
        }

        if speed > 0 {
            pos += dir * speed * dt
            let maxX = max(8, travelWidth - Self.spriteW - 2 - rightReserve)
            if pos <= 2 { pos = 2; dir = 1 }
            if pos >= maxX { pos = maxX; dir = -1 }
        }

        if jumpV != 0 || jumpY > 0 {
            jumpY += jumpV * dt
            jumpV -= 260 * dt
            if jumpY <= 0 { jumpY = 0; jumpV = 0 }
        }
    }

    func jump() {
        if jumpY == 0 { jumpV = 62 }
    }

    /// 点击 Touch Bar 引导奔跑方向：朝点击的 x 跑过去，冲刺一会儿
    func steer(towardX x: Double) {
        dir = x >= (pos + Self.spriteW / 2) ? 1 : -1
        steerClock = 1.3
    }
}
