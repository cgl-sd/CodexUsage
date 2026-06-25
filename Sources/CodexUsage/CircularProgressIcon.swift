import AppKit
import CoreGraphics

// MARK: - 圆形进度图标绘制器

/// 按设计绘制菜单栏圆形进度图标。
///
/// 设计规格（严格遵循）：
/// - 外圈是圆环（有背景轨道 + 进度弧）。
/// - 圆内部透明（不画填充）。
/// - 进度弧从 12 点钟（正上方）开始，顺时针填充。
/// - 已完成部分用绿色（系统绿 #34C759）。
/// - 进度 100% 时：整圈填满绿色，圆心绘制白色对勾 ✓。
public enum CircularProgressIcon {
    /// 绘制圆环进度图标。
    /// - Parameters:
    ///   - progress: 0.0–1.0
    ///   - size: 图标点尺寸（菜单栏建议 18–22pt）
    public static func image(progress: Double, size: CGFloat = 20) -> NSImage {
        let clamped = min(max(progress, 0), 1)

        // flipped: false → 标准数学坐标系（y 向上，原点左下）
        // 12 点钟 = π/2，顺时针在屏幕上 = CG 数学上的 clockwise: true
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.interpolationQuality = .high
            ctx.setShouldAntialias(true)

            let lineWidth: CGFloat = max(2.0, size * 0.16)
            let radius = (size - lineWidth) / 2 - 0.5
            let center = CGPoint(x: bounds.midX, y: bounds.midY)

            let green = CGColor(
                red: 0.204, green: 0.780, blue: 0.349, alpha: 1.0
            )  // #34C759

            if clamped >= 1.0 {
                drawFullRing(center: center, radius: radius, lineWidth: lineWidth, color: green, in: ctx)
                drawCheckmark(center: center, radius: radius, in: ctx)
            } else {
                drawTrack(center: center, radius: radius, lineWidth: lineWidth, in: ctx)
                if clamped > 0.001 {
                    drawProgressArc(
                        center: center, radius: radius, lineWidth: lineWidth,
                        progress: clamped, color: green, in: ctx
                    )
                }
            }
            return true
        }

        image.isTemplate = false
        return image
    }

    // MARK: - 绘制部件

    /// 背景轨道：浅灰整圈。
    private static func drawTrack(
        center: CGPoint, radius: CGFloat, lineWidth: CGFloat, in ctx: CGContext
    ) {
        ctx.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.addArc(
            center: center, radius: radius,
            startAngle: 0, endAngle: 2 * .pi, clockwise: false
        )
        ctx.strokePath()
    }

    /// 进度弧：从 12 点钟（π/2）开始，顺时针。
    /// y 向上坐标系中：clockwise: true = 屏幕上顺时针方向。
    private static func drawProgressArc(
        center: CGPoint, radius: CGFloat, lineWidth: CGFloat,
        progress: Double, color: CGColor, in ctx: CGContext
    ) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        let startAngle: CGFloat = .pi / 2  // 12 点钟
        let sweep: CGFloat = .pi * 2 * CGFloat(progress)
        let endAngle = startAngle - sweep   // 顺时针 = 角度递减
        ctx.addArc(
            center: center, radius: radius,
            startAngle: startAngle, endAngle: endAngle, clockwise: true
        )
        ctx.strokePath()
    }

    /// 100% 时的满圈绿色圆环。
    private static func drawFullRing(
        center: CGPoint, radius: CGFloat, lineWidth: CGFloat,
        color: CGColor, in ctx: CGContext
    ) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.addArc(
            center: center, radius: radius,
            startAngle: 0, endAngle: 2 * .pi, clockwise: false
        )
        ctx.strokePath()
    }

    /// 100% 时的绿色对勾 ✓。
    /// y 向上坐标系：y 越大 = 屏幕上越高。
    ///
    /// 对勾形态（✓）：
    ///   p2 ·  ← 右上（终点，最高）
    ///      ╲
    ///   p1 ·  ← 中下（拐点，最低）
    ///    ╱
    ///   p0 ·  ← 左中偏下（起点）
    private static func drawCheckmark(
        center: CGPoint, radius: CGFloat, in ctx: CGContext
    ) {
        let cx = center.x, cy = center.y, r = radius

        // 起点在左侧略低，拐点在中下方，终点在右上方。
        let p0 = CGPoint(x: cx - r * 0.44, y: cy - r * 0.02)
        let p1 = CGPoint(x: cx - r * 0.10, y: cy - r * 0.34)
        let p2 = CGPoint(x: cx + r * 0.48, y: cy + r * 0.30)

        ctx.setStrokeColor(
            CGColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1.0)
        )
        ctx.setLineWidth(max(1.6, r * 0.22))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.move(to: p0)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()
    }
}
