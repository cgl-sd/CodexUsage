import Foundation

// MARK: - Token 用量数据模型

/// 一组 token 计数（本轮增量或累计）。
public struct TokenCounts: Decodable, Equatable, Sendable {
    public var inputTokens: Int = 0
    public var cachedInputTokens: Int = 0
    public var outputTokens: Int = 0
    public var reasoningOutputTokens: Int = 0
    public var totalTokens: Int = 0

    // JSONL 字段是 snake_case，用 CodingKeys 映射
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    public static let zero = TokenCounts()

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens + rhs.reasoningOutputTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens
        )
    }
}

/// Codex 的用量窗口限制（5 小时 / 每周）。
public struct UsageWindow: Decodable, Equatable, Sendable {
    /// 已用百分比（0–100）。可能为 nil（如会话结束的清理记录）。
    public let usedPercent: Double?
    /// 窗口长度（分钟）：primary=300（5h），secondary=10080（7天）
    public let windowMinutes: Int?
    /// 重置时间戳
    public let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try c.decodeIfPresent(Double.self, forKey: .usedPercent)
        windowMinutes = try c.decodeIfPresent(Int.self, forKey: .windowMinutes)
        // resets_at 是 Unix 整数秒，手动转 Date
        if let secs = try c.decodeIfPresent(Int.self, forKey: .resetsAt) {
            resetsAt = Date(timeIntervalSince1970: TimeInterval(secs))
        } else {
            resetsAt = nil
        }
    }
}

/// rate_limits 事件负载：含 primary（5h）和 secondary（周）两个窗口。
public struct RateLimits: Decodable, Equatable, Sendable {
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    /// 套餐类型：plus / pro 等
    public let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

/// 从 jsonl 解析出的一次完整 token_count 事件。
public struct TokenCountEvent: Decodable, Equatable, Sendable {
    /// ISO8601 时间戳（UTC），如 "2026-06-24T15:07:41.482Z"
    public let timestamp: Date
    /// 本轮增量用量
    public let lastUsage: TokenCounts
    /// 本 session 累计用量（仅供诊断，不计入每日用量）
    public let totalUsage: TokenCounts
    /// 配额窗口
    public let rateLimits: RateLimits?

    public init(from decoder: Decoder) throws {
        // 顶层结构：{timestamp, type:"event_msg", payload:{type:"token_count", info:{...}, rate_limits:{...}}}
        let root = try decoder.container(keyedBy: RootKeys.self)
        let payload = try root.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        // 确认是 token_count 事件
        let payloadType = try payload.decode(String.self, forKey: .type)
        guard payloadType == "token_count" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: payload,
                debugDescription: "期望 token_count，实际为 \(payloadType)"
            )
        }

        let info = try payload.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
        lastUsage = try info.decode(TokenCounts.self, forKey: .lastTokenUsage)
        totalUsage = try info.decode(TokenCounts.self, forKey: .totalTokenUsage)

        // rate_limits 可能为 nil（事件级字段可能缺失）
        rateLimits = try payload.decodeIfPresent(RateLimits.self, forKey: .rateLimits)

        // 时间戳：Codex 用毫秒精度的 ISO8601，自定义解析
        let tsString = try root.decode(String.self, forKey: .timestamp)
        guard let parsed = TokenCountEvent.parseTimestamp(tsString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp, in: root,
                debugDescription: "无法解析时间戳: \(tsString)"
            )
        }
        timestamp = parsed
    }

    enum RootKeys: String, CodingKey {
        case timestamp
        case type
        case payload
    }
    enum PayloadKeys: String, CodingKey {
        case type
        case info
        case rateLimits = "rate_limits"
    }
    enum InfoKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
    }

    /// 解析 Codex 的 ISO8601 时间戳（带毫秒，如 "2026-06-24T15:07:41.482Z"）。
    /// 用 Foundation 的值类型解析策略，天然 Sendable，满足 Swift 6 严格并发。
    public static func parseTimestamp(_ string: String) -> Date? {
        // 优先按带毫秒解析（Codex token_count 事件总是带毫秒）
        let withFractional = Date.ISO8601FormatStyle()
            .year().month().day()
            .time(includingFractionalSeconds: true)
            .timeZone(separator: .omitted)
        if let d = try? withFractional.parse(string) {
            return d
        }
        // 兜底：不含毫秒的标准 ISO8601
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}
