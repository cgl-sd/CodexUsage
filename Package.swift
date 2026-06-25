// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodexUsage",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // 数据层 library（无 UI 依赖，可被 App 和验证程序共用）
        .target(
            name: "CodexUsageCore",
            path: "Sources/CodexUsage"
        ),
        // 菜单栏主程序
        .executableTarget(
            name: "CodexUsage",
            dependencies: ["CodexUsageCore"],
            path: "Sources/App"
        ),
        // 临时验证程序（用真实 jsonl 测试扫描器）
        .executableTarget(
            name: "VerifyScan",
            dependencies: ["CodexUsageCore"],
            path: "Sources/VerifyScan"
        ),
        // 图标渲染工具（导出 PNG 供视觉确认）
        .executableTarget(
            name: "RenderIcon",
            dependencies: ["CodexUsageCore"],
            path: "Sources/RenderIcon"
        )
    ]
)

