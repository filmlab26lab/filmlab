//
//  PhotoProjectView.swift
//  照片项目：剪辑器外框 —— 顶部条 / 黑底大画幅 / 底部图标栏 + 面板。
//  面板分五格：预设、底片、调整、效果、裁剪；参数改了预览立刻重渲染（离屏，所见即所得）。
//

import SwiftUI
import PhotosUI
import UIKit

struct PhotoProjectView: View {

    @Environment(\.dismiss) private var dismiss

    @AppStorage(FLKey.defaultStock) private var defaultStockID: String = "portra400"
    @AppStorage(FLKey.defaultPreset) private var defaultPresetRaw: String = FilmPreset.neutral.rawValue
    @AppStorage(FLKey.defaultPaper) private var defaultPaperID: String = "crystalArchiveTypeII"

    @State private var pickedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var previewImage: UIImage?
    @State private var params = FilmPaper.all[1].applied(to: FilmStock.all[1].params)
    @State private var stockID: String = "portra400"
    @State private var paperID: String = "crystalArchiveTypeII"
    @State private var preset: FilmPreset = .neutral
    @State private var crop: CGRect = CropMath.fullRect
    @State private var aspect: CropAspect = CropAspect.all[0]
    @State private var tab: String = "adjust"
    @State private var didLoadDefault = false
    @State private var showSavedAlert = false
    @State private var errorText: String?
    @State private var pendingWork: DispatchWorkItem?
    @State private var exporting = false

    private let tabs = [
        EditorTabItem(id: "preset", icon: "camera.filters", label: "预设"),
        EditorTabItem(id: "stock", icon: "film", label: "底片"),
        EditorTabItem(id: "adjust", icon: "slider.horizontal.3", label: "调整"),
        EditorTabItem(id: "effect", icon: "sparkles", label: "效果"),
        EditorTabItem(id: "crop", icon: "crop", label: "裁剪"),
    ]

    private var imageAspect: CGFloat {
        guard let image, image.size.height > 0 else { return 4.0 / 3.0 }
        return image.size.width / image.size.height
    }

    private var currentStock: FilmStock {
        FilmStock.all.first { $0.id == stockID } ?? FilmStock.none
    }

    private var currentPaper: FilmPaper {
        FilmPaper.all.first { $0.id == paperID } ?? FilmPaper.none
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorTopBar(title: currentStock.displayName,
                         saveTitle: exporting ? "导出中" : "保存",
                         saveEnabled: image != nil && !exporting,
                         onBack: { dismiss() },
                         onSave: { export() },
                         onReset: { reset() })

            previewArea

            Divider().overlay(FL.hairline)

            ScrollView {
                panel
            }
            .frame(maxHeight: 268)

            EditorTabBar(items: tabs, selection: $tab)
        }
        .background(FL.paper)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !didLoadDefault else { return }
            didLoadDefault = true
            if let stock = FilmStock.all.first(where: { $0.id == defaultStockID }) {
                stockID = stock.id
            }
            if let paper = FilmPaper.all.first(where: { $0.id == defaultPaperID }) {
                paperID = paper.id
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

    // MARK: 画面

    private var previewArea: some View {
        ZStack {
            Color.black

            Color.clear
                .aspectRatio(imageAspect, contentMode: .fit)
                .overlay(
                    Group {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 26))
                                    .foregroundStyle(FL.inkSoft)
                                Text(image == nil ? "选一张照片开始" : "正在渲染预览…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FL.inkSoft)
                            }
                        }
                    }
                )
                .overlay(
                    Group {
                        if tab == "crop", image != nil {
                            CropOverlay(crop: $crop,
                                        ratio: aspect.ratio,
                                        imageAspect: imageAspect)
                        }
                    }
                )
                .clipped()

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text(image == nil ? "导入照片" : "换一张")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .foregroundStyle(Color.white)
                    }
                    .padding(14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 面板

    @ViewBuilder
    private var panel: some View {
        switch tab {
        case "preset": presetPanel
        case "stock": stockPanel
        case "adjust": adjustPanel
        case "effect": effectPanel
        default: cropPanel
        }
    }

    private var presetPanel: some View {
        PanelBox {
            PanelHeader(title: "力度预设", detail: preset.rawValue)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmPreset.allCases) { p in
                        ChipButton(title: p.rawValue, active: preset == p) {
                            preset = p
                            rebuildParams()
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            Text(preset.note + "。预设只缩放力度，不覆盖底片本身的色味。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stockPanel: some View {
        PanelBox {
            PanelHeader(title: "底片型号", detail: currentStock.displayName)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmStock.all) { stock in
                        ChipButton(title: stock.name, subtitle: stock.brand, active: stock.id == stockID) {
                            stockID = stock.id
                            rebuildParams()
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            Text("\(currentStock.kind.rawValue) · \(currentStock.note)。型号为风格参考，与厂商无关联。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(FL.hairline).padding(.vertical, 4)

            PanelHeader(title: "相纸", detail: currentPaper.displayName)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmPaper.all) { paper in
                        ChipButton(title: paper.name, subtitle: paper.brand, active: paper.id == paperID) {
                            paperID = paper.id
                            rebuildParams()
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            Text(currentPaper.note + "。相纸定的是打印这一段的反差肩部、白点和黑位。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var adjustPanel: some View {
        PanelBox {
            PanelSlider(title: "曝光", value: $params.exposure, range: -1...1,
                        display: { String(format: "%+.2f EV", $0) })
            PanelSlider(title: "对比", value: $params.contrast, range: -1...1,
                        display: { String(format: "%+.0f", $0 * 100) })
            PanelSlider(title: "色温", value: $params.colorTemp, range: -1...1,
                        display: { $0 < -0.02 ? "偏冷" : ($0 > 0.02 ? "偏暖" : "中性") })
            PanelSlider(title: "色偏", value: $params.tintShift, range: -1...1,
                        display: { $0 < -0.02 ? "偏绿" : ($0 > 0.02 ? "偏品红" : "中性") })
            PanelSlider(title: "饱和度", value: $params.chroma, range: 0...1,
                        display: { $0 < 0.05 ? "黑白" : String(format: "%.0f%%", $0 * 100) })
            PanelSlider(title: "胶片强度", value: $params.strength, range: 0...1,
                        display: { String(format: "%.0f%%", $0 * 100) })

            VStack(alignment: .leading, spacing: 6) {
                PanelHeader(title: "输入色彩空间", detail: currentLogMode.title)
                Picker("输入色彩空间", selection: $params.inputMode) {
                    ForEach(LogMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var effectPanel: some View {
        PanelBox {
            PanelSlider(title: "光晕", value: $params.glow, range: 0...1,
                        display: { String(format: "%.0f%%", $0 * 100) })
            PanelSlider(title: "Halation", value: $params.halo, range: 0...0.40,
                        display: { String(format: "%.0f%%", $0 * 100) })
            PanelSlider(title: "颗粒", value: $params.grain, range: 0...0.20,
                        display: { String(format: "%.3f", $0) })
            PanelSlider(title: "色彩密度", value: $params.colorDensity, range: 0...1,
                        display: { String(format: "%.0f%%", $0 * 100) })
            PanelSlider(title: "暗角", value: $params.vignette, range: 0...1,
                        display: { String(format: "%.0f%%", $0 * 100) })
            PanelSlider(title: "黑位抬升", value: $params.blackRaise, range: 0...0.2,
                        display: { String(format: "%.2f", $0) })

            Divider().overlay(FL.hairline).padding(.vertical, 4)
            PanelHeader(title: "相纸（打印段）", detail: currentPaper.displayName)
            PanelSlider(title: "纸反差", value: $params.paperContrast, range: 0...1,
                        display: { String(format: "%.0f%%", $0 * 100) })
            PanelSlider(title: "纸高光压缩", value: $params.paperWhite, range: 0...0.3,
                        display: { String(format: "%.2f", $0) })
            PanelSlider(title: "纸黑位", value: $params.paperBlack, range: 0...0.1,
                        display: { String(format: "%.3f", $0) })
            PanelSlider(title: "纸色偏", value: $params.paperWarmth, range: -0.3...0.3,
                        display: { $0 < -0.02 ? "偏冷" : ($0 > 0.02 ? "偏暖" : "中性") })
            Text("光晕是亮部柔光扩散，Halation 是红橙溢光 —— 两个一起加才像真胶片。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cropPanel: some View {
        PanelBox {
            PanelHeader(title: "比例与裁剪", detail: cropText)
            CropAspectBar(aspect: $aspect, crop: $crop, imageAspect: imageAspect)

            PanelSlider(title: "裁剪大小", value: Binding(
                get: { cropScaleFraction },
                set: { fraction in
                    crop = CropMath.scaled(crop, fraction: fraction,
                                           ratio: aspect.ratio, imageAspect: imageAspect)
                }
            ), range: 0.1...1.0, display: { String(format: "%.0f%%", $0 * 100) })

            HStack(spacing: 14) {
                PanelSlider(title: "水平", value: Binding(
                    get: { Double(crop.minX) },
                    set: { v in
                        var r = crop
                        r.origin.x = min(max(0, CGFloat(v)), 1 - r.width)
                        crop = r
                    }
                ), range: 0...Double(max(0.01, 1 - crop.width)),
                   display: { String(format: "%.2f", $0) })

                PanelSlider(title: "垂直", value: Binding(
                    get: { Double(crop.minY) },
                    set: { v in
                        var r = crop
                        r.origin.y = min(max(0, CGFloat(v)), 1 - r.height)
                        crop = r
                    }
                ), range: 0...Double(max(0.01, 1 - crop.height)),
                   display: { String(format: "%.2f", $0) })
            }
        }
        .opacity(image == nil ? 0.45 : 1)
        .disabled(image == nil)
    }

    // MARK: 派生值

    private var currentLogMode: LogMode {
        LogMode(rawValue: params.inputMode) ?? .rec709
    }

    private var cropText: String {
        guard let image else { return "—" }
        let wpx = Int(image.size.width * crop.width)
        let hpx = Int(image.size.height * crop.height)
        return "\(wpx)×\(hpx)"
    }

    private var cropScaleFraction: Double {
        let maxR = CropMath.maxRect(ratio: aspect.ratio, imageAspect: imageAspect)
        guard maxR.width > 0 else { return 1 }
        return Double(min(1.0, max(0.1, crop.width / maxR.width)))
    }

    // MARK: 逻辑

    private func rebuildParams() {
        // 两段式：先按预设缩放底片的力度，再把相纸叠上去（相纸只动打印这一段）
        params = currentPaper.applied(to: preset.applied(to: currentStock.params))
        schedulePreview()
    }

    private func reset() {
        crop = CropMath.fullRect
        aspect = CropAspect.all[0]
        preset = FilmPreset(rawValue: defaultPresetRaw) ?? .neutral
        stockID = defaultStockID
        paperID = defaultPaperID
        rebuildParams()
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
        guard let image, !exporting else { return }
        exporting = true
        let params = self.params
        let cropRect = crop
        PreviewRenderer.render(image: image, params: params, crop: cropRect, longSide: 2200) { out in
            self.exporting = false
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
