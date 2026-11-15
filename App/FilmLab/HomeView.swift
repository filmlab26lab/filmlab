//
//  HomeView.swift
//  首页：打开就是「新建照片项目 / 新建视频项目」两个入口，左上角是设置入口。
//  设计上刻意只做两件事 —— 首页不该有第三个按钮，复杂的东西都往下钻。
//

import SwiftUI

struct HomeView: View {

    @State private var showSettings = false
    @AppStorage(FLKey.defaultPreset) private var defaultPresetRaw: String = FilmPreset.neutral.rawValue

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                    .padding(.top, 8)

                FilmSprocketStrip(holes: 24)
                    .padding(.top, 18)

                Spacer(minLength: 22)

                VStack(spacing: 14) {
                    NavigationLink {
                        PhotoProjectView()
                    } label: {
                        projectCard(
                            kicker: "PHOTO",
                            icon: "camera.aperture",
                            title: "新建照片项目",
                            note: "选一张照片，实时套胶片冲印管线，调完存进相册"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        VideoProjectView()
                    } label: {
                        projectCard(
                            kicker: "VIDEO",
                            icon: "film",
                            title: "新建视频项目",
                            note: "建立视频工程：时长、帧率、画幅与输入 Log"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 18)

                footer
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FL.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FL.ink)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(FL.card)
                        )
                        .overlay(
                            Circle().stroke(FL.hairline, lineWidth: 1)
                        )
                }
                .accessibilityLabel("设置")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text(Bundle.main.flVersionText)
                    .font(FL.monoFont)
                    .foregroundStyle(FL.inkSoft)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: 标题

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FilmLab")
                .font(FL.titleFont)
                .foregroundStyle(FL.ink)
            Text("负片 · 染料 · 相纸")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(FL.inkSoft)
            Text("当前默认预设：\(defaultPresetTitle)")
                .font(FL.monoFont)
                .foregroundStyle(FL.ochre)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var defaultPresetTitle: String {
        (FilmPreset(rawValue: defaultPresetRaw) ?? .neutral).rawValue
    }

    // MARK: 入口卡片

    private func projectCard(kicker: String, icon: String, title: String, note: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(FL.paperDeep)
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(FL.ink)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(kicker)
                    .font(FL.monoFont)
                    .tracking(1.4)
                    .foregroundStyle(FL.ochre)
                Text(title)
                    .font(FL.cardTitleFont)
                    .foregroundStyle(FL.ink)
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(FL.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FL.inkSoft)
        }
        .filmCard(padding: 16)
    }

    // MARK: 页脚

    private var footer: some View {
        HStack(spacing: 8) {
            Text("负片—染料—相纸链路")
                .font(FL.monoFont)
                .foregroundStyle(FL.inkSoft)
            Spacer(minLength: 0)
            Text("Halation · 颗粒 · 色彩密度 · 分段曲线")
                .font(FL.monoFont)
                .foregroundStyle(FL.inkSoft)
        }
    }
}
