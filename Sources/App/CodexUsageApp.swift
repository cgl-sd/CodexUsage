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
}

// MARK: - 菜单栏控制器

@MainActor
final class StatusBarController {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateIcon()
        configureButton()
        configurePopover()

        // 数据更新时刷新图标
        UsageStore.shared.onUpdate = { [weak self] in
            self?.updateIcon()
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
        popover.contentSize = NSSize(width: 340, height: 410)
        popover.contentViewController = NSHostingController(
            rootView: UsagePopoverView(
                onRefresh: { UsageStore.shared.refresh() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        )
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
            popover.performClose(nil)
            return
        }

        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showContextMenu() {
        let menu = NSMenu()
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

        popover.performClose(nil)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func didTapRefresh() {
        UsageStore.shared.refresh()
    }
}
