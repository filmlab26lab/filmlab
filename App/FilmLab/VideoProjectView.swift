//
//  VideoProjectView.swift
//  视频项目：剪辑器版式 —— 顶部条 / 片段条 / 大画幅预览 / 播放行 / 时间线缩略帧 / 面板 / 图标栏。
//  片段在最上面（用户明确要求），功能调节全在视频下面。
//

import SwiftUI
import PhotosUI
import Photos
import UIKit

struct VideoProjectView: View {

    @Environment(\.dismiss) private var dismiss

    @AppStorage(FLKey.defaultStock) private var defaultStockID: String = "portra400"
    @AppStorage(FLKey.defaultPreset) private var defaultPresetRaw: String = FilmPreset.neutral.rawValue
    @AppStorage(FLKey.defaultPaper) private var defaultPaperID: String = "crystalArchiveTypeII"

    @State private var clips: [VideoClip] = []
    @State private var selectedID: UUID?
    @State private var pickedVideo: PhotosPickerItem?
    @State private var stockID: String = "portra400"
    @State private var paperID: String = "crystalArchiveTypeII"
    @State private var preset: FilmPreset = .neutral
    @State private var params = FilmPaper.all[1].applied(to: FilmStock.all[1].params)
    @State private var aspect: CropAspect = CropAspect.all[3]
    @State private var tab: String = "adjust"
    @State private var playToken = 0
    @State private var pauseToken = 0
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var totalTime: Double = 0
    @State private var thumbs: [UUID: [UIImage]] = [:]
    @State private var exporting = false
    @State private var exportProgress: Double = 0
    @State private var message: String?
    @State private var didLoadDefault = false

    private let tabs = [
        EditorTabItem(id: "preset", icon: "camera.filters", label: "预设"),
        EditorTabItem(id: "stock", icon: "film", label: "底片"),
        EditorTabItem(id: "adjust", icon: "slider.horizontal.3", label: "调整"),
        EditorTabItem(id: "effect", icon: "sparkles", label: "效果"),
        EditorTabItem(id: "aspect", icon: "aspectratio", label: "画幅"),
    ]

    private var selectedClip: VideoClip? {
        clips.first { $0.id == selectedID }
    }

    private var currentStock: FilmStock {
        FilmStock.all.first { $0.id == stockID } ?? FilmStock.none
    }

    private var currentPaper: FilmPaper {
        FilmPaper.all.first { $0.id == paperID } ?? FilmPaper.none
    }

    private var crop: CGRect {
        guard let clip = selectedClip else { return CropMath.fullRect }
        return CropMath.maxRect(ratio: aspect.ratio, imageAspect: clip.aspect)
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorTopBar(title: selectedClip?.name ?? "视频项目",
                         saveTitle: exporting ? String(format: "%.0f%%", exportProgress * 100) : "导出",
                         saveEnabled: selectedClip != nil && !exporting,
                         onBack: { dismiss() },
                         onSave: { exportSelectedClip() },
                         onReset: nil)

            clipStrip
            previewArea
            playbackRow
            timeline
            Divider().overlay(FL.hairline)
            ScrollView {
                panel
            }
            .frame(maxHeight: 226)
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
        .onChange(of: pickedVideo) { _, item in
            importVideo(from: item)
        }
        .alert("提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) { }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: 片段条（最上面）

    private var clipStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(clips) { clip in
                        let active = clip.id == selectedID
                        HStack(spacing: 6) {
                            Image(systemName: "film")
                                .font(.system(size: 11, weight: .semibold))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(clip.name)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(timeString(clip.duration))
                                    .font(.system(size: 9))
                                    .foregroundStyle(active ? Color.white.opacity(0.7) : FL.inkSoft)
                            }
                            Button {
                                clips.removeAll { $0.id == clip.id }
                                thumbs[clip.id] = nil
                                if selectedID == clip.id {
                                    let next = clips.first
                                    selectedID = next?.id
                                    currentTime = 0
                                    totalTime = next?.duration ?? 0
                                    isPlaying = false
                                    pauseToken += 1
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(active ? Color.white.opacity(0.8) : FL.inkSoft)
                                    .padding(4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(active ? FL.ochre : FL.card)
                        )
                        .foregroundStyle(active ? Color.white : FL.ink)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedID = clip.id
                            currentTime = 0
                            totalTime = clip.duration
                            isPlaying = false
                            pauseToken += 1
                        }
                    }

                    if clips.isEmpty {
                        Text("还没有片段，点右边导入")
                            .font(.system(size: 11))
                            .foregroundStyle(FL.inkSoft)
                            .padding(.vertical, 8)
                    }
                }
            }

            PhotosPicker(selection: $pickedVideo, matching: .videos, photoLibrary: .shared()) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FL.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(FL.card))
                    .overlay(Circle().stroke(FL.hairline, lineWidth: 1))
            }
            .disabled(exporting)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: 画面

    private var previewArea: some View {
        ZStack {
            Color.black

            if let clip = selectedClip {
                let shownAspect = imageAspectForDisplay(clip)
                Color.clear
                    .aspectRatio(shownAspect, contentMode: .fit)
                    .overlay(
                        VideoPreview(url: clip.url,
                                     params: params,
                                     crop: crop,
                                     rotation: clip.rotation,
                                     playToken: playToken,
                                     pauseToken: pauseToken,
                                     onTime: { t, d in
                                         currentTime = t
                                         totalTime = d
                                     })
                    )
                    .clipped()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 26))
                        .foregroundStyle(FL.inkSoft)
                    Text("导入一段视频，播放时逐帧调色")
                        .font(.system(size: 12))
                        .foregroundStyle(FL.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 预览容器比例：按画幅比例显示，画面才能看出裁剪后的构图
    private func imageAspectForDisplay(_ clip: VideoClip) -> CGFloat {
        guard let ratio = aspect.ratio else { return clip.aspect }
        return ratio
    }

    // MARK: 播放行

    private var playbackRow: some View {
        HStack {
            Text(timeString(currentTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(FL.ink)

            Spacer()

            Button {
                guard selectedClip != nil else { return }
                isPlaying.toggle()
                if isPlaying { playToken += 1 } else { pauseToken += 1 }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FL.ink)
                    .frame(width: 34, height: 26)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(timeString(totalTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(FL.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: 时间线

    private var timeline: some View {
        GeometryReader { geo in
            let list = selectedClip.flatMap { thumbs[$0.id] } ?? []
            let n = max(1, list.count)
            let w = geo.size.width / CGFloat(n)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { i in
                        Group {
                            if i < list.count {
                                Image(uiImage: list[i])
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Rectangle().fill(FL.paperDeep)
                                    .overlay(
                                        Image(systemName: "film")
                                            .font(.system(size: 10))
                                            .foregroundStyle(FL.inkSoft)
                                    )
                            }
                        }
                        .frame(width: w, height: 54)
                        .clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                // 播放头
                if selectedClip != nil {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 1.5, height: 54)
                        .offset(x: max(0, min(geo.size.width - 1.5, geo.size.width * playProgress)))
                }
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var playProgress: Double {
        guard totalTime > 0 else { return 0 }
        return min(1, max(0, currentTime / totalTime))
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: 面板

    @ViewBuilder
    private var panel: some View {
        switch tab {
        case "preset": presetPanel
        case "stock": stockPanel
        case "effect": effectPanel
        case "aspect": aspectPanel
        default: adjustPanel
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
            Text("导出会把当前比例、底片、全部参数一起烘进画面。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aspectPanel: some View {
        PanelBox {
            PanelHeader(title: "画幅", detail: outputSizeText)
            CropAspectBar(aspect: $aspect, crop: .constant(crop),
                          imageAspect: selectedClip?.aspect ?? (16.0 / 9.0))
            Text("视频按所选比例居中裁切，导出尺寸跟着变；照片页里可以自由拖框。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(selectedClip == nil ? 0.45 : 1)
        .disabled(selectedClip == nil)
    }

    private var currentLogMode: LogMode {
        LogMode(rawValue: params.inputMode) ?? .rec709
    }

    private var outputSizeText: String {
        guard let clip = selectedClip else { return "—" }
        return String(format: "%d×%d",
                      Int(clip.displaySize.width * crop.width),
                      Int(clip.displaySize.height * crop.height))
    }

    // MARK: 逻辑

    private func rebuildParams() {
        params = currentPaper.applied(to: preset.applied(to: currentStock.params))
    }

    private func importVideo(from item: PhotosPickerItem?) {
        guard let item else { return }
        let clipName = "片段 \(clips.count + 1)"
        Task {
            guard let file = try? await item.loadTransferable(type: VideoFile.self) else {
                await MainActor.run { message = "这段视频读不出来，换一段试试" }
                return
            }
            guard let clip = await VideoClip.make(url: file.url, name: clipName) else {
                await MainActor.run { message = "这个文件里没有视频轨道" }
                return
            }
            let strip = await ClipThumbnails.make(url: clip.url, count: 10)
            await MainActor.run {
                clips.append(clip)
                selectedID = clip.id
                thumbs[clip.id] = strip
                currentTime = 0
                totalTime = clip.duration
                isPlaying = false
                pauseToken += 1
            }
        }
    }

    private func exportSelectedClip() {
        guard let clip = selectedClip, !exporting else { return }
        exporting = true
        exportProgress = 0
        pauseToken += 1
        isPlaying = false
        let params = self.params
        let cropRect = crop
        VideoExporter.export(clip: clip, params: params, crop: cropRect, progress: { p in
            self.exportProgress = p
        }, completion: { result in
            self.exporting = false
            switch result {
            case .success(let url):
                saveToLibrary(url)
            case .failure(let error):
                self.message = error.localizedDescription
            }
        })
    }

    private func saveToLibrary(_ url: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completionHandler: { ok, error in
            DispatchQueue.main.async {
                if ok {
                    self.message = "已导出到相册"
                } else {
                    self.message = "存相册失败：\(error?.localizedDescription ?? "未知原因")"
                }
            }
        })
    }
}
