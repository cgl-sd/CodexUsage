import AppKit
import CodexUsageCore
import Foundation

// 把不同进度的圆形图标渲染成 PNG 到桌面，供视觉确认设计效果
let outDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Desktop/codexusage_icons")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let samples: [(String, Double)] = [
    ("00_pct", 0.0),
    ("04_pct", 0.042),   // 今日真实进度
    ("50_pct", 0.5),
    ("99_pct", 0.99),
    ("100_pct", 1.0),
]

var size: CGFloat = 40  // 放大到 40pt 便于看清细节

for (name, progress) in samples {
    let img = CircularProgressIcon.image(progress: progress, size: size)
    // 透明背景 PNG
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
    let url = outDir.appendingPathComponent("\(name).png")
    try? png.write(to: url)
    print("已生成: \(url.path)")
}

print("\n图标渲染完成，请到桌面 codexusage_icons 文件夹查看 5 种状态。")
