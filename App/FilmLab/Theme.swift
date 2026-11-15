//
//  Theme.swift
//  FilmLab 的视觉基调：相纸暖白 + 墨黑 + 胶片橙，克制的圆角与细描边。
//  之所以单独抽一个文件：颜色、字体、底纹三样东西被每个页面复用，
//  散落在各视图里改一次配色就要改八处，这是最容易让界面「越改越脏」的写法。
//

import SwiftUI

enum FL {
    /// 相纸底色：略暖的米白，不是纯白 —— 纯白在 OLED 上会显得刺眼、也不像胶片
    static let paper = Color(red: 0.957, green: 0.937, blue: 0.906)
    /// 纸的暗部，用在卡片投影与装饰
    static let paperDeep = Color(red: 0.910, green: 0.884, blue: 0.845)
    /// 墨色文字（不用纯黑，纯黑在暖底上会发脏）
    static let ink = Color(red: 0.106, green: 0.098, blue: 0.086)
    /// 次要文字
    static let inkSoft = Color(red: 0.106, green: 0.098, blue: 0.086).opacity(0.52)
    /// 胶片橙：只用在关键数值、强调按钮上，一页不要超过三处
    static let ochre = Color(red: 0.769, green: 0.388, blue: 0.137)
    /// 卡片底：比纸再亮一点，形成层次
    static let card = Color(red: 0.990, green: 0.982, blue: 0.964)
    /// 细描边
    static let hairline = Color(red: 0.106, green: 0.098, blue: 0.086).opacity(0.12)

    static let titleFont = Font.system(size: 32, weight: .semibold, design: .serif)
    static let cardTitleFont = Font.system(size: 17, weight: .semibold, design: .serif)
    static let labelFont = Font.system(size: 13, weight: .medium)
    static let monoFont = Font.system(size: 11, weight: .medium, design: .monospaced)
}

/// 纸感底纹：顶部一层暖光 + 一层极淡噪点，模拟相纸纹理。
/// 噪点是确定性算法生成的（同一次渲染每次一样），不用随机数，避免界面「呼吸」。
struct PaperBackground: View {
    var body: some View {
        ZStack {
            FL.paper
            LinearGradient(
                colors: [Color.white.opacity(0.50), Color.clear, FL.paperDeep.opacity(0.70)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GrainOverlay(strength: 0.05)
        }
        .ignoresSafeArea()
    }
}

struct GrainOverlay: View {
    var strength: Double = 0.05

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func nextUnit() -> Double {
                seed ^= seed << 13
                seed ^= seed >> 7
                seed ^= seed << 17
                return Double(seed % 10_000) / 10_000.0
            }
            let count = max(120, Int(size.width * size.height / 1_400))
            for _ in 0..<count {
                let x = nextUnit() * size.width
                let y = nextUnit() * size.height
                let d = 0.6 + nextUnit() * 1.2
                let rect = CGRect(x: x, y: y, width: d, height: d)
                context.fill(Path(rect), with: .color(FL.ink.opacity(strength * (0.35 + nextUnit() * 1.0))))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 胶片齿孔装饰条：首页用来做一个很轻的「胶片」暗示，不做成拟物大图
struct FilmSprocketStrip: View {
    var holes: Int = 20

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<holes, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(FL.ink.opacity(0.13))
                    .frame(width: 5, height: 8)
            }
        }
    }
}

/// 统一的卡片样式：亮底 + 细描边 + 很轻的投影
struct FilmCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FL.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(FL.hairline, lineWidth: 1)
            )
            .shadow(color: FL.ink.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func filmCard(padding: CGFloat = 16) -> some View {
        modifier(FilmCard(padding: padding))
    }

    /// 小标题：全大写 + 字距，用来给区块开头
    func flSectionLabel() -> some View {
        self.font(FL.monoFont)
            .foregroundStyle(FL.inkSoft)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}
