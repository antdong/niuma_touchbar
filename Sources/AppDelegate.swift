import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSTouchBarDelegate {
    let model = PetModel()
    let store = StateStore()
    let defaults = UserDefaults.standard

    let fullItemId = NSTouchBarItem.Identifier("com.wzd.niumabar.full")

    var stripPet: PetView!
    var fullPet: PetView?
    var fullBar: NSTouchBar?
    var previewPanel: NSPanel?
    var previewPet: PetView?
    var statusItem: NSStatusItem!
    var tickTimer: Timer?
    var activity: NSObjectProtocol?
    var touchBarInstalled = false

    var statusLine: NSMenuItem!
    var speedLabelItem: NSMenuItem!
    var speedMenuRef: NSMenu!
    var speedSliderRef: NSSlider!
    var soundToggleItems: [PetState: NSMenuItem] = [:]
    var soundRingMenus: [PetState: NSMenu] = [:]
    var fatigueToggleItems: [String: NSMenuItem] = [:]
    var iconMenuItems: [NSMenuItem] = []
    var previewMenuItem: NSMenuItem!
    var loginMenuItem: NSMenuItem!

    var fullBarActive: Bool { fullPet?.window != nil }
    private var sigSrc: DispatchSourceSignal?
    private var soundArmed = false

    var energyCap: Double {  // 累计 token 消耗达到此值即「精疲力竭」
        get { let v = defaults.double(forKey: "energyCap"); return v == 0 ? 3_000_000 : v }
        set { defaults.set(newValue, forKey: "energyCap") }
    }
    var fatigueColor: Bool {
        get { defaults.object(forKey: "fatigueColor") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fatigueColor") }
    }
    var fatigueSize: Bool {
        get { defaults.object(forKey: "fatigueSize") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fatigueSize") }
    }
    var fatigueSpeed: Bool {
        get { defaults.object(forKey: "fatigueSpeed") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fatigueSpeed") }
    }
    var iconEmoji: String {
        get { defaults.string(forKey: "iconEmoji") ?? "" }
        set { defaults.set(newValue, forKey: "iconEmoji") }
    }
    private var currentSound: NSSound?
    private let soundChoices = ["Submarine", "Glass", "Funk", "Hero", "Ping", "Tink", "Basso", "Sosumi"]
    // 可发声的状态：转变「进入」该态时响一次
    private let soundableStates: [(state: PetState, label: String, def: String)] = [
        (.approval, "审批", "Submarine"),
        (.idle, "完成", "Glass"),
        (.failed, "失败", "Basso"),
    ]

    private func soundDefault(for s: PetState) -> String {
        soundableStates.first { $0.state == s }?.def ?? "Glass"
    }
    private func soundEnabled(for s: PetState) -> Bool {
        if let v = defaults.object(forKey: "sound.\(s.rawValue).on") as? Bool { return v }
        if s == .approval, let old = defaults.object(forKey: "approvalSound") as? Bool { return old }  // 迁移旧设置
        return true
    }
    private func setSoundEnabled(_ on: Bool, for s: PetState) {
        defaults.set(on, forKey: "sound.\(s.rawValue).on")
    }
    private func soundName(for s: PetState) -> String {
        if let n = defaults.string(forKey: "sound.\(s.rawValue).name") { return n }
        if s == .approval, let old = defaults.string(forKey: "approvalSoundName") { return old }  // 迁移旧设置
        return soundDefault(for: s)
    }
    private func setSoundName(_ n: String, for s: PetState) {
        defaults.set(n, forKey: "sound.\(s.rawValue).name")
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        // 防止重复运行出现两只牛马
        if let bid = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                .filter { $0 != NSRunningApplication.current }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "NiuMaBar Touch Bar animation")

        model.travelWidth = 150  // 进入 Touch Bar 后以实际 bounds 为准

        stripPet = PetView(model: model, drawScale: 1, intrinsicWidth: 150)
        stripPet.onSteer = { [weak self] _ in self?.presentFullBar() }   // 常驻点击 → 展开整条 Touch Bar
        stripPet.onGeometry = { [weak self] in self?.updateTravelWidth() }
        touchBarInstalled = TouchBarTray.install(view: stripPet)

        store.onAggregateChange = { [weak self] s in
            guard let self else { return }
            let prev = self.model.state
            self.model.state = s
            self.refreshStatusTitle()
            if self.soundArmed { self.maybePlaySound(prev: prev, next: s) }
        }
        store.start()
        model.state = store.aggregate

        setupStatusItem()

        if defaults.bool(forKey: "showPreview") || !touchBarInstalled {
            showPreview(true)
        }

        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t

        // pkill -USR1 NiuMaBar 可在脚本里切换整条跑道模式
        signal(SIGUSR1, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        s.setEventHandler { [weak self] in self?.toggleFullMode() }
        s.resume()
        sigSrc = s

        refreshStatusTitle()

        // 启动后稍等再 arm，避免启动瞬间发现旧的待审批文件就误响
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.soundArmed = true
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        if let bar = fullBar { TouchBarTray.dismissModal(bar) }
        TouchBarTray.remove()
    }

    private func tick() {
        updateTravelWidth()
        model.tokens = store.totalTokens
        model.rightReserve = store.totalTokens > 0 ? 30 : 0
        model.fatigueColor = fatigueColor
        model.fatigueSize = fatigueSize
        model.fatigueSpeed = fatigueSpeed
        model.iconEmoji = iconEmoji
        let target = min(1.0, Double(store.totalTokens) / max(100000.0, energyCap))
        model.fatigue += (target - model.fatigue) * 0.08   // 平滑过渡，精力渐变
        model.tick(1.0 / 30.0)
        stripPet?.needsDisplay = true
        fullPet?.needsDisplay = true
        previewPet?.needsDisplay = true
    }

    /// 跑道宽度始终跟随当前真正显示的视图：整条跑道模式用 fullPet，否则用 Control Strip 槽位
    private func updateTravelWidth() {
        let logical: CGFloat
        if let fp = fullPet, fp.window != nil {
            var w = fp.visibleRect.width
            if w < 50 { w = min(fp.bounds.width, 700) }
            // 比可见区宽会变成可滚动区域，小马会跑出画面——收紧到可见宽度
            if fp.intrinsicWidth > w + 4 && w > 100 { fp.intrinsicWidth = w }
            logical = w
        } else {
            logical = max(40, stripPet.bounds.width)
        }
        if abs(model.travelWidth - Double(logical)) > 1 {
            model.travelWidth = Double(logical)
            if previewPanel?.isVisible == true { rebuildPreview() }
        }
    }

    private func refreshStatusTitle() {
        let title: String
        switch model.state {
        case .idle: title = "🐴"
        case .working: title = "🐴💨"
        case .approval: title = "🐴❓"
        case .failed: title = "🐴❗"
        }
        statusItem?.button?.title = title
    }

    // MARK: - 整条跑道模式

    private func presentFullBar() {
        guard touchBarInstalled else { return }
        if fullBar == nil {
            let b = NSTouchBar()
            b.delegate = self
            b.defaultItemIdentifiers = [fullItemId]
            fullBar = b
        }
        TouchBarTray.presentModal(fullBar!)
    }

    private func minimizeFullBar() {
        if let bar = fullBar { TouchBarTray.minimizeModal(bar) }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == fullItemId else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        if fullPet == nil {
            let v = PetView(model: model, drawScale: 1, intrinsicWidth: 2000)
            v.onSteer = { [weak self] x in self?.model.steer(towardX: x) }
            v.onGeometry = { [weak self] in self?.updateTravelWidth() }
            fullPet = v
        }
        item.view = fullPet!
        return item
    }

    // MARK: - 声音提醒

    /// 仅在状态「转变进入」可发声态时响一次，天然去重（持续同态不重复）
    private func maybePlaySound(prev: PetState, next: PetState) {
        guard prev != next else { return }
        switch next {
        case .approval:
            if soundEnabled(for: .approval) { playSound(named: soundName(for: .approval)) }
        case .failed:
            if soundEnabled(for: .failed) { playSound(named: soundName(for: .failed)) }
        case .idle:
            // working/approval 收尾算「完成」；failed 褪色成 idle 不算完成，不响
            guard prev != .failed else { return }
            if soundEnabled(for: .idle) { playSound(named: soundName(for: .idle)) }
        default:
            break
        }
    }

    private func playSound(named name: String) {
        // 用实例属性持有，避免 NSSound 局部变量过早释放打断异步播放
        let s = NSSound(named: NSSound.Name(name))
            ?? NSSound(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff"), byReference: true)
        currentSound = s
        s?.stop()
        s?.play()
        fputs("[NiuMaBar] ▶ 播放提示音: \(name) (loaded=\(s != nil))\n", stderr)
    }

    // MARK: - 菜单

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐴"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        statusLine = NSMenuItem(title: "牛马状态：空闲", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        if !touchBarInstalled {
            let warn = NSMenuItem(title: "⚠️ 未接入 Touch Bar：\(TouchBarTray.diagnostics)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        let speedItem = NSMenuItem(title: "奔跑速度", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        for (label, v) in [("慢悠悠 0.6×", 0.6), ("正常 1.0×", 1.0), ("加急 1.6×", 1.6), ("疯狂牛马 3.0×", 3.0)] {
            let it = NSMenuItem(title: label, action: #selector(pickSpeed(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = v
            speedMenu.addItem(it)
        }
        speedMenu.addItem(.separator())
        let sliderItem = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 210, height: 28))
        let slider = NSSlider(value: model.speedMult, minValue: 0.5, maxValue: 3.0,
                              target: self, action: #selector(speedSlider(_:)))
        slider.frame = NSRect(x: 14, y: 3, width: 182, height: 22)
        slider.isContinuous = true
        container.addSubview(slider)
        sliderItem.view = container
        speedMenu.addItem(sliderItem)
        speedSliderRef = slider
        speedLabelItem = NSMenuItem(title: String(format: "当前：%.1f×", model.speedMult), action: nil, keyEquivalent: "")
        speedLabelItem.isEnabled = false
        speedMenu.addItem(speedLabelItem)
        speedItem.submenu = speedMenu
        menu.addItem(speedItem)
        speedMenuRef = speedMenu

        let soundItem = NSMenuItem(title: "声音提醒", action: nil, keyEquivalent: "")
        let soundMenu = NSMenu()
        for entry in soundableStates {
            let st = entry.state
            let stateItem = NSMenuItem(title: "\(entry.label)提示音", action: nil, keyEquivalent: "")
            let stateMenu = NSMenu()
            let toggle = NSMenuItem(title: "启用", action: #selector(toggleSound(_:)), keyEquivalent: "")
            toggle.target = self
            toggle.representedObject = st.rawValue
            stateMenu.addItem(toggle)
            soundToggleItems[st] = toggle
            stateMenu.addItem(.separator())
            let ringLabel = NSMenuItem(title: "铃声（点击试听）", action: nil, keyEquivalent: "")
            ringLabel.isEnabled = false
            stateMenu.addItem(ringLabel)
            for name in soundChoices {
                let it = NSMenuItem(title: name, action: #selector(pickSound(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = "\(st.rawValue)|\(name)"
                stateMenu.addItem(it)
            }
            stateItem.submenu = stateMenu
            soundMenu.addItem(stateItem)
            soundRingMenus[st] = stateMenu
        }
        soundItem.submenu = soundMenu
        menu.addItem(soundItem)

        // 疲劳表现（消耗 token 时改变什么，可配置；全关 = 不随消耗变化）
        let fatigueItem = NSMenuItem(title: "疲劳表现", action: nil, keyEquivalent: "")
        let fatigueMenu = NSMenu()
        for (label, key) in [("变暗（颜色）", "color"), ("变小（大小）", "size"), ("变慢（速度）", "speed")] {
            let it = NSMenuItem(title: label, action: #selector(toggleFatigueDim(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = key
            fatigueMenu.addItem(it)
            fatigueToggleItems[key] = it
        }
        fatigueItem.submenu = fatigueMenu
        menu.addItem(fatigueItem)

        // 图标（内置像素牛马 或 任选 emoji）
        let iconItem = NSMenuItem(title: "图标", action: nil, keyEquivalent: "")
        let iconMenu = NSMenu()
        let pixelIt = NSMenuItem(title: "🐎 像素牛马（默认）", action: #selector(pickIcon(_:)), keyEquivalent: "")
        pixelIt.target = self
        pixelIt.representedObject = ""
        iconMenu.addItem(pixelIt)
        iconMenuItems.append(pixelIt)
        iconMenu.addItem(.separator())
        for e in ["🐮", "🐴", "🐶", "🐱", "🐰", "🦄", "🐢", "🐉", "🐌", "🚀"] {
            let it = NSMenuItem(title: "\(e)  Emoji", action: #selector(pickIcon(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = e
            iconMenu.addItem(it)
            iconMenuItems.append(it)
        }
        iconItem.submenu = iconMenu
        menu.addItem(iconItem)

        menu.addItem(.separator())

        let testItem = NSMenuItem(title: "测试状态", action: nil, keyEquivalent: "")
        let testMenu = NSMenu()
        for (label, raw) in [("🏃 工作中", "working"), ("❓ 待审批", "approval"), ("💥 任务失败", "failed"), ("😴 空闲", "idle")] {
            let it = NSMenuItem(title: label, action: #selector(testState(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = raw
            testMenu.addItem(it)
        }
        testMenu.addItem(.separator())
        let clear = NSMenuItem(title: "清除测试状态", action: #selector(clearTest), keyEquivalent: "")
        clear.target = self
        testMenu.addItem(clear)
        testItem.submenu = testMenu
        menu.addItem(testItem)

        menu.addItem(.separator())

        previewMenuItem = NSMenuItem(title: "屏幕预览窗口", action: #selector(togglePreview), keyEquivalent: "")
        previewMenuItem.target = self
        menu.addItem(previewMenuItem)

        let openDir = NSMenuItem(title: "打开状态目录", action: #selector(openStateDir), keyEquivalent: "")
        openDir.target = self
        menu.addItem(openDir)

        loginMenuItem = NSMenuItem(title: "开机自启", action: #selector(toggleLogin), keyEquivalent: "")
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出小牛马", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let pct = Int((1 - model.fatigue) * 100)
        statusLine.title = "状态 \(model.state.label) · 精力 \(pct)% · 消耗 \(PetModel.fmtTokens(store.totalTokens)) · \(store.summary())"
        for it in speedMenuRef.items {
            if let v = it.representedObject as? Double {
                it.state = abs(v - model.speedMult) < 0.01 ? .on : .off
            }
        }
        speedSliderRef.doubleValue = model.speedMult
        speedLabelItem.title = String(format: "当前：%.1f×", model.speedMult)
        for entry in soundableStates {
            let st = entry.state
            soundToggleItems[st]?.state = soundEnabled(for: st) ? .on : .off
            let cur = soundName(for: st)
            soundRingMenus[st]?.items.forEach { it in
                if let tag = it.representedObject as? String, tag.hasPrefix("\(st.rawValue)|") {
                    it.state = (String(tag.dropFirst(st.rawValue.count + 1)) == cur) ? .on : .off
                }
            }
        }
        fatigueToggleItems["color"]?.state = fatigueColor ? .on : .off
        fatigueToggleItems["size"]?.state = fatigueSize ? .on : .off
        fatigueToggleItems["speed"]?.state = fatigueSpeed ? .on : .off
        for it in iconMenuItems {
            it.state = ((it.representedObject as? String ?? "") == iconEmoji) ? .on : .off
        }
        previewMenuItem.state = (previewPanel?.isVisible ?? false) ? .on : .off
        if #available(macOS 13.0, *) {
            loginMenuItem.isHidden = false
            loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            loginMenuItem.isHidden = true
        }
    }

    // MARK: - 动作

    @objc private func pickSpeed(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        model.speedMult = v
    }

    @objc private func speedSlider(_ sender: NSSlider) {
        model.speedMult = sender.doubleValue
        speedLabelItem.title = String(format: "当前：%.1f×", model.speedMult)
    }

    @objc private func toggleFullMode() {
        if fullBarActive { minimizeFullBar() } else { presentFullBar() }
    }

    @objc private func toggleSound(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let st = PetState(rawValue: raw) else { return }
        let now = !soundEnabled(for: st)
        setSoundEnabled(now, for: st)
        if now { playSound(named: soundName(for: st)) }  // 打开时试听
    }

    @objc private func pickSound(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String,
              let sep = tag.firstIndex(of: "|") else { return }
        let raw = String(tag[..<sep])
        let name = String(tag[tag.index(after: sep)...])
        guard let st = PetState(rawValue: raw) else { return }
        setSoundName(name, for: st)
        playSound(named: name)  // 选了就试听
    }

    @objc private func toggleFatigueDim(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case "color": fatigueColor.toggle()
        case "size": fatigueSize.toggle()
        case "speed": fatigueSpeed.toggle()
        default: break
        }
    }

    @objc private func pickIcon(_ sender: NSMenuItem) {
        iconEmoji = (sender.representedObject as? String) ?? ""
    }

    @objc private func testState(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let st = PetState(rawValue: raw) else { return }
        store.writeManual(st)
    }

    @objc private func clearTest() {
        store.clearManual()
    }

    @objc private func openStateDir() {
        NSWorkspace.shared.open(StateStore.dirURL)
    }

    @objc private func togglePreview() {
        showPreview(!(previewPanel?.isVisible ?? false))
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置开机自启失败"
            alert.informativeText = "\(error.localizedDescription)\n\n建议把 NiuMaBar.app 移到 /Applications 后再试。"
            alert.runModal()
        }
    }

    // MARK: - 预览窗口

    private func showPreview(_ show: Bool) {
        defaults.set(show, forKey: "showPreview")
        if show {
            if previewPanel == nil { buildPreview() }
            previewPanel?.orderFrontRegardless()
        } else {
            previewPanel?.orderOut(nil)
        }
    }

    private func rebuildPreview() {
        let wasVisible = previewPanel?.isVisible ?? false
        previewPanel?.orderOut(nil)
        previewPanel = nil
        previewPet = nil
        if wasVisible { showPreview(true) }
    }

    private func buildPreview() {
        let scale: CGFloat = model.travelWidth > 400 ? 1 : 2
        let w = CGFloat(model.travelWidth) * scale
        let h = CGFloat(PetModel.barHeight) * scale
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "小牛马 · Touch Bar 预览"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let pet = PetView(model: model, drawScale: scale, isPreview: true)
        pet.onSteer = { [weak self] x in self?.model.steer(towardX: x) }
        pet.frame = NSRect(x: 0, y: 0, width: w, height: h)
        pet.autoresizingMask = [.width, .height]
        panel.contentView = pet

        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - w / 2,
                                         y: screen.visibleFrame.minY + 80))
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.defaults.set(false, forKey: "showPreview")
        }

        previewPanel = panel
        previewPet = pet
    }
}
