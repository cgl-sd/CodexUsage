import AppKit
import CodexUsageCore
import ObjectiveC
import SwiftUI

// MARK: - 应用入口

@main
enum CodexUsageApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // 不在 Dock 显示，只在菜单栏运行
        let delegate = AppDelegate()
        app.delegate = delegate
        // 保持 delegate 存活：NSApplication.delegate 是 weak 属性
        objc_setAssociatedObject(app, &Self.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        app.run()
    }

    private nonisolated(unsafe) static var delegateKey: UInt8 = 0
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusBarController.shared.setup()
        UsageStore.shared.start()
    }

    func applicationDidResignActive(_ notification: Notification) {
        StatusBarController.shared.closePopover()
    }
}

// MARK: - 菜单栏控制器

@MainActor
final class StatusBarController {
    static let shared = StatusBarController()

    private let popoverWidth: CGFloat = 320
    private let compactPopoverHeight: CGFloat = 332
    private let regularPopoverHeight: CGFloat = 352
    private let settingsWindowSize = NSSize(width: 360, height: 368)

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var settingsCloseObserver: NSObjectProtocol?
    private var popoverCloseObserver: NSObjectProtocol?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var currentPopoverHeight: CGFloat?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateIcon()
        configureButton()
        configurePopover()

        // 数据更新时刷新图标
        UsageStore.shared.onUpdate = { [weak self] in
            self?.updateIcon()
            self?.updatePopoverSize()
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(didClickStatusItem)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        updatePopoverSize()
        popoverCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removePopoverDismissHandlers()
            }
        }
    }

    // MARK: - 图标

    private func updateIcon() {
        let progress = UsageStore.shared.snapshot.todayProgress
        if let button = statusItem.button {
            button.image = CircularProgressIcon.image(progress: progress, size: 20)
        }
    }

    // MARK: - 下拉内容

    @objc private func didClickStatusItem() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }

        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        updatePopoverSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installPopoverDismissHandlers()
    }

    private func updatePopoverSize() {
        let height = popoverHeight(for: UsageStore.shared.snapshot.rateLimits)
        let size = NSSize(width: popoverWidth, height: height)
        let shouldRebuildContent = popover.contentViewController == nil || currentPopoverHeight != height

        if popover.contentSize != size {
            popover.contentSize = size
        }
        currentPopoverHeight = height

        guard shouldRebuildContent else {
            popover.contentViewController?.preferredContentSize = size
            return
        }

        let rootView = UsagePopoverView(
            onOpenSettings: { [weak self] in self?.openSettingsWindow() },
            onRefresh: { UsageStore.shared.refresh() },
            onQuit: { NSApplication.shared.terminate(nil) },
            panelWidth: popoverWidth,
            panelHeight: height
        )

        if let hostingController = popover.contentViewController as? NSHostingController<UsagePopoverView> {
            hostingController.rootView = rootView
            hostingController.preferredContentSize = size
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.preferredContentSize = size
            popover.contentViewController = hostingController
        }
    }

    private func popoverHeight(for rateLimits: RateLimits?) -> CGFloat {
        quotaWindowCount(from: rateLimits) <= 1 ? compactPopoverHeight : regularPopoverHeight
    }

    private func quotaWindowCount(from rateLimits: RateLimits?) -> Int {
        guard let rateLimits else { return 1 }
        let windows = [rateLimits.primary, rateLimits.secondary]
        let count = windows.filter { window in
            guard let window else { return false }
            return window.usedPercent != nil || window.resetsAt != nil
        }.count
        return max(1, count)
    }

    func closePopover() {
        guard popover.isShown else {
            removePopoverDismissHandlers()
            return
        }
        popover.performClose(nil)
        removePopoverDismissHandlers()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(didTapSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let refreshItem = NSMenuItem(
            title: "刷新",
            action: #selector(didTapRefresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        // 退出
        let quitItem = NSMenuItem(
            title: "退出 CodexUsage",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        closePopover()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func didTapRefresh() {
        UsageStore.shared.refresh()
    }

    @objc private func didTapSettings() {
        openSettingsWindow()
    }

    private func openSettingsWindow() {
        closePopover()

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: settingsWindowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodexUsage 设置"
        placeSettingsWindowNearStatusItem(window)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: UsageSettingsView())
        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let observer = self.settingsCloseObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                self.settingsCloseObserver = nil
                self.settingsWindow = nil
            }
        }
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func placeSettingsWindowNearStatusItem(_ window: NSWindow) {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            window.center()
            return
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrame = buttonWindow.convertToScreen(buttonFrameInWindow)
        let visible = screen.visibleFrame
        let gap: CGFloat = 8

        var origin = NSPoint(
            x: buttonFrame.midX - settingsWindowSize.width / 2,
            y: buttonFrame.minY - settingsWindowSize.height - gap
        )
        origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - settingsWindowSize.width - gap)
        origin.y = min(max(origin.y, visible.minY + gap), visible.maxY - settingsWindowSize.height - gap)

        window.setFrame(NSRect(origin: origin, size: settingsWindowSize), display: false)
    }

    private func installPopoverDismissHandlers() {
        removePopoverDismissHandlers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.closePopoverIfClickIsOutside(event)
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
    }

    private func removePopoverDismissHandlers() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func closePopoverIfClickIsOutside(_ event: NSEvent) {
        guard popover.isShown else { return }
        if event.window == popover.contentViewController?.view.window {
            return
        }
        if let button = statusItem.button,
           event.window == button.window,
           button.bounds.contains(button.convert(event.locationInWindow, from: nil)) {
            return
        }
        closePopover()
    }
}
