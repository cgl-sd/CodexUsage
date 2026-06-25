import CodexUsageCore
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject private var store = UsageStore.shared
    @State private var isShowingSettings = false

    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        Group {
            if isShowingSettings {
                UsageSettingsPane(
                    onDone: { isShowingSettings = false }
                )
            } else {
                UsageOverviewPane(
                    onOpenSettings: { isShowingSettings = true },
                    onRefresh: onRefresh,
                    onQuit: onQuit
                )
            }
        }
        .frame(width: 340, height: isShowingSettings ? 410 : 330, alignment: .topLeading)
        .background(.regularMaterial)
    }
}

private struct UsageOverviewPane: View {
    @ObservedObject private var store = UsageStore.shared

    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let snapshot = store.snapshot

        VStack(alignment: .leading, spacing: 14) {
            header(snapshot: snapshot)
            accountSummary(store.accountInfo, snapshot: snapshot)

            VStack(spacing: 10) {
                ProgressMetricRow(
                    title: "今日目标",
                    iconName: snapshot.todayProgress >= 1 ? "checkmark.circle.fill" : "target",
                    tint: .green,
                    percent: snapshot.todayProgress * 100,
                    detail: "\(formatTokenCount(snapshot.todayUsage.totalTokens)) / \(formatTokenCount(snapshot.dailyTokenGoal))",
                    resetText: "按本地日期统计"
                )

                ProgressMetricRow(
                    title: "5 小时用量",
                    iconName: "clock.fill",
                    tint: .blue,
                    percent: snapshot.rateLimits?.primary?.usedPercent,
                    detail: percentDetail(snapshot.rateLimits?.primary?.usedPercent),
                    resetText: resetText(snapshot.rateLimits?.primary?.resetsAt, style: .time),
                    sourceText: "配额来源 \(shortDateTime(snapshot.rateLimitsUpdatedAt))"
                )

                ProgressMetricRow(
                    title: "周用量",
                    iconName: "calendar",
                    tint: .purple,
                    percent: snapshot.rateLimits?.secondary?.usedPercent,
                    detail: percentDetail(snapshot.rateLimits?.secondary?.usedPercent),
                    resetText: resetText(snapshot.rateLimits?.secondary?.resetsAt, style: .date),
                    sourceText: "配额来源 \(shortDateTime(snapshot.rateLimitsUpdatedAt))"
                )
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                Text("更新于 \(updatedText(snapshot.lastUpdated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                iconButton("gearshape", help: "设置", action: onOpenSettings)
                iconButton("arrow.clockwise", help: "刷新", action: onRefresh)
                iconButton("power", help: "退出", action: onQuit)
            }
        }
        .padding(16)
    }

    private func header(snapshot: UsageSnapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: CircularProgressIcon.image(progress: snapshot.todayProgress, size: 34))
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Usage")
                    .font(.headline)
                Text("每日目标 \(formatTokenCount(snapshot.dailyTokenGoal)) token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(String(format: "%.1f%%", snapshot.todayProgress * 100))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(snapshot.todayProgress >= 1 ? .green : .primary)
        }
    }

    private func accountSummary(_ account: CodexAccountInfo, snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: verificationIcon(account.verification))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(verificationColor(account.verification))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.email ?? account.name ?? "未设置账号")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(accountSubtitle(account, snapshot: snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct UsageSettingsPane: View {
    @ObservedObject private var store = UsageStore.shared

    @State private var displayName = ""
    @State private var email = ""
    @State private var accountID = ""
    @State private var goalWanText = ""
    @State private var validationMessage = ""

    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onDone) {
                    Image(systemName: "chevron.left")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("返回")

                Text("设置")
                    .font(.headline)
                Spacer()
                Button(action: save) {
                    Image(systemName: "checkmark")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("保存")
                .disabled(parsedGoal == nil)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("账号信息")
                    .font(.subheadline.weight(.semibold))

                LabeledField(title: "显示名", text: $displayName, placeholder: "例如 guangle cao")
                LabeledField(title: "邮箱", text: $email, placeholder: "name@example.com")
                LabeledField(title: "账号 ID", text: $accountID, placeholder: "可留空，验证时可自动填入")

                HStack(spacing: 8) {
                    Button(action: validateFromLocalAuth) {
                        Label("从本地 Codex 验证", systemImage: "checkmark.shield")
                    }
                    .controlSize(.small)

                    Spacer()
                }

                Text(validationMessage.isEmpty ? verificationText(store.accountInfo.verification) : validationMessage)
                    .font(.caption)
                    .foregroundStyle(verificationColor(store.accountInfo.verification))
                    .lineLimit(2)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("每日目标")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    TextField("8000", text: $goalWanText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospacedDigit())
                        .frame(width: 88)
                    Text("万 token / 天")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text("当前目标 \(formatTokenCount(store.snapshot.dailyTokenGoal)) token；本地日志优先用于统计。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("数据来源")
                    .font(.subheadline.weight(.semibold))
                Text("默认使用本地 ~/.codex/sessions 日志统计 token，并读取日志里的 rate_limits 显示 5 小时和周配额。官网数据适合后续作为校验通道。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .onAppear(perform: load)
    }

    private var parsedGoal: Int? {
        let trimmed = goalWanText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let wan = Double(trimmed), wan > 0 else { return nil }
        return Int((wan * 10_000).rounded())
    }

    private func load() {
        let settings = SettingsStore.shared
        displayName = settings.accountDisplayName
        email = settings.accountEmail
        accountID = settings.accountID
        goalWanText = String(store.snapshot.dailyTokenGoal / 10_000)
        validationMessage = ""
    }

    private func save() {
        guard let parsedGoal else { return }
        store.updateAccount(displayName: displayName, email: email, accountID: accountID)
        store.updateDailyTokenGoal(parsedGoal)
        goalWanText = String(parsedGoal / 10_000)
        validationMessage = verificationText(store.accountInfo.verification)
    }

    private func validateFromLocalAuth() {
        let local = store.localAuthAccountInfo()
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            email = local.email ?? ""
        }
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayName = local.name ?? ""
        }
        if accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            accountID = local.accountID ?? ""
        }
        store.updateAccount(displayName: displayName, email: email, accountID: accountID)
        validationMessage = verificationText(store.accountInfo.verification)
    }
}

private struct LabeledField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
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
    var sourceText: String? = nil

    private var clampedPercent: Double {
        min(max(percent ?? 0, 0), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(percentLabel)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(percent == nil ? .secondary : tint)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))

                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: proxy.size.width * clampedPercent / 100)
                }
            }
            .frame(height: 8)

            HStack {
                Text(detail)
                Spacer()
                Text(resetText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let sourceText {
                Text(sourceText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
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

private func shortDateTime(_ date: Date?) -> String {
    guard let date else { return "--" }
    let formatter = DateFormatter()
    formatter.timeZone = .current
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date)
}

private func accountSubtitle(_ account: CodexAccountInfo, snapshot: UsageSnapshot) -> String {
    var parts: [String] = []
    if let plan = account.planType, plan.isEmpty == false {
        parts.append(plan.uppercased())
    } else if let plan = snapshot.rateLimits?.planType, plan.isEmpty == false {
        parts.append(plan.uppercased())
    }
    if let mode = account.authMode, mode.isEmpty == false {
        parts.append(mode)
    }
    if let id = account.accountID, id.isEmpty == false {
        parts.append("账号 \(shortAccountID(id))")
    }
    parts.append(verificationText(account.verification))
    return parts.joined(separator: " · ")
}

private func verificationText(_ verification: AccountVerification) -> String {
    switch verification {
    case .verifiedLocalAuth:
        return "本地验证通过"
    case .mismatchLocalAuth:
        return "与本地 Codex 登录不一致"
    case .manualOnly:
        return "仅手动填写，未验证"
    case .missingLocalAuth:
        return "未找到本地 Codex 登录"
    }
}

private func verificationIcon(_ verification: AccountVerification) -> String {
    switch verification {
    case .verifiedLocalAuth:
        return "checkmark.seal.fill"
    case .mismatchLocalAuth:
        return "exclamationmark.triangle.fill"
    case .manualOnly:
        return "person.crop.circle"
    case .missingLocalAuth:
        return "questionmark.circle"
    }
}

private func verificationColor(_ verification: AccountVerification) -> Color {
    switch verification {
    case .verifiedLocalAuth:
        return .green
    case .mismatchLocalAuth:
        return .orange
    case .manualOnly, .missingLocalAuth:
        return .secondary
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
