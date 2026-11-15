//
//  VideoEngine.swift
//  视频三件事都在这一个文件里：
//    1) 从相册导入（Transferable）
//    2) 播放时逐帧取像素、送进胶片管线渲染到屏幕（实时预览）
//    3) 导出：AVAssetReader 逐帧读 -> Metal 渲染 -> AVAssetWriter 重新编码
//
//  取向说明：预览与导出复用同一个 FilmRenderer 与同一套 uniform，
//  所以「预览看到的」和「导出得到的」是同一段数学。
//

import AVFoundation
import CoreVideo
import CoreTransferable
import Metal
import MetalKit
import UIKit
import UniformTypeIdentifiers

// MARK: - 导入

/// PhotosPicker 拿到的视频：拷进临时目录（系统给的是「借用」的 URL，出了闭包就失效）
struct VideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let dest = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("fl-clip-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFile(url: dest)
        }
    }
}

/// 一个片段。displaySize 已经按视频的旋转变换摆正，rotation 是 0/1/2/3 个 90°。
struct VideoClip: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let displaySize: CGSize
    let rotation: Int
    let duration: Double
    let name: String

    static func make(url: URL, name: String) async -> VideoClip? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        let size = track.naturalSize
        let transform = track.preferredTransform
        // 从 preferredTransform 里读出「内容被摆正需要转几个 90°」
        let angle = atan2(transform.b, transform.a)
        var quarter = Int(round(angle / (.pi / 2)))
        quarter = ((quarter % 4) + 4) % 4
        let rotated = abs(quarter) == 1 || abs(quarter) == 3
        let display = rotated ? CGSize(width: size.height, height: size.width) : size
        let seconds = CMTimeGetSeconds(asset.duration)
        return VideoClip(id: UUID(),
                         url: url,
                         displaySize: display.width > 0 && display.height > 0
                            ? display
                            : CGSize(width: 1080, height: 1920),
                         rotation: quarter,
                         duration: seconds.isFinite ? seconds : 0,
                         name: name)
    }

    var aspect: CGFloat {
        displaySize.height > 0 ? displaySize.width / displaySize.height : 9.0 / 16.0
    }
}

// MARK: - 实时预览

/// 把 AVPlayer 的每一帧取出来，经胶片管线渲染到 MTKView 上。
final class VideoPreviewView: MTKView, MTKViewDelegate {

    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var textureCache: CVMetalTextureCache?
    private var renderer: FilmRenderer?
    private var currentCVTexture: CVMetalTexture?

    private(set) var renderStatus: String = "初始化中"

    init() {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false
        isPaused = false
        clearColor = MTLClearColorMake(0.957, 0.937, 0.906, 1)

        if let device {
            renderer = FilmRenderer(device: device)
            CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
            renderStatus = (renderer?.pipelineReady == true) ? "着色器就绪" : "着色器编译失败"
        } else {
            renderStatus = "这台设备拿不到 Metal"
        }

        delegate = self
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(handlePlaybackEnded),
                                              name: .AVPlayerItemDidPlayToEndTime,
                                              object: nil)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) 不用于这个视图")
    }

    // MARK: 片源 / 参数

    func load(url: URL) {
        player?.pause()

        let item = AVPlayerItem(url: url)
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(videoOutput)
        output = videoOutput

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = false
        player = newPlayer
        renderer?.externalTexture = nil
    }

    func update(params: FilmParams, crop: CGRect, rotation: Int) {
        guard let renderer else { return }
        var u = FilmUniforms.make(params: params, crop: crop, useTexture: true, time: 0, rotation: rotation)
        u.useTexture = 1
        u.time = renderer.uniforms.time
        renderer.uniforms = u
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    var isPlaying: Bool { player?.timeControlStatus == .playing }

    @objc private func handlePlaybackEnded() {
        player?.seek(to: .zero)
        player?.play()
    }

    // MARK: 绘制

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let renderer else { return }

        if let output, let item = player?.currentItem, item.status == .readyToPlay {
            let hostTime = CACurrentMediaTime()
            let itemTime = output.itemTime(forHostTime: hostTime)
            if output.hasNewPixelBuffer(forItemTime: itemTime),
               let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
               let texture = makeTexture(from: buffer) {
                renderer.externalTexture = texture
                renderer.uniforms.useTexture = 1
            }
        } else if renderer.externalTexture == nil {
            renderer.uniforms.useTexture = 0
        }

        renderer.draw(in: view)
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil,
                                                              .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        currentCVTexture = cvTexture
        return texture
    }
}

/// SwiftUI 包装：换片段、改参数、播放暂停都从这里进
struct VideoPreview: UIViewRepresentable {

    var url: URL?
    var params: FilmParams
    var crop: CGRect
    var rotation: Int
    var playToken: Int
    var pauseToken: Int

    final class Coordinator {
        var lastURL: URL?
        var lastPlay = 0
        var lastPause = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        if let url {
            view.load(url: url)
            context.coordinator.lastURL = url
        }
        view.update(params: params, crop: crop, rotation: rotation)
        context.coordinator.lastPlay = playToken
        context.coordinator.lastPause = pauseToken
        return view
    }

    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        if let url, context.coordinator.lastURL != url {
            uiView.load(url: url)
            context.coordinator.lastURL = url
        }
        uiView.update(params: params, crop: crop, rotation: rotation)
        // 递增计数当成「按下播放/暂停」的信号：只有计数变了才动，改参数不会误触发
        if context.coordinator.lastPlay != playToken {
            context.coordinator.lastPlay = playToken
            uiView.play()
        }
        if context.coordinator.lastPause != pauseToken {
            context.coordinator.lastPause = pauseToken
            uiView.pause()
        }
    }
}

// MARK: - 导出

enum VideoExportError: LocalizedError {
    case noVideoTrack
    case metalUnavailable
    case readerFailed(String)
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "这个文件里没有视频轨道"
        case .metalUnavailable: return "这台设备的 Metal 不可用"
        case .readerFailed(let m): return "读取失败：\(m)"
        case .writerFailed(let m): return "编码失败：\(m)"
        }
    }
}

enum VideoExporter {

    /// 在后台把片段按参数重新渲染并编码成 mp4；progress 是 0~1
    static func export(clip: VideoClip,
                       params: FilmParams,
                       crop: CGRect,
                       progress: @escaping (Double) -> Void,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try render(clip: clip, params: params, crop: crop, progress: progress)
                DispatchQueue.main.async { completion(.success(url)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func render(clip: VideoClip,
                               params: FilmParams,
                               crop: CGRect,
                               progress: @escaping (Double) -> Void) throws -> URL {
        let asset = AVURLAsset(url: clip.url)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw VideoExportError.readerFailed("加不进视频输出")
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            if reader.canAdd(out) {
                reader.add(out)
                audioOutput = out
            }
        }

        // 输出尺寸 = 显示尺寸 × 裁剪比例，并强制偶数（H.264 要求）
        var width = Int(clip.displaySize.width * crop.width)
        var height = Int(clip.displaySize.height * crop.height)
        width -= width % 2
        height -= height % 2
        width = max(2, width)
        height = max(2, height)

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filmlab-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)

        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 6,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(videoInput) else { throw VideoExportError.writerFailed("加不进视频输入") }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else {
            throw VideoExportError.writerFailed(writer.error?.localizedDescription ?? "startWriting 失败")
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            throw VideoExportError.readerFailed(reader.error?.localizedDescription ?? "startReading 失败")
        }

        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = FilmRenderer(device: device),
              renderer.pipelineReady else {
            throw VideoExportError.metalUnavailable
        }

        // 目标纹理：每帧渲染到这里，再把像素抄进适配器的 CVPixelBuffer
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                            width: width, height: height,
                                                            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: desc) else {
            throw VideoExportError.metalUnavailable
        }

        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)

        var uniforms = FilmUniforms.make(params: params, crop: crop,
                                         useTexture: true, time: 0, rotation: clip.rotation)

        let frames = max(1, Int(round(max(1, clip.duration) * 24)))
        var processed = 0

        while reader.status == .reading {
            guard videoInput.isReadyForMoreMediaData else {
                Thread.sleep(forTimeInterval: 0.004)
                continue
            }
            guard let sample = videoOutput.copyNextSampleBuffer() else { break }
            guard let pool = adaptor.pixelBufferPool,
                  let sourceBuffer = CMSampleBufferGetImageBuffer(sample)
            else { continue }

            var destination: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination)
            guard let destination else { continue }

            // 源帧 -> 纹理
            var srcCV: CVMetalTexture?
            if let textureCache {
                CVMetalTextureCacheCreateTextureFromImage(
                    nil, textureCache, sourceBuffer, nil, .bgra8Unorm,
                    CVPixelBufferGetWidth(sourceBuffer), CVPixelBufferGetHeight(sourceBuffer), 0, &srcCV)
            }

            if let srcCV, let srcTexture = CVMetalTextureGetTexture(srcCV) {
                let uTime = Float(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)))
                uniforms.time = uTime

                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .dontCare
                pass.colorAttachments[0].storeAction = .store
                if let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
                   let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                    renderer.encode(encoder: encoder, uniforms: uniforms, texture: srcTexture)
                    encoder.endEncoding()
                    commandBuffer.commit()
                    commandBuffer.waitUntilCompleted()
                }

                // 目标纹理 -> CVPixelBuffer
                CVPixelBufferLockBaseAddress(destination, [])
                if let base = CVPixelBufferGetBaseAddress(destination) {
                    let stride = CVPixelBufferGetBytesPerRow(destination)
                    target.getBytes(base, bytesPerRow: stride,
                                    from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                }
                CVPixelBufferUnlockBaseAddress(destination, [])
            }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            if adaptor.append(destination, withPresentationTime: timestamp) {
                processed += 1
            }
            let ratio = min(1.0, Double(processed) / Double(frames))
            progress(ratio)
        }

        videoInput.markAsFinished()

        if let audioOutput, let audioInput {
            while reader.status == .reading {
                guard audioInput.isReadyForMoreMediaData else {
                    Thread.sleep(forTimeInterval: 0.004)
                    continue
                }
                guard let sample = audioOutput.copyNextSampleBuffer() else { break }
                audioInput.append(sample)
            }
            audioInput.markAsFinished()
        }

        writer.endSession(atSourceTime: asset.duration)

        let finishSemaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { finishSemaphore.signal() }
        finishSemaphore.wait()

        if writer.status == .failed {
            throw VideoExportError.writerFailed(writer.error?.localizedDescription ?? "未知错误")
        }
        return outURL
    }
}
