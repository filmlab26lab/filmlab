//
//  FilmRenderer.swift
//  把 FilmTest.metal 接到 MTKView 上；同时提供「不进界面也能出图」的离屏渲染，
//  导出按钮就是靠离屏渲染把当前参数算成一张图再写进相册的。
//
//  两种输入：
//    · 有照片 -> 采样照片纹理走同一套胶片管线
//    · 没照片 -> 走着色器里的测试色卡（就是首页预览的空态）
//

import UIKit
import MetalKit
import QuartzCore

/// 与着色器里 struct Uniforms 一一对应（字段顺序、类型都不能改）
struct FilmUniforms {
    var time: Float = 0
    var filmStrength: Float = 0.60
    var grainAmount: Float = 0.05
    var haloPower: Float = 0.16
    var colorDensity: Float = 0.85
    var blackRaise: Float = 0.03
    var inputMode: Int32 = 0
    var useTexture: Int32 = 0
}

final class FilmRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var inputTexture: MTLTexture?
    private var dummyTexture: MTLTexture?
    private let startTime = CACurrentMediaTime()

    /// 着色器是否编译成功，界面用它显示状态
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

    /// 没有照片时也要绑一张纹理，否则采样器读不到东西会出黑屏
    private func buildDummyTexture() {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                        width: 1, height: 1, mipmapped: false)
        d.usage = [.shaderRead]
        dummyTexture = device.makeTexture(descriptor: d)
    }

    /// 换成片源；传 nil 就回到测试色卡
    func setInputImage(_ image: UIImage?) {
        guard let image, let cg = image.flNormalizedUp().cgImage else {
            inputTexture = nil
            uniforms.useTexture = 0
            return
        }
        let loader = MTKTextureLoader(device: device)
        do {
            // SRGB 关掉：照片数据已经是我们想要的显示参考值，再让它做一次 sRGB 转换就会偏亮
            inputTexture = try loader.newTexture(cgImage: cg, options: [.SRGB: false])
            uniforms.useTexture = (inputTexture != nil) ? 1 : 0
        } catch {
            inputTexture = nil
            uniforms.useTexture = 0
        }
    }

    var hasInputImage: Bool { inputTexture != nil }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipelineState,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        // 预览时让颗粒随时间流动，能看出「颗粒是活的」；导出时把 time 固定成 0
        uniforms.time = Float(CACurrentMediaTime() - startTime)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FilmUniforms>.stride, index: 0)
        encoder.setFragmentTexture(inputTexture ?? dummyTexture, index: 0)
        if let samplerState {
            encoder.setFragmentSamplerState(samplerState, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: 离屏渲染（导出用）

    /// 不依赖屏幕，直接把一张照片按当前参数渲染成 UIImage。返回 nil 说明这台设备的 Metal 拒绝出图。
    static func renderStill(image: UIImage?, uniforms: FilmUniforms, width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0,
              let device = MTLCreateSystemDefaultDevice(),
              let renderer = FilmRenderer(device: device),
              renderer.pipelineReady
        else { return nil }

        renderer.setInputImage(image)

        var u = uniforms
        u.time = 0
        u.useTexture = renderer.hasInputImage ? 1 : 0

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
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass),
              let pipelineState = renderer.pipelineState
        else { return nil }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&u, length: MemoryLayout<FilmUniforms>.stride, index: 0)
        encoder.setFragmentTexture(renderer.inputTexture ?? renderer.dummyTexture, index: 0)
        if let samplerState = renderer.samplerState {
            encoder.setFragmentSamplerState(samplerState, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        target.getBytes(&bytes, bytesPerRow: rowBytes,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Metal 的 bgra8Unorm 在内存里就是 BGRA，对应 little endian + 跳过首字节 alpha
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        let cgImage: CGImage? = bytes.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let base = ptr.baseAddress,
                  let ctx = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
        guard let cgImage else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// 自带 renderer 的 MTKView，界面层只碰这个类
final class FilmMetalView: MTKView {

    private var renderer: FilmRenderer?

    /// 给界面读的状态文案
    private(set) var statusText: String = "Metal 初始化中"

    /// 界面层用这个无参构造；MTKView 的指定构造是 init(frame:device:)，所以这里走 convenience
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
        // 空态底色用相纸色，避免未出图时闪一块黑
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

    func apply(inputMode: Int, filmStrength: Double, grain: Double, halo: Double,
               colorDensity: Double, blackRaise: Double = 0.03) {
        renderer?.uniforms.inputMode = Int32(inputMode)
        renderer?.uniforms.filmStrength = Float(filmStrength)
        renderer?.uniforms.grainAmount = Float(grain)
        renderer?.uniforms.haloPower = Float(halo)
        renderer?.uniforms.colorDensity = Float(colorDensity)
        renderer?.uniforms.blackRaise = Float(blackRaise)
    }

    /// 换片源；nil 回到测试色卡
    func setInputImage(_ image: UIImage?) {
        renderer?.setInputImage(image)
    }
}

extension UIImage {
    /// 相册里的照片常带 EXIF 方向，直接塞进 Metal 会躺倒 90°/180°，这里先统一画正
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
}
