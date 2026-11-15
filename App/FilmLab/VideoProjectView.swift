//
//  VideoProjectView.swift
//  视频项目：先把工程规格（时长 / 帧率 / 画幅 / 输入 Log）定下来，片段列表这一版是空态。
//  说明白点：视频的逐帧渲染、音轨与导出还没接，这一页给的是工程骨架而不是假按钮。
//

import SwiftUI

enum VideoAspect: String, CaseIterable, Identifiable {
    case landscape = "16:9"
    case portrait = "9:16"
    case square = "1:1"

    var id: String { rawValue }

    var ratio: CGFloat {
        switch self {
        case .landscape: return 16.0 / 9.0
        case .portrait:  return 9.0 / 16.0
        case .square:    return 1.0
        }
    }

    var note: String {
        switch self {
        case .landscape: return "横屏，适合正常视频与放映"
        case .portrait:  return "竖屏，适合短视频平台"
        case .square:    return "方图，适合社交平台信息流"
        }
    }
}

struct VideoProjectView: View {

    @State private var duration: Double = 10
    @State private var fps: Int = 24
    @State private var aspect: VideoAspect = .landscape
    @State private var logMode: LogMode = .rec709
    @State private var showNote = false

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    specBlock
                    timelineBlock
                    roadmapBlock
                    addClipButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("视频项目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FL.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("片段导入还没接", isPresented: $showNote) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("这一版先把工程规格定下来。下一版接视频帧解码 + 逐帧胶片渲染 + 音轨，接好之后这里就能直接拖片段了。")
        }
    }

    // MARK: 工程规格

    private var specBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("工程规格").flSectionLabel()

            durationRow

            Divider().overlay(FL.hairline)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("帧率")
                        .font(FL.labelFont)
                        .foregroundStyle(FL.ink)
                    Spacer(minLength: 0)
                    Text("\(fps) fps")
                        .font(FL.monoFont)
                        .foregroundStyle(FL.ochre)
                }
                Picker("帧率", selection: $fps) {
                    Text("24").tag(24)
                    Text("25").tag(25)
                    Text("30").tag(30)
                }
                .pickerStyle(.segmented)
            }

            Divider().overlay(FL.hairline)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("画幅")
                        .font(FL.labelFont)
                        .foregroundStyle(FL.ink)
                    Spacer(minLength: 0)
                    Text(aspect.rawValue)
                        .font(FL.monoFont)
                        .foregroundStyle(FL.ochre)
                }
                Picker("画幅", selection: $aspect) {
                    ForEach(VideoAspect.allCases) { a in
                        Text(a.rawValue).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                Text(aspect.note)
                    .font(.system(size: 11))
                    .foregroundStyle(FL.inkSoft)
            }

            Divider().overlay(FL.hairline)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("输入色彩空间")
                        .font(FL.labelFont)
                        .foregroundStyle(FL.ink)
                    Spacer(minLength: 0)
                    Text(logMode.title)
                        .font(FL.monoFont)
                        .foregroundStyle(FL.ochre)
                }
                Picker("输入色彩空间", selection: $logMode) {
                    ForEach(LogMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider().overlay(FL.hairline)

            aspectPreview
        }
        .filmCard(padding: 16)
    }

    private var durationRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("时长")
                    .font(FL.labelFont)
                    .foregroundStyle(FL.ink)
                Spacer(minLength: 0)
                Text(String(format: "%.0f 秒", duration))
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }
            Slider(value: $duration, in: 3...30, step: 1)
                .tint(FL.ochre)
            HStack(spacing: 8) {
                quickChip("5 秒") { duration = 5 }
                quickChip("10 秒") { duration = 10 }
                quickChip("15 秒") { duration = 15 }
                Spacer(minLength: 0)
            }
        }
    }

    private func quickChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(FL.paperDeep.opacity(0.7)))
                .foregroundStyle(FL.ink)
        }
        .buttonStyle(.plain)
    }

    /// 画幅的直观示意：一个按比例的小框，比读「16:9」更容易确认
    private var aspectPreview: some View {
        HStack(spacing: 12) {
            Text("画面比例")
                .font(FL.labelFont)
                .foregroundStyle(FL.ink)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FL.paperDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(FL.hairline, lineWidth: 1)
                )
                .frame(width: 54, height: 54 / aspect.ratio)
                .overlay(
                    Text(aspect.rawValue)
                        .font(FL.monoFont)
                        .foregroundStyle(FL.inkSoft)
                )
        }
    }

    // MARK: 片段时间线（空态）

    private var timelineBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("片段").flSectionLabel()
                Spacer(minLength: 0)
                Text("0 个片段")
                    .font(FL.monoFont)
                    .foregroundStyle(FL.inkSoft)
            }

            VStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(FL.inkSoft)
                Text("还没有片段")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FL.ink)
                Text("下一版从相册导入视频，逐帧过胶片管线后再编码导出")
                    .font(.system(size: 11))
                    .foregroundStyle(FL.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FL.card.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FL.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
    }

    private var roadmapBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这一版有什么、没什么").flSectionLabel()

            roadmapRow(done: true, text: "工程规格与胶片参数结构已定")
            roadmapRow(done: true, text: "照片链路完整可用（选片、实时调色、导出）")
            roadmapRow(done: false, text: "视频帧解码与逐帧渲染")
            roadmapRow(done: false, text: "音轨保留与编码导出")
        }
        .filmCard(padding: 16)
    }

    private func roadmapRow(done: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(done ? FL.ochre : FL.inkSoft)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(done ? FL.ink : FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var addClipButton: some View {
        Button {
            showNote = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("添加片段")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FL.card)
            )
            .foregroundStyle(FL.inkSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FL.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
