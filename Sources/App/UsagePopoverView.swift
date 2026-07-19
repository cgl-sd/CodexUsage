import CodexUsageCore
import SwiftUI

struct UsagePopoverView: View {
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void
    let panelWidth: CGFloat
    let panelHeight: CGFloat

    var body: some View {
        UsageOverviewPane(
            onOpenSettings: onOpenSettings,
            onRefresh: onRefresh,
            onQuit: onQuit
        )
        .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
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
                    detail: "含缓存 \(formatTokenCount(snapshot.todayUsage.totalTokens)) / \(formatTokenCount(snapshot.dailyTokenGoal))",
                    resetText: "不含缓存 \(formatTokenCount(snapshot.todayUsageWithoutCache))"
                )

                ForEach(limitMetrics(from: snapshot.rateLimits)) { metric in
                    ProgressMetricRow(
                        title: metric.title,
                        iconName: metric.iconName,
                        tint: metric.tint,
                        percent: metric.percent,
                        detail: percentDetail(metric.percent),
                        resetText: resetText(metric.resetsAt, style: metric.resetStyle)
                    )
                }
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text("刷新于 \(updatedText(store.lastRefreshCompletedAt))")
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
                        RefreshIcon(isRefreshing: store.isRefreshing)
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

private struct LimitMetric: Identifiable {
    let id: String
    let title: String
    let iconName: String
    let tint: Color
    let percent: Double?
    let resetsAt: Date?
    let resetStyle: ResetStyle
}

private struct RefreshIcon: View {
    let isRefreshing: Bool
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(rotation))
            .frame(width: 20, height: 20)
            .onAppear {
                updateRotation(isRefreshing)
            }
            .onChange(of: isRefreshing) { _, newValue in
                updateRotation(newValue)
            }
    }

    private func updateRotation(_ refreshing: Bool) {
        if refreshing {
            rotation = 0
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                rotation = 0
            }
        }
    }
}

struct UsageSettingsView: View {
    @ObservedObject private var store = UsageStore.shared
    @State private var goalWanText = ""
    @State private var saveMessage = ""
    @State private var updateMessage = ""
    @State private var isCheckingUpdates = false
    @State private var latestDownloadURL: URL?

    var body: some View {
        let account = store.accountInfo

        VStack(alignment: .leading, spacing: 9) {
            Text("设置")
                .font(.title3.weight(.semibold))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("本地账号")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(action: refreshLocal) {
                        Label("重新读取", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }

                accountLine("邮箱", account.email ?? "未读取到")
                accountLine("名称", account.name ?? "未读取到")
                accountLine("计划", account.planType?.uppercased() ?? "未知")

                Text(verificationText(account.verification))
                    .font(.caption)
                    .foregroundStyle(verificationColor(account.verification))
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("每日目标")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    TextField("8000", text: $goalWanText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospacedDigit())
                        .frame(width: 76)
                    Text("万 token / 天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: saveGoal) {
                        Label("保存", systemImage: "checkmark")
                    }
                    .controlSize(.small)
                    .disabled(parsedGoal == nil)
                }

                Text(saveMessage.isEmpty ? "当前目标 \(formatTokenCount(store.snapshot.dailyTokenGoal)) token" : saveMessage)
                    .font(.caption)
                    .foregroundStyle(saveMessage.isEmpty ? Color.secondary : Color.green)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("版本与更新")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    Text("当前版本 \(appVersionText())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: checkForUpdates) {
                        Label(isCheckingUpdates ? "检查中" : "检查更新", systemImage: "arrow.down.circle")
                    }
                    .controlSize(.small)
                    .disabled(isCheckingUpdates)
                }

                if updateMessage.isEmpty == false {
                    Text(updateMessage)
                        .font(.caption)
                        .foregroundStyle(updateMessage.contains("失败") || updateMessage.contains("无法") ? Color.orange : Color.green)
                        .lineLimit(2)
                }

                if let latestDownloadURL {
                    HStack {
                        Spacer()
                        Button(action: { downloadAndOpen(url: latestDownloadURL) }) {
                            Label("下载并打开 DMG", systemImage: "square.and.arrow.down")
                        }
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("数据来源")
                    .font(.subheadline.weight(.semibold))
                sourceLine("用量/限额", usageSourcePath)
                sourceLine("账号", accountSourcePath)
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 360, height: 368)
        .onAppear {
            goalWanText = String(store.snapshot.dailyTokenGoal / 10_000)
        }
    }

    private var parsedGoal: Int? {
        let trimmed = goalWanText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let wan = Double(trimmed), wan > 0 else { return nil }
        return Int((wan * 10_000).rounded())
    }

    private var usageSourcePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex/sessions"
    }

    private var accountSourcePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex/auth.json"
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

    private func checkForUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        updateMessage = ""
        latestDownloadURL = nil

        Task {
            let latest = await fetchLatestRelease()
            await MainActor.run {
                isCheckingUpdates = false
                guard let latest else {
                    updateMessage = "检查失败，请确认网络连接后重试。"
                    return
                }
                let current = appVersionText()
                if isVersion(latest.tagName, newerThan: current) {
                    updateMessage = "发现新版本 \(latest.tagName)，可下载新版 DMG 覆盖安装。"
                    latestDownloadURL = latest.downloadURL
                } else {
                    updateMessage = "当前已是最新版本。"
                }
            }
        }
    }

    private func fetchLatestRelease() async -> (tagName: String, downloadURL: URL?)? {
        guard let url = URL(string: "https://github.com/cgl-sd/CodexUsage/releases/latest") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.setValue("CodexUsage/\(appVersionText())", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 8
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let finalURL = response.url,
                  finalURL.pathComponents.contains("tag"),
                  let tagName = finalURL.pathComponents.last,
                  tagName.isEmpty == false,
                  tagName != "latest"
            else {
                return nil
            }
            let downloadURL = URL(string: "https://github.com/cgl-sd/CodexUsage/releases/download/\(tagName)/CodexUsage.dmg")
            return (tagName, downloadURL)
        } catch {
            return nil
        }
    }

    private func downloadAndOpen(url: URL) {
        updateMessage = "正在下载新版 DMG..."

        Task {
            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.homeDirectoryForCurrentUser
                let destination = downloads.appendingPathComponent("CodexUsage-\(Date().timeIntervalSince1970).dmg")
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)

                await MainActor.run {
                    updateMessage = "已下载到 Downloads，并已打开 DMG。"
                    NSWorkspace.shared.open(destination)
                }
            } catch {
                await MainActor.run {
                    updateMessage = "下载失败，请稍后重试。"
                }
            }
        }
    }

    private func appVersionText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "0.1.5"
    }

    private func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = versionParts(candidate)
        let rhs = versionParts(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private func versionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    private func accountLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private func sourceLine(_ title: String, _ path: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(verbatim: path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
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
                    .layoutPriority(1)
                    .truncationMode(.tail)
                Spacer()
                Text(resetText)
                    .truncationMode(.tail)
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

private func limitMetrics(from rateLimits: RateLimits?) -> [LimitMetric] {
    guard let rateLimits else {
        return [
            LimitMetric(
                id: "quota-placeholder",
                title: "配额用量",
                iconName: "gauge.with.dots.needle.67percent",
                tint: quotaColor(nil, windowMinutes: nil),
                percent: nil,
                resetsAt: nil,
                resetStyle: .date
            )
        ]
    }

    let windows = [
        ("primary", rateLimits.primary),
        ("secondary", rateLimits.secondary),
    ]

    let metrics = windows.compactMap { id, window -> LimitMetric? in
        guard let window, window.usedPercent != nil || window.resetsAt != nil else {
            return nil
        }
        let kind = quotaWindowKind(minutes: window.windowMinutes)
        return LimitMetric(
            id: id,
            title: kind.title,
            iconName: kind.iconName,
            tint: quotaColor(window.usedPercent, windowMinutes: window.windowMinutes),
            percent: window.usedPercent,
            resetsAt: window.resetsAt,
            resetStyle: kind.resetStyle
        )
    }

    if metrics.isEmpty {
        return [
            LimitMetric(
                id: "quota-placeholder",
                title: "配额用量",
                iconName: "gauge.with.dots.needle.67percent",
                tint: quotaColor(nil, windowMinutes: nil),
                percent: nil,
                resetsAt: nil,
                resetStyle: .date
            )
        ]
    }
    return metrics
}

private func quotaWindowKind(minutes: Int?) -> (title: String, iconName: String, resetStyle: ResetStyle) {
    guard let minutes else {
        return ("配额用量", "gauge.with.dots.needle.67percent", .date)
    }
    if minutes == 300 {
        return ("5 小时用量", "clock.fill", .time)
    }
    if minutes == 10_080 {
        return ("周用量", "calendar", .date)
    }
    if minutes < 1_440 {
        let hours = max(1, Int((Double(minutes) / 60.0).rounded()))
        return ("\(hours) 小时用量", "clock.fill", .time)
    }
    let days = max(1, Int((Double(minutes) / 1_440.0).rounded()))
    return ("\(days) 天用量", "calendar", .date)
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

private func quotaColor(_ percent: Double?, windowMinutes: Int?) -> Color {
    let base = (windowMinutes ?? 0) >= 1_440
        ? Color(red: 0.38, green: 0.65, blue: 0.98)
        : Color(red: 0.18, green: 0.70, blue: 0.42)
    guard let percent else {
        return base
    }
    if percent >= 80 {
        return .red
    } else if percent >= 65 {
        return .orange
    } else {
        return base
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
