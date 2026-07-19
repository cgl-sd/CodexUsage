import Foundation
import CodexUsageCore

// 临时验证程序：用真实 ~/.codex/sessions 数据验证扫描器正确性
// 验证目标：
// 1. 能解析出 token_count 事件，数量合理
// 2. 时间戳解析正确（今日的事件归到今日）
// 3. last_token_usage vs total_token_usage 区分清楚（不混淆累计/增量）
// 4. rate_limits 字段能正确读取

let scanner = CodexLogScanner()
let events = scanner.scanAllEvents()

print("=== 扫描结果 ===")
print("事件总数: \(events.count)")

guard !events.isEmpty else {
    print("⚠️ 没扫描到任何事件，检查 ~/.codex/sessions 是否存在")
    exit(0)
}

// 时间范围
let earliest = events.first!.timestamp
let latest = events.last!.timestamp
let df = DateFormatter()
df.dateFormat = "yyyy-MM-dd HH:mm:ss"
df.timeZone = TimeZone(identifier: "Asia/Shanghai")
print("最早事件: \(df.string(from: earliest))")
print("最新事件: \(df.string(from: latest))")

// 按本地日期分组，累加 last_token_usage（增量），对比 total_token_usage（累计）
print("\n=== 每日用量（累加 last_token_usage 增量）===")
let calendar = Calendar(identifier: .gregorian)
var localCal = calendar
localCal.timeZone = TimeZone(identifier: "Asia/Shanghai")!

var dailyIncrement: [Date: TokenCounts] = [:]
for event in events {
    let day = localCal.startOfDay(for: event.timestamp)
    dailyIncrement[day, default: .zero] = dailyIncrement[day, default: .zero] + event.lastUsage
}

let sortedDays = dailyIncrement.keys.sorted()
for day in sortedDays.suffix(7) {  // 最近7天
    let counts = dailyIncrement[day]!
    print("\(df.string(from: day).prefix(10))  总量(last增量累加): \(counts.totalTokens)  输入: \(counts.inputTokens)  输出: \(counts.outputTokens)")
}

// 对比：今日如果错误地用 total_token_usage 会是多少
print("\n=== 去重陷阱验证（今日）===")
let today = localCal.startOfDay(for: Date())
let todayEvents = events.filter { localCal.isDate($0.timestamp, inSameDayAs: today) }
if todayEvents.isEmpty {
    print("今日暂无事件")
} else {
    let wrongWay = todayEvents.reduce(TokenCounts.zero) { $0 + $1.totalUsage }
    let rightWay = todayEvents.reduce(TokenCounts.zero) { $0 + $1.lastUsage }
    print("✅ 正确（累加 last 增量）: \(rightWay.totalTokens) tokens")
    print("❌ 错误（累加 total 累计）: \(wrongWay.totalTokens) tokens  ← 会虚高")
}

// rate_limits 验证：取最新一条带有效 rate_limits 的事件
print("\n=== 配额窗口（最新有效记录）===")
let latestWithLimits = events.last {
    $0.rateLimits?.primary?.usedPercent != nil ||
        $0.rateLimits?.secondary?.usedPercent != nil
}
if let rl = latestWithLimits?.rateLimits {
    if let p = rl.primary {
        print("primary窗口:   已用 \(p.usedPercent ?? -1)%，窗口 \(p.windowMinutes ?? -1) 分钟，重置于 \(df.string(from: p.resetsAt ?? Date()))")
    }
    if let s = rl.secondary {
        print("secondary窗口: 已用 \(s.usedPercent ?? -1)%，窗口 \(s.windowMinutes ?? -1) 分钟，重置于 \(df.string(from: s.resetsAt ?? Date()))")
    }
    print("套餐: \(rl.planType ?? "未知")")
} else {
    print("未找到带有效 rate_limits 的记录")
}

// === 聚合器验证 ===
print("\n=== 聚合器输出（目标 8000万）===")
let aggregator = UsageAggregator()
let snapshot = aggregator.aggregate(events, dailyTokenGoal: 80_000_000)
print("今日用量: \(snapshot.todayUsage.totalTokens) tokens")
print("今日进度: \(String(format: "%.1f%%", snapshot.todayProgress * 100))  (\(snapshot.todayUsage.totalTokens) / \(snapshot.dailyTokenGoal))")
print("最近7天:")
let dayFmt = DateFormatter()
dayFmt.dateFormat = "MM-dd"
for point in snapshot.recentDays {
    let bar = String(repeating: "█", count: min(20, point.counts.totalTokens / 2_500_000))
    print("  \(dayFmt.string(from: point.date))  \(point.counts.totalTokens)  \(bar)")
}
