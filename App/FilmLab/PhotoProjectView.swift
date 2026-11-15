//
//  PhotoProjectView.swift
//  照片项目：导入 → 实时调色（离屏渲染，所见即所得）→ 自由裁剪 → 选底片型号 → 导出到相册。
//  预览之所以不用 MTKView 而用「后台渲染 + Image 显示」：调色是静态画面，
//  这条路径没有黑屏/首帧丢失的风险，而且导出与预览走的是同一段着色器数学。
//

import SwiftUI
import PhotosUI
import UIKit

struct PhotoProjectView: View {

    @AppStorage(FLKey.defaultStock) private var defaultStockID: String = "portra400"
    @AppStorage(FLKey.defaultPreset) private var defaultPresetRaw: String = FilmPreset.neutral.rawValue

    @State private var pickedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var previewImage: UIImage?
    @State private var params = FilmStock.all[1].params
    @State private var stockID: String = "portra400"
    @State private var preset: FilmPreset = .neutral
    @State private var crop: CGRect = CropMath.fullRect
    @State private var aspect: CropAspect = CropAspect.all[0]
    @State private var didLoadDefault = false
    @State private var showSavedAlert = false
    @State private var errorText: String?
    @State private var pendingWork: DispatchWorkItem?
    @State private var isRendering = false

    private var imageAspect: CGFloat {
        guard let image, image.size.height > 0 else { return 4.0 / 3.0 }
        return image.size.width / image.size.height
    }

    private var currentStock: FilmStock {
        FilmStock.all.first { $0.id == stockID } ?? FilmStock.none
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewBlock
                    cropCard
                    stockCard
                    paramsCard
                    actionRow
                    privacyLine
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
                    Text(isRendering ? "导出中" : "导出")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(image == nil ? FL.inkSoft : FL.ochre)
                }
                .disabled(image == nil || isRendering)
            }
        }
        .onAppear {
            guard !didLoadDefault else { return }
            didLoadDefault = true
            if let stock = FilmStock.all.first(where: { $0.id == defaultStockID }) {
                stockID = stock.id
            }
            preset = FilmPreset(rawValue: defaultPresetRaw) ?? .neutral
            rebuildParams()
        }
        .onChange(of: pickedItem) { _, newItem in
            importImage(from: newItem)
        }
        .onChange(of: params) { _, _ in
            schedulePreview()
        }
        .alert("已存到相册", isPresented: $showSavedAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text("打开「照片」App，最后一张就是刚导出的图。")
        }
        .alert("出问题了", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) { }
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: 预览 + 裁剪框

    private var previewBlock: some View {
        VStack(spacing: 8) {
            Color.clear
                .aspectRatio(imageAspect, contentMode: .fit)
                .overlay(
                    Group {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                FL.paperDeep
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 22, weight: .regular))
                                        .foregroundStyle(FL.inkSoft)
                                    Text(image == nil ? "还没有照片" : "正在渲染预览…")
                                        .font(.system(size: 13))
                                        .foregroundStyle(FL.inkSoft)
                                }
                            }
                        }
                    }
                )
                .overlay(
                    Group {
                        if image != nil {
                            CropOverlay(crop: $crop,
                                        ratio: aspect.ratio,
                                        imageAspect: imageAspect)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FL.hairline, lineWidth: 1)
                )

            HStack(spacing: 6) {
                Text(image == nil ? "空态 · 测试色卡" : "实时预览 · \(currentStock.displayName)")
                    .font(FL.monoFont)
                    .foregroundStyle(FL.inkSoft)
                Spacer(minLength: 0)
                Text(cropText)
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }
            .padding(.horizontal, 2)
        }
    }

    private var cropText: String {
        guard let image else { return "裁剪 —" }
        let wpx = Int(image.size.width * crop.width)
        let hpx = Int(image.size.height * crop.height)
        return "\(wpx)×\(hpx)"
    }

    // MARK: 裁剪

    private var cropCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("裁剪").flSectionLabel()
                Spacer(minLength: 0)
                Text(aspect.title)
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }

            CropAspectBar(aspect: $aspect, crop: $crop, imageAspect: imageAspect)

            VStack(spacing: 5) {
                HStack {
                    Text("裁剪大小")
                        .font(FL.labelFont)
                        .foregroundStyle(FL.ink)
                    Spacer(minLength: 0)
                    Text(String(format: "%.0f%%", cropScaleFraction * 100))
                        .font(FL.monoFont)
                        .foregroundStyle(FL.ochre)
                }
                Slider(value: Binding(
                    get: { cropScaleFraction },
                    set: { fraction in
                        crop = CropMath.scaled(crop, fraction: fraction,
                                               ratio: aspect.ratio, imageAspect: imageAspect)
                    }
                ), in: 0.1...1.0)
                .tint(FL.ochre)
            }

            HStack(spacing: 12) {
                offsetSlider(title: "水平", value: Binding(
                    get: { Double(crop.minX) },
                    set: { v in
                        var r = crop
                        r.origin.x = min(max(0, CGFloat(v)), 1 - r.width)
                        crop = r
                    }
                ), upper: 1 - crop.width)

                offsetSlider(title: "垂直", value: Binding(
                    get: { Double(crop.minY) },
                    set: { v in
                        var r = crop
                        r.origin.y = min(max(0, CGFloat(v)), 1 - r.height)
                        crop = r
                    }
                ), upper: 1 - crop.height)
            }
        }
        .filmCard(padding: 16)
        .opacity(image == nil ? 0.5 : 1)
        .disabled(image == nil)
    }

    private func offsetSlider(title: String, value: Binding<Double>, upper: CGFloat) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(FL.inkSoft)
                Spacer(minLength: 0)
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(FL.monoFont)
                    .foregroundStyle(FL.inkSoft)
            }
            Slider(value: value, in: 0...Double(max(0.01, upper)))
                .tint(FL.inkSoft)
        }
    }

    private var cropScaleFraction: Double {
        let maxR = CropMath.maxRect(ratio: aspect.ratio, imageAspect: imageAspect)
        guard maxR.width > 0 else { return 1 }
        return Double(min(1.0, max(0.1, crop.width / maxR.width)))
    }

    // MARK: 底片型号

    private var stockCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("底片").flSectionLabel()
                Spacer(minLength: 0)
                Text(currentStock.displayName)
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmStock.all) { stock in
                        let active = stock.id == stockID
                        Button {
                            stockID = stock.id
                            rebuildParams()
                        } label: {
                            VStack(spacing: 2) {
                                Text(stock.brand)
                                    .font(.system(size: 10))
                                    .foregroundStyle(active ? FL.paper.opacity(0.75) : FL.inkSoft)
                                Text(stock.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(active ? FL.paper : FL.ink)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(active ? FL.ink : FL.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(FL.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }

            Text(currentStock.note)
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .filmCard(padding: 16)
    }

    // MARK: 参数

    private var paramsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("调节").flSectionLabel()
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(FilmPreset.allCases) { p in
                        Button {
                            preset = p
                            rebuildParams()
                        } label: {
                            Text(p.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(preset == p ? FL.ink : FL.card))
                                .foregroundStyle(preset == p ? FL.paper : FL.ink)
                                .overlay(Capsule().stroke(FL.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            sliderRow("胶片强度", value: $params.strength, range: 0...1,
                      display: { String(format: "%.0f%%", $0 * 100) })
            sliderRow("颗粒", value: $params.grain, range: 0...0.20,
                      display: { String(format: "%.3f", $0) })
            sliderRow("Halation", value: $params.halo, range: 0...0.40,
                      display: { String(format: "%.0f%%", $0 * 100) })
            sliderRow("色彩密度", value: $params.colorDensity, range: 0...1,
                      display: { String(format: "%.0f%%", $0 * 100) })
            sliderRow("色温", value: $params.colorTemp, range: -1...1,
                      display: { $0 < -0.02 ? "偏冷" : ($0 > 0.02 ? "偏暖" : "中性") })
            sliderRow("色偏", value: $params.tintShift, range: -1...1,
                      display: { $0 < -0.02 ? "偏绿" : ($0 > 0.02 ? "偏品红" : "中性") })
            sliderRow("饱和度", value: $params.chroma, range: 0...1,
                      display: { $0 < 0.05 ? "黑白" : String(format: "%.0f%%", $0 * 100) })

            Divider().overlay(FL.hairline)

            logPicker
        }
        .filmCard(padding: 16)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
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
            Slider(value: value, in: range).tint(FL.ochre)
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
                    Text(image == nil ? "导入照片" : "换一张")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FL.ink))
                .foregroundStyle(FL.paper)
            }

            Button {
                crop = CropMath.fullRect
                aspect = CropAspect.all[0]
                preset = FilmPreset(rawValue: defaultPresetRaw) ?? .neutral
                rebuildParams()
            } label: {
                Text("复位")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FL.card))
                    .foregroundStyle(FL.ink)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FL.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
    }

    private var privacyLine: some View {
        Text("渲染在设备本地完成，不联网、不上传照片。底片型号为风格参考，与各厂商无关联。")
            .font(FL.monoFont)
            .foregroundStyle(FL.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 2)
    }

    // MARK: 逻辑

    private func rebuildParams() {
        params = preset.applied(to: currentStock.params)
        schedulePreview()
    }

    private func importImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data)
            else {
                await MainActor.run { errorText = "这张照片读不出来（可能是 iCloud 里还没下载完的原图）" }
                return
            }
            let normalized = ui.flNormalizedUp()
            await MainActor.run {
                self.image = normalized
                self.crop = CropMath.fullRect
                self.aspect = CropAspect.all[0]
                self.previewImage = nil
                self.schedulePreview(immediate: true)
            }
        }
    }

    private func schedulePreview(immediate: Bool = false) {
        pendingWork?.cancel()
        guard let image else { return }
        let params = self.params
        let work = DispatchWorkItem {
            PreviewRenderer.render(image: image, params: params,
                                   crop: CropMath.fullRect, longSide: 900) { out in
                if let out {
                    self.previewImage = out
                } else {
                    self.errorText = "预览渲染失败：这台设备的 Metal 拒绝出图"
                }
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0.01 : 0.12), execute: work)
    }

    private func export() {
        guard let image else { return }
        isRendering = true
        let params = self.params
        let cropRect = crop
        PreviewRenderer.render(image: image, params: params, crop: cropRect, longSide: 2200) { out in
            self.isRendering = false
            guard let out else {
                self.errorText = "渲染失败：这台设备的 Metal 拒绝出图"
                return
            }
            UIImageWriteToSavedPhotosAlbum(out, nil, nil, nil)
            self.showSavedAlert = true
        }
    }
}

/// 后台串行渲染队列：滑滑块时只保留最后一次渲染，避免把主线程堵住
enum PreviewRenderer {
    static let queue = DispatchQueue(label: "com.filmlab.render", qos: .userInitiated)

    static func render(image: UIImage, params: FilmParams, crop: CGRect,
                       longSide: CGFloat, completion: @escaping (UIImage?) -> Void) {
        queue.async {
            let iw = image.size.width
            let ih = image.size.height
            guard iw > 0, ih > 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let cw = max(1, iw * crop.width)
            let ch = max(1, ih * crop.height)
            let scale = min(1.0, longSide / max(cw, ch))
            let out = FilmRenderer.renderStill(image: image,
                                               params: params,
                                               crop: crop,
                                               width: max(1, Int(cw * scale)),
                                               height: max(1, Int(ch * scale)))
            DispatchQueue.main.async { completion(out) }
        }
    }
}
