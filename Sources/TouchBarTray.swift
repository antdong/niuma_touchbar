import AppKit

/// 通过 DFRFoundation 私有框架把自定义视图常驻到 Touch Bar 的 Control Strip。
/// 与 Pock / Dozer 同一套机制：NSTouchBarItem +addSystemTrayItem: 加
/// DFRElementSetControlStripPresenceForIdentifier()。
enum TouchBarTray {
    static let identifier = "com.wzd.niumabar.pet"
    private static var item: NSCustomTouchBarItem?
    private typealias PresenceFn = @convention(c) (NSString, Bool) -> Void
    private static var presenceFn: PresenceFn?

    static var diagnostics = ""

    @discardableResult
    static func install(view: NSView) -> Bool {
        guard let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY) else {
            diagnostics = "DFRFoundation dlopen 失败"
            return false
        }
        guard let sym = dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier") else {
            diagnostics = "缺少 DFRElementSetControlStripPresenceForIdentifier"
            return false
        }
        presenceFn = unsafeBitCast(sym, to: PresenceFn.self)

        let sel = NSSelectorFromString("addSystemTrayItem:")
        let cls: AnyObject = NSTouchBarItem.self
        guard cls.responds(to: sel) else {
            diagnostics = "缺少 addSystemTrayItem:"
            return false
        }

        let tbItem = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier(identifier))
        tbItem.view = view
        item = tbItem
        _ = cls.perform(sel, with: tbItem)
        presenceFn?(identifier as NSString, true)
        diagnostics = "ok"
        return true
    }

    static func remove() {
        presenceFn?(identifier as NSString, false)
        if let tbItem = item {
            let cls: AnyObject = NSTouchBarItem.self
            let sel = NSSelectorFromString("removeSystemTrayItem:")
            if cls.responds(to: sel) { _ = cls.perform(sel, with: tbItem) }
        }
        item = nil
    }

    // MARK: - 整条跑道（system modal touch bar，Pock 同款机制）

    @discardableResult
    static func presentModal(_ bar: NSTouchBar) -> Bool {
        let cls: AnyObject = NSTouchBar.self
        let sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard cls.responds(to: sel) else { return false }
        _ = cls.perform(sel, with: bar, with: identifier)
        return true
    }

    static func minimizeModal(_ bar: NSTouchBar) {
        let cls: AnyObject = NSTouchBar.self
        let sel = NSSelectorFromString("minimizeSystemModalTouchBar:")
        if cls.responds(to: sel) { _ = cls.perform(sel, with: bar) }
    }

    static func dismissModal(_ bar: NSTouchBar) {
        let cls: AnyObject = NSTouchBar.self
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        if cls.responds(to: sel) { _ = cls.perform(sel, with: bar) }
    }
}
