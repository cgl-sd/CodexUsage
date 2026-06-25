import Foundation

// MARK: - 设置持久化

/// 用 UserDefaults 存储用户偏好，跨 App 重启保留。
public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()

    /// 每日 Token 目标（默认 8000 万）
    public var dailyTokenGoal: Int {
        get {
            let stored = defaults.integer(forKey: Key.dailyTokenGoal)
            return stored > 0 ? stored : 80_000_000
        }
        set {
            defaults.set(newValue, forKey: Key.dailyTokenGoal)
        }
    }

    /// 刷新间隔（秒）
    public var refreshInterval: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.refreshInterval)
            return stored > 0 ? stored : 60
        }
        set {
            defaults.set(newValue, forKey: Key.refreshInterval)
        }
    }

    private let defaults = UserDefaults.standard

    private enum Key {
        static let dailyTokenGoal = "dailyTokenGoal"
        static let refreshInterval = "refreshInterval"
    }

    private init() {}
}
