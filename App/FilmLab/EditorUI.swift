//
//  EditorUI.swift
//  剪辑器风格的公共外框：顶部条、底部图标栏、面板滑块、chips。
//  照片页与视频页共用同一套外框 —— 两个页面的手感必须一致，
//  否则同一个「调整」在两个页面里长得不一样，用户会以为进了两个 App。
//

import SwiftUI

// MARK: 顶部条

struct EditorTopBar: View {
    var title: String
    var saveTitle: String = "保存"
    var saveEnabled: Bool = true
    var onBack: () -> Void
    var onSave: () -> Void
    var onReset: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FL.ink)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FL.inkSoft)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let onReset {
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(FL.inkSoft)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(action: onSave) {
                Text(saveTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(saveEnabled ? FL.ochre : FL.card))
                    .foregroundStyle(saveEnabled ? Color.white : FL.inkSoft)
            }
            .buttonStyle(.plain)
            .disabled(!saveEnabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(FL.paper)
    }
}

// MARK: 底部图标栏

struct EditorTabItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let label: String
}

struct EditorTabBar: View {
    let items: [EditorTabItem]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let active = selection == item.id
                Button {
                    selection = item.id
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(active ? FL.ochre : FL.ink)
                        Text(item.label)
                            .font(.system(size: 11, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? FL.ochre : FL.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .background(FL.paperDeep)
        .overlay(alignment: .top) {
            Rectangle().fill(FL.hairline).frame(height: 0.5)
        }
    }
}

// MARK: 面板控件

struct PanelSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: (Double) -> String

    var body: some View {
        VStack(spacing: 1) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FL.ink)
                Spacer(minLength: 0)
                Text(display(value))
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }
            Slider(value: $value, in: range)
                .tint(FL.ochre)
        }
    }
}

struct ChipButton: View {
    let title: String
    var subtitle: String? = nil
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(active ? Color.white.opacity(0.72) : FL.inkSoft)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? Color.white : FL.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? FL.ochre : FL.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(FL.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PanelHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FL.ink)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }
        }
    }
}

/// 面板容器：深色底 + 一条分隔线，让「画面在上、参数在下」的层级清楚
struct PanelBox<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
