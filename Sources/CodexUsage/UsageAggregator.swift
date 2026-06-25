import Foundation

// MARK: - 用量聚合器

/// 把扫描出的原始 `TokenCountEvent` 聚合成 UI 直接可用的视图模型。
///
/// 聚合规则（核心去重逻辑写死在此）：
/// - 每日用量 = 当日所有事件的 `lastUsage`（本轮增量）之和。
///   **绝不**累加 `totalUsage`（累计值会因每轮重复计入上下文而虚高）。
/// - 配额窗口 = 所有事件中时间最新、且 `rate_limits` 至少有一个有效百分比的那一条。
public struct UsageAggregator: Sendable {
    /// 本地时区（用户实际所在日期归属用）
    public let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.calendar = cal
    }

    /// 聚合全部事件，生成快照。
    public func aggregate(_ events: [TokenCountEvent], dailyTokenGoal: Int) -> UsageSnapshot {
        // 1) 按本地日期分组，累加本轮增量
        var daily: [Date: TokenCounts] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            daily[day, default: .zero] = daily[day, default: .zero] + event.lastUsage
        }

        // 2) 今日用量
        let today = calendar.startOfDay(for: Date())
        let todayCounts = daily[today] ?? .zero

        // 3) 配额窗口：取最新一条有效记录
        let latestWithLimits = events.last {
            $0.rateLimits?.primary?.usedPercent != nil ||
                $0.rateLimits?.secondary?.usedPercent != nil
        }
        let rateLimits = latestWithLimits?.rateLimits

        // 4) 最近 7 天序列（用于下拉面板的小趋势）
        let recentDays = (0..<7).reversed().compactMap { offset -> DailyUsagePoint? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let counts = daily[day] ?? .zero
            return DailyUsagePoint(date: day, counts: counts)
        }

        let lastUpdated = events.last?.timestamp

        return UsageSnapshot(
            dailyTokenGoal: dailyTokenGoal,
            todayUsage: todayCounts,
            todayProgress: progressRatio(used: todayCounts.totalTokens, goal: dailyTokenGoal),
            rateLimits: rateLimits,
            rateLimitsUpdatedAt: latestWithLimits?.timestamp,
            recentDays: recentDays,
            lastUpdated: lastUpdated
        )
    }

    /// 进度比例，范围 0.0–1.0（超出目标也只显示满）。
    private func progressRatio(used: Int, goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(used) / Double(goal))
    }
}

// MARK: - 聚合结果视图模型

/// UI 层消费的聚合快照。
public struct UsageSnapshot: Sendable, Equatable {
    /// 每日 Token 目标
    public let dailyTokenGoal: Int
    /// 今日已用（按本地日期聚合的增量之和）
    public let todayUsage: TokenCounts
    /// 今日完成进度 0.0–1.0
    public let todayProgress: Double
    /// 最新有效的配额窗口
    public let rateLimits: RateLimits?
    /// 最新有效配额窗口来自哪一条 token_count 事件。
    public let rateLimitsUpdatedAt: Date?
    /// 最近 7 天用量
    public let recentDays: [DailyUsagePoint]
    /// 数据最后更新时间（最新事件的 timestamp）
    public let lastUpdated: Date?
}

/// 单日用量点（用于趋势展示）。
public struct DailyUsagePoint: Sendable, Equatable {
    public let date: Date
    public let counts: TokenCounts
}
