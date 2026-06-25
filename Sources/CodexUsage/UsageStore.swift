import Foundation

// MARK: - 中央状态机

/// 串联扫描器 → 聚合器 → UI 层的中央状态管理。
/// 负责：
/// 1. 启动时全量扫描 + 后台定时增量刷新。
/// 2. 持有最新聚合快照 `UsageSnapshot`，供 UI 读取。
/// 3. 数据变化时通过闭包通知 UI 更新。
@MainActor
public final class UsageStore: ObservableObject {
    public static let shared = UsageStore()

    /// 当前聚合快照（UI 绑定此属性）
    @Published public var snapshot: UsageSnapshot
    @Published public private(set) var accountInfo: CodexAccountInfo

    /// 上次扫描时间（用于增量扫描）
    private var lastScanDate: Date

    /// 刷新定时器
    private var refreshTimer: Timer?

    /// 数据变化回调（供菜单栏控制器等外部监听）
    public var onUpdate: (() -> Void)?

    private let scanner = CodexLogScanner()
    private let aggregator = UsageAggregator()

    private init() {
        // 初始空快照
        self.snapshot = UsageSnapshot(
            dailyTokenGoal: SettingsStore.shared.dailyTokenGoal,
            todayUsage: .zero,
            todayProgress: 0,
            rateLimits: nil,
            rateLimitsUpdatedAt: nil,
            recentDays: [],
            lastUpdated: nil
        )
        self.accountInfo = CodexAccountResolver().resolve()
        self.lastScanDate = .distantPast
    }

    /// 启动：全量扫描 + 开启定时刷新。
    public func start() {
        fullScan()
        startTimer()
    }

    /// 手动刷新（下拉菜单「刷新」按钮用）。
    public func refresh() {
        fullScan()
    }

    public func updateDailyTokenGoal(_ goal: Int) {
        guard goal > 0 else { return }
        SettingsStore.shared.dailyTokenGoal = goal
        fullScan()
    }

    public func updateAccount(displayName: String, email: String, accountID: String) {
        SettingsStore.shared.accountDisplayName = displayName
        SettingsStore.shared.accountEmail = email
        SettingsStore.shared.accountID = accountID
        accountInfo = CodexAccountResolver().resolve()
        onUpdate?()
    }

    public func localAuthAccountInfo() -> CodexAccountInfo {
        CodexAccountResolver().localAuthAccountInfo()
    }

    // MARK: - 私有方法

    private func fullScan() {
        let events = scanner.scanAllEvents()
        lastScanDate = Date()
        accountInfo = CodexAccountResolver().resolve()
        updateSnapshot(from: events)
    }

    private func incrementalScan() {
        let newEvents = scanner.scanEventsModifiedSince(lastScanDate)
        guard !newEvents.isEmpty else { return }
        lastScanDate = Date()
        // 增量需要和已有数据合并，这里简化为全量重算
        fullScan()
    }

    private func updateSnapshot(from events: [TokenCountEvent]) {
        snapshot = aggregator.aggregate(
            events,
            dailyTokenGoal: SettingsStore.shared.dailyTokenGoal
        )
        onUpdate?()
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        let interval = SettingsStore.shared.refreshInterval
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.incrementalScan()
            }
        }
    }
}
