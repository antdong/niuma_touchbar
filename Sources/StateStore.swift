import Foundation

struct SessionEntry {
    let key: String
    let state: PetState
    let ts: TimeInterval
    let source: String
    let tokens: Int
}

/// 聚合 ~/.niumabar/state/*.json 里各 agent 会话的状态。
/// 文件协议: {"state":"working|approval|failed|idle","ts":<unix秒>,"source":"claude|codex|manual","session":"..."}
final class StateStore {
    static let dirURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".niumabar/state", isDirectory: true)

    var onAggregateChange: ((PetState) -> Void)?
    private(set) var entries: [SessionEntry] = []
    private(set) var aggregate: PetState = .idle
    private(set) var totalTokens: Int = 0   // 各活跃会话累计 token 消耗之和 → 精力

    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var pendingReload: DispatchWorkItem?

    func start() {
        try? FileManager.default.createDirectory(at: Self.dirURL, withIntermediateDirectories: true)
        startWatcher()
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.reload() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        reload()
    }

    private func startWatcher() {
        let fd = open(Self.dirURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let w = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .link, .rename, .delete], queue: .main)
        w.setEventHandler { [weak self] in self?.scheduleReload() }
        w.setCancelHandler { close(fd) }
        w.resume()
        watcher = w
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    func reload() {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        var fresh: [SessionEntry] = []
        let files = (try? fm.contentsOfDirectory(at: Self.dirURL, includingPropertiesForKeys: nil)) ?? []

        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let rawState = obj["state"] as? String else { continue }
            let ts = (obj["ts"] as? NSNumber)?.doubleValue ?? 0
            let source = obj["source"] as? String ?? "unknown"
            let tokens = (obj["tokens"] as? NSNumber)?.intValue ?? 0
            let age = now - ts
            if age > 86400 { try? fm.removeItem(at: f); continue }

            var state = PetState(rawValue: rawState) ?? .idle
            if state == .failed && age > 25 { state = .idle }  // 失败红色只闪 25 秒

            let ttl: TimeInterval
            if source == "manual" {
                ttl = 180
            } else {
                switch state {
                case .working: ttl = 1800
                case .approval: ttl = 21600
                default: ttl = 7200
                }
            }
            guard age < ttl else { continue }
            fresh.append(SessionEntry(key: f.deletingPathExtension().lastPathComponent,
                                      state: state, ts: ts, source: source, tokens: tokens))
        }

        entries = fresh
        totalTokens = fresh.map { $0.tokens }.reduce(0, +)
        let prio: [PetState: Int] = [.idle: 0, .working: 1, .failed: 2, .approval: 3]
        let agg = fresh.max(by: { (prio[$0.state] ?? 0) < (prio[$1.state] ?? 0) })?.state ?? .idle
        if agg != aggregate {
            aggregate = agg
            onAggregateChange?(agg)
        }
    }

    func writeManual(_ state: PetState) {
        let obj: [String: Any] = [
            "state": state.rawValue,
            "ts": Date().timeIntervalSince1970,
            "source": "manual",
            "session": "menu",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? FileManager.default.createDirectory(at: Self.dirURL, withIntermediateDirectories: true)
            try? data.write(to: Self.dirURL.appendingPathComponent("manual-menu.json"), options: .atomic)
        }
        reload()
    }

    func clearManual() {
        try? FileManager.default.removeItem(at: Self.dirURL.appendingPathComponent("manual-menu.json"))
        reload()
    }

    func summary() -> String {
        if entries.isEmpty { return "暂无会话" }
        var bySource: [String: Int] = [:]
        for e in entries { bySource[e.source, default: 0] += 1 }
        return bySource.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
    }
}
