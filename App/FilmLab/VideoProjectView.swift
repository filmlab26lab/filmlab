//
//  VideoProjectView.swift
//  视频项目：片段在最上面，导入 / 实时调色预览 / 比例与参数调节 / 导出，全在片段下面。
//  预览是真的实时：播放时每一帧都过胶片管线（Metal），不是给画面盖一层色片。
//

import SwiftUI
import PhotosUI
import Photos
import UIKit

struct VideoProjectView: View {

    @AppStorage(FLKey.defaultStock) private var defaultStockID: String = "portra400"
    @AppStorage(FLKey.defaultPreset) private var defaultPresetRaw: String = FilmPreset.neutral.rawValue

    @State private var clips: [VideoClip] = []
    @State private var selectedID: UUID?
    @State private var pickedVideo: PhotosPickerItem?
    @State private var stockID: String = "portra400"
    @State private var preset: FilmPreset = .neutral
    @State private var params = FilmStock.all[1].params
    @State private var aspect: CropAspect = CropAspect.all[3]   // 默认 4:3，视频常用
    @State private var playToken = 0
    @State private var pauseToken = 0
    @State private var isPlaying = false
    @State private var exporting = false
    @State private var exportProgress: Double = 0
    @State private var message: String?
    @State private var didLoadDefault = false

    private var selectedClip: VideoClip? {
        clips.first { $0.id == selectedID }
    }

    private var currentStock: FilmStock {
        FilmStock.all.first { $0.id == stockID } ?? FilmStock.none
    }

    /// 视频的裁剪窗口：按所选比例的居中最大框（暂不支持在画面上拖框，视频用比例裁剪更可控）
    private var crop: CGRect {
        guard let clip = selectedClip else { return CropMath.fullRect }
        return CropMath.maxRect(ratio: aspect.ratio, imageAspect: clip.aspect)
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    clipsCard
                    if selectedClip != nil {
                        previewCard
                        paramCard
                        stockCard
                        exportCard
                    } else {
                        emptyHint
                    }
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
        .onAppear {
            guard !didLoadDefault else { return }
            didLoadDefault = true
            if let stock = FilmStock.all.first(where: { $0.id == defaultStockID }) {
                stockID = stock.id
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

    // MARK: 片段（最上面）

    private var clipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("片段").flSectionLabel()
                Spacer(minLength: 0)
                Text("\(clips.count) 个")
                    .font(FL.monoFont)
                    .foregroundStyle(FL.inkSoft)
            }

            if clips.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 24))
                        .foregroundStyle(FL.inkSoft)
                    Text("还没有片段")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FL.ink)
                    Text("从相册导入一段视频，它会立刻按当前参数实时调色")
                        .font(.system(size: 11))
                        .foregroundStyle(FL.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FL.card.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FL.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(clips) { clip in
                        clipRow(clip)
                    }
                }
            }

            PhotosPicker(selection: $pickedVideo, matching: .videos, photoLibrary: .shared()) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text(exporting ? "导出中，先等一下" : "导入视频")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FL.ink))
                .foregroundStyle(FL.paper)
            }
            .disabled(exporting)
        }
        .filmCard(padding: 16)
    }

    private func clipRow(_ clip: VideoClip) -> some View {
        let active = clip.id == selectedID
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? FL.ochre.opacity(0.16) : FL.paperDeep)
                    .frame(width: 40, height: 30)
                Image(systemName: "film")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? FL.ochre : FL.inkSoft)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FL.ink)
                    .lineLimit(1)
                Text(String(format: "%.1f 秒 · %d×%d", clip.duration,
                            Int(clip.displaySize.width), Int(clip.displaySize.height)))
                    .font(FL.monoFont)
                    .foregroundStyle(FL.inkSoft)
            }

            Spacer(minLength: 0)

            Button {
                clips.removeAll { $0.id == clip.id }
                if selectedID == clip.id { selectedID = nil }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(FL.inkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? FL.card : FL.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(active ? FL.ochre.opacity(0.5) : FL.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedID = clip.id
            isPlaying = false
            pauseToken += 1
        }
    }

    private var emptyHint: some View {
        Text("导入一段视频后，这里会出现实时预览、比例与胶片调节。")
            .font(FL.monoFont)
            .foregroundStyle(FL.inkSoft)
            .padding(.leading, 2)
    }

    // MARK: 预览

    private var previewCard: some View {
        VStack(spacing: 10) {
            if let clip = selectedClip {
                Color.clear
                    .aspectRatio(clip.aspect, contentMode: .fit)
                    .overlay(
                        VideoPreview(url: clip.url,
                                     params: params,
                                     crop: crop,
                                     rotation: clip.rotation,
                                     playToken: playToken,
                                     pauseToken: pauseToken)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(FL.hairline, lineWidth: 1)
                    )
                    .overlay(alignment: .bottomLeading) {
                        Text(String(format: "输出 %d×%d",
                                    Int(clip.displaySize.width * crop.width),
                                    Int(clip.displaySize.height * crop.height)))
                            .font(FL.monoFont)
                            .foregroundStyle(FL.paper)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(FL.ink.opacity(0.55)))
                            .padding(10)
                    }

                HStack(spacing: 10) {
                    Button {
                        isPlaying.toggle()
                        if isPlaying { playToken += 1 } else { pauseToken += 1 }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(isPlaying ? "暂停" : "播放")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FL.ink))
                        .foregroundStyle(FL.paper)
                    }
                    .buttonStyle(.plain)

                    Text("逐帧过管线，改参数立刻变")
                        .font(FL.monoFont)
                        .foregroundStyle(FL.inkSoft)

                    Spacer(minLength: 0)
                }
            }
        }
        .filmCard(padding: 12)
    }

    // MARK: 比例与参数

    private var paramCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("画面与调节").flSectionLabel()
                Spacer(minLength: 0)
                Text(aspect.title)
                    .font(FL.monoFont)
                    .foregroundStyle(FL.ochre)
            }

            CropAspectBar(aspect: $aspect, crop: .constant(crop),
                          imageAspect: selectedClip?.aspect ?? (16.0 / 9.0))
                .allowsHitTesting(true)

            Text("视频按所选比例居中裁切（导出尺寸会跟着变）")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)

            Divider().overlay(FL.hairline)

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
                Spacer(minLength: 0)
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
        .filmCard(padding: 16)
    }

    private var currentLogMode: LogMode {
        LogMode(rawValue: params.inputMode) ?? .rec709
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

    // MARK: 底片

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

    // MARK: 导出

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                exportSelectedClip()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: exporting ? "hourglass" : "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                    Text(exporting ? String(format: "导出中 %.0f%%", exportProgress * 100) : "导出到相册")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(exporting ? FL.paperDeep : FL.ochre)
                )
                .foregroundStyle(exporting ? FL.inkSoft : FL.paper)
            }
            .buttonStyle(.plain)
            .disabled(exporting || selectedClip == nil)

            if exporting {
                ProgressView(value: exportProgress)
                    .tint(FL.ochre)
            }

            Text("导出会按当前比例、底片与参数逐帧重新渲染并编码；片子越长越慢，中途别切后台。")
                .font(.system(size: 11))
                .foregroundStyle(FL.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .filmCard(padding: 16)
    }

    // MARK: 逻辑

    private func rebuildParams() {
        params = preset.applied(to: currentStock.params)
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
            await MainActor.run {
                clips.append(clip)
                selectedID = clip.id
                pauseToken += 1
                isPlaying = false
            }
        }
    }

    private func exportSelectedClip() {
        guard let clip = selectedClip, !exporting else { return }
        exporting = true
        exportProgress = 0
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
