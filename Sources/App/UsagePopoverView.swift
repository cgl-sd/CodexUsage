import CodexUsageCore
import SwiftUI

struct UsagePopoverView: View {
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        UsageOverviewPane(
            onOpenSettings: onOpenSettings,
            onRefresh: onRefresh,
            onQuit: onQuit
        )
        .frame(width: 314, height: 352, alignment: .topLeading)
        .background(popoverBackground)
    }

    private var popoverBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.13)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct UsageOverviewPane: View {
    @ObservedObject private var store = UsageStore.shared

    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let snapshot = store.snapshot

        VStack(alignment: .leading, spacing: 10) {
            header(snapshot: snapshot)
            accountSummary(store.accountInfo, snapshot: snapshot)

            VStack(spacing: 8) {
                ProgressMetricRow(
                    title: "今日目标",
                    iconName: snapshot.todayProgress >= 1 ? "checkmark.circle.fill" : "target",
                    tint: dailyGoalColor(snapshot.todayProgress * 100),
                    percent: snapshot.todayProgress * 100,
                    detail: "\(formatTokenCount(snapshot.todayUsage.totalTokens)) / \(formatTokenCount(snapshot.dailyTokenGoal))",
                    resetText: "按本地日志统计"
                )

                ProgressMetricRow(
                    title: "5 小时用量",
                    iconName: "clock.fill",
                    tint: fiveHourColor(snapshot.rateLimits?.primary?.usedPercent),
                    percent: snapshot.rateLimits?.primary?.usedPercent,
                    detail: percentDetail(snapshot.rateLimits?.primary?.usedPercent),
                    resetText: resetText(snapshot.rateLimits?.primary?.resetsAt, style: .time)
                )

                ProgressMetricRow(
                    title: "周用量",
                    iconName: "calendar",
                    tint: weeklyColor(snapshot.rateLimits?.secondary?.usedPercent),
                    percent: snapshot.rateLimits?.secondary?.usedPercent,
                    detail: percentDetail(snapshot.rateLimits?.secondary?.usedPercent),
                    resetText: resetText(snapshot.rateLimits?.secondary?.resetsAt, style: .date)
                )
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text("更新于 \(updatedText(snapshot.lastUpdated))")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(14)
    }

    private func header(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(nsImage: CircularProgressIcon.image(progress: snapshot.todayProgress, size: 30))
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex Usage")
                        .font(.headline)
                    Text("每日目标 \(formatTokenCount(snapshot.dailyTokenGoal)) token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(store.isRefreshing ? 180 : 0))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isRefreshing)
                    .help("重新读取本地 Codex 日志")

                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("设置")

                    Button(action: onQuit) {
                        Image(systemName: "power")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("退出")
                }
            }

            HStack {
                Text(String(format: "%.1f%%", snapshot.todayProgress * 100))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(dailyGoalColor(snapshot.todayProgress * 100))

                Spacer()

                if store.isRefreshing {
                    Text("正在刷新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func accountSummary(_ account: CodexAccountInfo, snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: verificationIcon(account.verification))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(verificationColor(account.verification))
                .frame(width: 16)

            Text(account.email ?? account.name ?? "未读取到本地账号")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            planBadge(account.planType ?? snapshot.rateLimits?.planType)
        }
    }

    private func planBadge(_ plan: String?) -> some View {
        let text = (plan?.isEmpty == false ? plan! : "未知").uppercased()
        let tint = planColor(plan)

        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }

}

struct UsageSettingsView: View {
    @ObservedObject private var store = UsageStore.shared
    @State private var goalWanText = ""
    @State private var saveMessage = ""

    var body: some View {
        let account = store.accountInfo

        VStack(alignment: .leading, spacing: 18) {
            Text("设置")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("本地账号")
                    .font(.subheadline.weight(.semibold))

                accountLine("邮箱", account.email ?? "未读取到")
                accountLine("名称", account.name ?? "未读取到")
                accountLine("计划", account.planType?.uppercased() ?? "未知")
                accountLine("账号 ID", account.accountID.map(shortAccountID) ?? "未读取到")

                HStack {
                    Text(verificationText(account.verification))
                        .font(.caption)
                        .foregroundStyle(verificationColor(account.verification))
                    Spacer()
                    Button(action: refreshLocal) {
                        Label("重新读取本地信息", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("每日目标")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    TextField("8000", text: $goalWanText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospacedDigit())
                        .frame(width: 90)
                    Text("万 token / 天")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: saveGoal) {
                        Label("保存", systemImage: "checkmark")
                    }
                    .disabled(parsedGoal == nil)
                }

                Text(saveMessage.isEmpty ? "当前目标 \(formatTokenCount(store.snapshot.dailyTokenGoal)) token" : saveMessage)
                    .font(.caption)
                    .foregroundStyle(saveMessage.isEmpty ? Color.secondary : Color.green)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("数据来源")
                    .font(.subheadline.weight(.semibold))
                Text("用量从本地 ~/.codex/sessions 日志读取；5 小时和周配额来自日志中的 rate_limits。账号信息从本地 ~/.codex/auth.json 动态解析，不在程序中写死。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 420, height: 360)
        .onAppear {
            goalWanText = String(store.snapshot.dailyTokenGoal / 10_000)
        }
    }

    private var parsedGoal: Int? {
        let trimmed = goalWanText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let wan = Double(trimmed), wan > 0 else { return nil }
        return Int((wan * 10_000).rounded())
    }

    private func saveGoal() {
        guard let parsedGoal else { return }
        store.updateDailyTokenGoal(parsedGoal)
        goalWanText = String(parsedGoal / 10_000)
        saveMessage = "已保存：每日目标 \(formatTokenCount(parsedGoal)) token"
    }

    private func refreshLocal() {
        store.refreshAccountInfo()
        store.refresh()
        saveMessage = "已重新读取本地账号与用量"
    }

    private func accountLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

private struct ProgressMetricRow: View {
    let title: String
    let iconName: String
    let tint: Color
    let percent: Double?
    let detail: String
    let resetText: String

    private var clampedPercent: Double {
        min(max(percent ?? 0, 0), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(percentLabel)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(percent == nil ? .secondary : tint)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.12))

                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.88), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * clampedPercent / 100)
                }
            }
            .frame(height: 7)

            HStack {
                Text(detail)
                Spacer()
                Text(resetText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var percentLabel: String {
        guard let percent else { return "--" }
        return String(format: "%.0f%%", percent)
    }
}

private enum ResetStyle {
    case time
    case date
}

private func percentDetail(_ percent: Double?) -> String {
    guard let percent else { return "暂无数据" }
    return String(format: "已用 %.0f%%，剩余 %.0f%%", percent, max(0, 100 - percent))
}

private func resetText(_ date: Date?, style: ResetStyle) -> String {
    guard let date else { return "等待下一次配额记录" }
    let formatter = DateFormatter()
    formatter.timeZone = .current
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = style == .time ? "HH:mm 重置" : "M月d日 HH:mm 重置"
    return formatter.string(from: date)
}

private func updatedText(_ date: Date?) -> String {
    guard let date else { return "暂无数据" }
    let formatter = DateFormatter()
    formatter.timeZone = .current
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
}

private func verificationText(_ verification: AccountVerification) -> String {
    switch verification {
    case .verifiedLocalAuth:
        return "本地账号已读取"
    case .missingLocalAuth:
        return "未找到本地 Codex 登录"
    }
}

private func verificationIcon(_ verification: AccountVerification) -> String {
    switch verification {
    case .verifiedLocalAuth:
        return "checkmark.seal.fill"
    case .missingLocalAuth:
        return "questionmark.circle"
    }
}

private func verificationColor(_ verification: AccountVerification) -> Color {
    switch verification {
    case .verifiedLocalAuth:
        return .green
    case .missingLocalAuth:
        return .secondary
    }
}

private func planColor(_ plan: String?) -> Color {
    switch plan?.lowercased() {
    case "plus":
        return Color(red: 0.20, green: 0.78, blue: 0.35)
    case "pro":
        return Color(red: 0.58, green: 0.40, blue: 0.94)
    case "team", "enterprise", "business":
        return Color(red: 0.18, green: 0.55, blue: 0.96)
    default:
        return .secondary
    }
}

private func dailyGoalColor(_ percent: Double) -> Color {
    if percent >= 100 {
        return Color(red: 0.20, green: 0.78, blue: 0.35)
    }
    return Color(red: 0.18, green: 0.70, blue: 0.42)
}

private func fiveHourColor(_ percent: Double?) -> Color {
    guard let percent else {
        return Color(red: 0.18, green: 0.70, blue: 0.42)
    }
    if percent >= 80 {
        return .red
    } else if percent >= 65 {
        return .orange
    } else {
        return Color(red: 0.18, green: 0.70, blue: 0.42)
    }
}

private func weeklyColor(_ percent: Double?) -> Color {
    guard let percent else {
        return Color(red: 0.38, green: 0.65, blue: 0.98)
    }
    if percent >= 80 {
        return .red
    } else if percent >= 65 {
        return Color(red: 0.70, green: 0.38, blue: 0.94)
    } else {
        return Color(red: 0.38, green: 0.65, blue: 0.98)
    }
}

private func shortAccountID(_ id: String) -> String {
    guard id.count > 8 else { return id }
    return String(id.prefix(8)) + "..."
}

private func formatTokenCount(_ count: Int) -> String {
    if count >= 100_000_000 {
        return String(format: "%.1f亿", Double(count) / 100_000_000.0)
    } else if count >= 10_000 {
        return String(format: "%.0f万", Double(count) / 10_000.0)
    }
    return "\(count)"
}
