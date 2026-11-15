//
//  Theme.swift
//  FilmLab 的视觉基调：相纸暖白 + 墨黑 + 胶片橙，克制的圆角与细描边。
//  之所以单独抽一个文件：颜色、字体、底纹三样东西被每个页面复用，
//  散落在各视图里改一次配色就要改八处，这是最容易让界面「越改越脏」的写法。
//

import SwiftUI

enum FL {
    /// 编辑器底色：近黑（不是纯黑，纯黑在 OLED 上与画面边界会糊在一起）
    static let paper = Color(red: 0.055, green: 0.055, blue: 0.063)
    /// 比底色略亮一层，用在底栏、时间线槽
    static let paperDeep = Color(red: 0.094, green: 0.094, blue: 0.102)
    /// 主文字（不用纯白，纯白在大面积黑底上会跳）
    static let ink = Color(red: 0.925, green: 0.925, blue: 0.937)
    /// 次要文字与未选中的图标
    static let inkSoft = Color(red: 0.925, green: 0.925, blue: 0.937).opacity(0.52)
    /// 胶片橙：只用在选中项、关键数值、主按钮上，一页不要超过三处
    static let ochre = Color(red: 0.910, green: 0.451, blue: 0.235)
    /// 面板底：比底栏再亮一点，形成层次
    static let card = Color(red: 0.125, green: 0.125, blue: 0.137)
    /// 细描边
    static let hairline = Color(red: 0.925, green: 0.925, blue: 0.937).opacity(0.12)
    /// 遮罩与分隔用的纯黑
    static let veil = Color.black.opacity(0.55)

    static let titleFont = Font.system(size: 32, weight: .semibold, design: .serif)
    static let cardTitleFont = Font.system(size: 17, weight: .semibold, design: .serif)
    static let labelFont = Font.system(size: 13, weight: .medium)
    static let monoFont = Font.system(size: 11, weight: .medium, design: .monospaced)
}

/// 底纹：顶部一层极淡的冷光 + 一层确定性噪点，深色底下这点颗粒感是「剪辑台」的味道
struct PaperBackground: View {
    var body: some View {
        ZStack {
            FL.paper
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.clear, Color.black.opacity(0.35)],
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
