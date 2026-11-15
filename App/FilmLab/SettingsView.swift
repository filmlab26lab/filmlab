//
//  SettingsView.swift
//  设置：默认预设、引擎说明、开发自检入口、关于。
//  从首页左上角进，用 sheet 弹出 —— 设置不是常用页，不该占首页的位置。
//

import SwiftUI

struct SettingsView: View {

    @AppStorage(FLKey.defaultPreset) private var defaultPresetRaw: String = FilmPreset.neutral.rawValue
    @AppStorage(FLKey.defaultStock) private var defaultStockID: String = "portra400"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        stockCard
                        presetCard
                        engineCard
                        toolsCard
                        aboutCard
                    }
                    .padding(18)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FL.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FL.ochre)
                }
            }
        }
        .tint(FL.ochre)
    }

    // MARK: 默认底片

    private var stockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("新建项目的默认底片").flSectionLabel()
                Spacer(minLength: 0)
                Text(currentStockName)
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }

            VStack(spacing: 2) {
                ForEach(FilmStock.all) { stock in
                    Button {
                        defaultStockID = stock.id
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stock.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(FL.ink)
                                Text(stock.note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(FL.inkSoft)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: defaultStockID == stock.id
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(defaultStockID == stock.id ? FL.ochre : FL.inkSoft)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("底片型号是风格参考（按各型号的公开印象拟合），与厂商无关联。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .filmCard(padding: 16)
    }

    private var currentStockName: String {
        FilmStock.all.first { $0.id == defaultStockID }?.displayName ?? "中性 原片"
    }

    // MARK: 默认预设

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建项目的默认预设").flSectionLabel()

            VStack(spacing: 2) {
                ForEach(FilmPreset.allCases) { preset in
                    Button {
                        defaultPresetRaw = preset.rawValue
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.rawValue)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(FL.ink)
                                Text(preset.note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(FL.inkSoft)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: defaultPresetRaw == preset.rawValue
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(defaultPresetRaw == preset.rawValue ? FL.ochre : FL.inkSoft)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .filmCard(padding: 16)
    }

    // MARK: 引擎说明

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("引擎").flSectionLabel()

            Text("负片—染料—相纸三段式，按 Dehancer 那套思路实现四个要素：")
                .font(.system(size: 12))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            engineRow("Halation", "亮部向周围溢出的红橙光晕")
            engineRow("密度联动颗粒", "暗部颗粒更明显，高光更细，不清零")
            engineRow("色彩密度", "中调更饱满，高饱和不收死")
            engineRow("分段胶片曲线", "端点归一，黑位不被曲线自己抬起来")

            Text("Log 还原支持 Rec.709 / S-Log3 / D-Log / N-Log；编码再解码可逆，所以四种模式切换画面应完全一致。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .filmCard(padding: 16)
    }

    private func engineRow(_ title: String, _ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FL.ink)
                .frame(width: 92, alignment: .leading)
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: 开发自检

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开发").flSectionLabel()

            NavigationLink {
                TestView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FL.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("链路自检")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FL.ink)
                        Text("设备 / Metal / Log 可逆性 / 滑块传参")
                            .font(.system(size: 11))
                            .foregroundStyle(FL.inkSoft)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FL.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .filmCard(padding: 16)
    }

    // MARK: 关于

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("关于").flSectionLabel()

            HStack {
                Text("版本")
                    .font(.system(size: 12))
                    .foregroundStyle(FL.inkSoft)
                Spacer(minLength: 0)
                Text(Bundle.main.flVersionText)
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ink)
            }

            Text("所有渲染都在设备本地用 Metal 完成，不联网、不上传照片。测试版采用公开资料的中灰与白点锚点近似曲线，正式上架前会替换为厂商规范数值。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .filmCard(padding: 16)
    }
}
