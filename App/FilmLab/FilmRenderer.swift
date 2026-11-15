//
//  FilmRenderer.swift
//  胶片管线在 Metal 上的实现入口：
//    · 屏幕预览（MTKView 持续绘制，视频播放走这条）
//    · 离屏出图（照片预览与导出走这条，所见即所得）
//
//  两种片源：
//    · 静态图（照片）—— 采样 inputTexture
//    · 视频帧（CVPixelBuffer）—— 由 VideoEngine 每帧塞进 externalTexture
//    · 都没有时 —— 着色器内置测试色卡，当空态用
//

import UIKit
import MetalKit
import CoreVideo
import QuartzCore

/// 与着色器里 struct Uniforms 一一对应（字段顺序、类型都不能改，改一处两边都要改）
struct FilmUniforms {
    var time: Float = 0
    var filmStrength: Float = 0.60
    var grainAmount: Float = 0.05
    var haloPower: Float = 0.16
    var colorDensity: Float = 0.85
    var blackRaise: Float = 0.03
    var inputMode: Int32 = 0
    var useTexture: Int32 = 0
    var cropX: Float = 0
    var cropY: Float = 0
    var cropW: Float = 1
    var cropH: Float = 1
    var colorTemp: Float = 0
    var tintShift: Float = 0
    var chroma: Float = 1
    var rotateQuarter: Int32 = 0
    var exposure: Float = 0
    var contrast: Float = 0
    var glow: Float = 0.10
    var vignette: Float = 0.18

    /// 从界面参数生成 uniform；裁剪是归一化到源图的窗口
    static func make(params: FilmParams, crop: CGRect, useTexture: Bool,
                     time: Float = 0, rotation: Int = 0) -> FilmUniforms {
        var u = FilmUniforms()
        u.time = time
        u.filmStrength = Float(params.strength)
        u.grainAmount = Float(params.grain)
        u.haloPower = Float(params.halo)
        u.colorDensity = Float(params.colorDensity)
        u.blackRaise = Float(params.blackRaise)
        u.inputMode = Int32(params.inputMode)
        u.useTexture = useTexture ? 1 : 0
        u.cropX = Float(crop.minX)
        u.cropY = Float(crop.minY)
        u.cropW = Float(max(0.001, crop.width))
        u.cropH = Float(max(0.001, crop.height))
        u.colorTemp = Float(params.colorTemp)
        u.tintShift = Float(params.tintShift)
        u.chroma = Float(params.chroma)
        u.rotateQuarter = Int32(rotation)
        u.exposure = Float(params.exposure)
        u.contrast = Float(params.contrast)
        u.glow = Float(params.glow)
        u.vignette = Float(params.vignette)
        return u
    }
}

final class FilmRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private(set) var pipelineState: MTLRenderPipelineState?
    private(set) var samplerState: MTLSamplerState?
    private(set) var inputTexture: MTLTexture?
    private(set) var dummyTexture: MTLTexture?

    /// 视频帧纹理：由 VideoEngine 每帧覆盖，优先于静态图
    var externalTexture: MTLTexture?

    private let startTime = CACurrentMediaTime()

    /// 着色器是否编译成功
    private(set) var pipelineReady = false

    var uniforms = FilmUniforms()

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()
        buildPipeline()
        buildSampler()
        buildDummyTexture()
    }

    // MARK: 资源准备

    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "fullscreen_vertex"),
              let fragmentFn = library.makeFunction(name: "film_fragment") else {
            return
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "FilmLabPipeline"
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        pipelineReady = (pipelineState != nil)
    }

    private func buildSampler() {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: d)
    }

    private func buildDummyTexture() {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                        width: 1, height: 1, mipmapped: false)
        d.usage = [.shaderRead]
        dummyTexture = device.makeTexture(descriptor: d)
    }

    /// 换成静态片源；传 nil 回到测试色卡
    func setInputImage(_ image: UIImage?) {
        guard let image, let cg = image.flNormalizedUp().flSRGB8Bit().cgImage else {
            inputTexture = nil
            uniforms.useTexture = 0
            return
        }
        // 自己建纹理而不是用 MTKTextureLoader：Loader 对非 sRGB / 非 8bit 的 CGImage
        // 会抛错（相册里 P3、10bit 的照片很常见），表现就是「选了照片却什么都不显示」。
        inputTexture = Self.makeTexture(device: device, cgImage: cg)
        uniforms.useTexture = (inputTexture != nil) ? 1 : 0
    }

    var hasInputImage: Bool { inputTexture != nil }

    /// 把任意 CGImage 规整成 bgra8Unorm 纹理
    static func makeTexture(device: MTLDevice, cgImage: CGImage) -> MTLTexture? {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }

        let bytesPerRow = w * 4
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                        width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: d) else { return nil }

        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        let ok: Bool = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue)
            else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }

        texture.replace(region: MTLRegionMake2D(0, 0, w, h),
                        mipmapLevel: 0, withBytes: bytes, bytesPerRow: bytesPerRow)
        return texture
    }

    // MARK: 绘制

    private var activeTexture: MTLTexture? {
        externalTexture ?? inputTexture ?? dummyTexture
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipelineState,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        uniforms.time = Float(CACurrentMediaTime() - startTime)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FilmUniforms>.stride, index: 0)
        encoder.setFragmentTexture(activeTexture, index: 0)
        if let samplerState {
            encoder.setFragmentSamplerState(samplerState, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// 把一帧编码进外部 encoder（视频导出用）
    func encode(encoder: MTLRenderCommandEncoder, uniforms u: FilmUniforms, texture: MTLTexture?) {
        guard let pipelineState else { return }
        var uu = u
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uu, length: MemoryLayout<FilmUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture ?? dummyTexture, index: 0)
        if let samplerState {
            encoder.setFragmentSamplerState(samplerState, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: 离屏出图

    /// 把一张静态图按参数 + 裁剪渲染成 UIImage。
    /// 宽高应当等于「裁剪后」的输出尺寸 —— 着色器会把裁剪窗口铺满整个输出纹理。
    static func renderStill(image: UIImage?, params: FilmParams, crop: CGRect,
                            width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0,
              let device = MTLCreateSystemDefaultDevice(),
              let renderer = FilmRenderer(device: device),
              renderer.pipelineReady
        else { return nil }

        if let image {
            renderer.setInputImage(image)
        }
        let hasImage = renderer.hasInputImage
        var u = FilmUniforms.make(params: params, crop: crop, useTexture: hasImage, time: 0)

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                            width: width, height: height,
                                                            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = device.makeTexture(descriptor: desc) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else { return nil }

        renderer.encode(encoder: encoder, uniforms: u,
                        texture: hasImage ? renderer.inputTexture : renderer.dummyTexture)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return imageFromTexture(target)
    }

    /// bgra8Unorm 纹理 -> UIImage
    static func imageFromTexture(_ texture: MTLTexture) -> UIImage? {
        let w = texture.width
        let h = texture.height
        let rowBytes = w * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(&bytes, bytesPerRow: rowBytes,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        let cg: CGImage? = bytes.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let base = ptr.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: rowBytes, space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
        guard let cg else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// 自带 renderer 的 MTKView，界面层只碰这个类
final class FilmMetalView: MTKView {

    private var renderer: FilmRenderer?

    private(set) var statusText: String = "Metal 初始化中"

    convenience init() {
        self.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
    }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false
        isPaused = false
        clearColor = MTLClearColorMake(0.957, 0.937, 0.906, 1)

        guard let device, let r = FilmRenderer(device: device) else {
            statusText = "这台设备拿不到 Metal 设备"
            return
        }
        renderer = r
        delegate = r
        statusText = r.pipelineReady
            ? "着色器编译成功：\(device.name)"
            : "着色器编译失败（看 Xcode 控制台的 Metal 报错）"
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) 不用于这个视图")
    }

    var filmRenderer: FilmRenderer? { renderer }

    func apply(inputMode: Int, filmStrength: Double, grain: Double, halo: Double,
               colorDensity: Double, blackRaise: Double = 0.03) {
        renderer?.uniforms.inputMode = Int32(inputMode)
        renderer?.uniforms.filmStrength = Float(filmStrength)
        renderer?.uniforms.grainAmount = Float(grain)
        renderer?.uniforms.haloPower = Float(halo)
        renderer?.uniforms.colorDensity = Float(colorDensity)
        renderer?.uniforms.blackRaise = Float(blackRaise)
    }

    func setInputImage(_ image: UIImage?) {
        renderer?.setInputImage(image)
    }
}

extension UIImage {
    /// 相册照片常带 EXIF 方向，直接塞进 Metal 会躺倒 90°，先统一画正
    func flNormalizedUp() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 规整成 8bit sRGB 的表示：P3、16bit、带 alpha 的照片都能进同一条纹理路径
    func flSRGB8Bit() -> UIImage {
        guard let cg = cgImage else { return self }
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0 else { return self }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue)
        else { return self }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return self }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }
}
