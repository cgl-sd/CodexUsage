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
    @Published public private(set) var isRefreshing = false

    /// 上次扫描时间（用于增量扫描）
    private var lastScanDate: Date
    private var cachedEvents: [TokenCountEvent] = []
    private var lastSnapshotDay: Date?

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
        refresh()
        startTimer()
    }

    /// 手动刷新（下拉菜单「刷新」按钮用）。
    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let scanner = scanner
        let task = Task.detached(priority: .utility) {
            let events = scanner.scanAllEvents()
            let accountInfo = CodexAccountResolver().resolve()
            return (events: events, accountInfo: accountInfo)
        }
        Task { @MainActor [weak self] in
            let result = await task.value
            guard let self else { return }
            self.cachedEvents = result.events
            self.lastScanDate = Date()
            self.accountInfo = result.accountInfo
            self.updateSnapshot(from: result.events)
            self.isRefreshing = false
        }
    }

    public func updateDailyTokenGoal(_ goal: Int) {
        guard goal > 0 else { return }
        SettingsStore.shared.dailyTokenGoal = goal
        if cachedEvents.isEmpty {
            refresh()
        } else {
            updateSnapshot(from: cachedEvents)
        }
    }

    public func refreshAccountInfo() {
        accountInfo = CodexAccountResolver().resolve()
        onUpdate?()
    }

    public func localAuthAccountInfo() -> CodexAccountInfo {
        CodexAccountResolver().localAuthAccountInfo()
    }

    // MARK: - 私有方法

    private func incrementalScan() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let scanner = scanner
        let since = lastScanDate
        let task = Task.detached(priority: .utility) {
            let newEvents = scanner.scanEventsModifiedSince(since)
            guard !newEvents.isEmpty else { return Optional<[TokenCountEvent]>.none }
            return scanner.scanAllEvents()
        }
        Task { @MainActor [weak self] in
            let events = await task.value
            guard let self else { return }
            if let events {
                self.cachedEvents = events
                self.lastScanDate = Date()
                self.updateSnapshot(from: events)
            } else if self.shouldRecomputeForCurrentDay(), self.cachedEvents.isEmpty == false {
                self.updateSnapshot(from: self.cachedEvents)
            }
            self.isRefreshing = false
        }
    }

    private func updateSnapshot(from events: [TokenCountEvent]) {
        snapshot = aggregator.aggregate(
            events,
            dailyTokenGoal: SettingsStore.shared.dailyTokenGoal
        )
        lastSnapshotDay = Calendar.current.startOfDay(for: Date())
        onUpdate?()
    }

    private func shouldRecomputeForCurrentDay() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return lastSnapshotDay != today
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
