//
//  PhotoProjectView.swift
//  照片项目：选片 → 实时预览（Metal 管线）→ 调参数 → 离屏渲染导出到相册。
//  空态不画假界面，直接走着色器里的测试色卡，让人一眼看出「管线是活的」。
//

import SwiftUI
import PhotosUI
import UIKit

struct PhotoProjectView: View {

    @AppStorage(FLKey.defaultPreset) private var defaultPresetRaw: String = FilmPreset.neutral.rawValue

    @State private var pickedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var params = FilmPreset.neutral.params()
    @State private var didLoadDefault = false
    @State private var showSavedAlert = false
    @State private var exportError: String?

    private var aspect: CGFloat {
        guard let image, image.size.height > 0 else { return 4.0 / 3.0 }
        return image.size.width / image.size.height
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewBlock
                    presetRow
                    controlsBlock
                    actionRow
                    Text("整条管线在设备本地跑，不联网、不上传照片。")
                        .font(FL.monoFont)
                        .foregroundStyle(FL.inkSoft)
                        .padding(.leading, 2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("照片项目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FL.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    export()
                } label: {
                    Text("导出")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(image == nil ? FL.inkSoft : FL.ochre)
                }
                .disabled(image == nil)
            }
        }
        .onAppear {
            if !didLoadDefault {
                params = (FilmPreset(rawValue: defaultPresetRaw) ?? .neutral).params()
                didLoadDefault = true
            }
        }
        .onChange(of: pickedItem) { _, newItem in
            loadImage(from: newItem)
        }
        .alert("已存到相册", isPresented: $showSavedAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text("打开「照片」App，最后一张就是刚导出的图。")
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("好", role: .cancel) { }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: 预览

    private var previewBlock: some View {
        VStack(spacing: 8) {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .overlay(
                    FilmCanvas(image: image, params: params)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FL.hairline, lineWidth: 1)
                )

            HStack(spacing: 6) {
                Text(image == nil ? "空态 · 测试色卡" : "实时预览 · Metal 管线")
                    .font(FL.monoFont)
                    .foregroundStyle(FL.inkSoft)
                Spacer(minLength: 0)
                Text(String(format: "强度 %.0f%%", params.strength * 100))
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: 预设

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预设").flSectionLabel()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmPreset.allCases) { preset in
                        presetChip(preset)
                    }
                }
                .padding(.vertical, 1)
            }

            Text(activePreset?.note ?? "已手动调整参数")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func presetChip(_ preset: FilmPreset) -> some View {
        let active = (activePreset == preset)
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                params = preset.params()
            }
        } label: {
            Text(preset.rawValue)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? FL.ink : FL.card)
                )
                .foregroundStyle(active ? FL.paper : FL.ink)
                .overlay(
                    Capsule().stroke(FL.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var activePreset: FilmPreset? {
        FilmPreset.allCases.first { $0.params() == params }
    }

    // MARK: 参数

    private var controlsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("胶片参数").flSectionLabel()

            sliderRow("胶片强度", value: $params.strength, range: 0...1,
                      display: { String(format: "%.0f%%", $0 * 100) })
            sliderRow("颗粒", value: $params.grain, range: 0...0.20,
                      display: { String(format: "%.3f", $0) })
            sliderRow("Halation", value: $params.halo, range: 0...0.40,
                      display: { String(format: "%.0f%%", $0 * 100) })
            sliderRow("色彩密度", value: $params.colorDensity, range: 0...1,
                      display: { String(format: "%.0f%%", $0 * 100) })

            Divider().overlay(FL.hairline)

            logPicker
        }
        .filmCard(padding: 16)
    }

    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           display: @escaping (Double) -> String) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(FL.labelFont)
                    .foregroundStyle(FL.ink)
                Spacer(minLength: 0)
                Text(display(value.wrappedValue))
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }
            Slider(value: value, in: range)
                .tint(FL.ochre)
        }
    }

    private var logPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("输入色彩空间")
                    .font(FL.labelFont)
                    .foregroundStyle(FL.ink)
                Spacer(minLength: 0)
                Text(currentLogMode.title)
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }
            Picker("输入色彩空间", selection: $params.inputMode) {
                ForEach(LogMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(currentLogMode.hint)
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentLogMode: LogMode {
        LogMode(rawValue: params.inputMode) ?? .rec709
    }

    // MARK: 操作

    private var actionRow: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 7) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 14, weight: .semibold))
                    Text("选择照片")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FL.ink)
                )
                .foregroundStyle(FL.paper)
            }

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    params = (FilmPreset(rawValue: defaultPresetRaw) ?? .neutral).params()
                }
            } label: {
                Text("复位")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FL.card)
                    )
                    .foregroundStyle(FL.ink)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FL.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: 数据

    private func loadImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data)
            else { return }
            await MainActor.run {
                self.image = ui.flNormalizedUp()
            }
        }
    }

    private func export() {
        guard let image else { return }
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else {
            exportError = "照片尺寸读取失败"
            return
        }

        // 长边压到 1600：手机上看完全够，同时避免大图占内存
        let longSide: CGFloat = 1600
        let scale = min(1.0, longSide / max(w, h))
        let targetW = max(1, Int(w * scale))
        let targetH = max(1, Int(h * scale))

        var uniforms = FilmUniforms()
        uniforms.filmStrength = Float(params.strength)
        uniforms.grainAmount = Float(params.grain)
        uniforms.haloPower = Float(params.halo)
        uniforms.colorDensity = Float(params.colorDensity)
        uniforms.blackRaise = Float(params.blackRaise)
        uniforms.inputMode = Int32(params.inputMode)

        guard let rendered = FilmRenderer.renderStill(image: image,
                                                      uniforms: uniforms,
                                                      width: targetW,
                                                      height: targetH)
        else {
            exportError = "渲染失败：这台设备的 Metal 拒绝出图"
            return
        }

        UIImageWriteToSavedPhotosAlbum(rendered, nil, nil, nil)
        showSavedAlert = true
    }
}

/// 把 FilmMetalView 包成 SwiftUI 视图；照片变了才重建纹理，拖滑块时只更新 uniform
struct FilmCanvas: UIViewRepresentable {

    var image: UIImage?
    var params: FilmParams

    final class Coordinator {
        var lastImageID: ObjectIdentifier?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FilmMetalView {
        let view = FilmMetalView()
        view.apply(inputMode: params.inputMode,
                   filmStrength: params.strength,
                   grain: params.grain,
                   halo: params.halo,
                   colorDensity: params.colorDensity,
                   blackRaise: params.blackRaise)
        if let image {
            view.setInputImage(image)
            context.coordinator.lastImageID = ObjectIdentifier(image)
        }
        return view
    }

    func updateUIView(_ uiView: FilmMetalView, context: Context) {
        uiView.apply(inputMode: params.inputMode,
                     filmStrength: params.strength,
                     grain: params.grain,
                     halo: params.halo,
                     colorDensity: params.colorDensity,
                     blackRaise: params.blackRaise)

        if let image {
            let id = ObjectIdentifier(image)
            if context.coordinator.lastImageID != id {
                uiView.setInputImage(image)
                context.coordinator.lastImageID = id
            }
        } else if context.coordinator.lastImageID != nil {
            uiView.setInputImage(nil)
            context.coordinator.lastImageID = nil
        }
    }
}
