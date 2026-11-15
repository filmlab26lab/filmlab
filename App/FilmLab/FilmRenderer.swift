//
//  FilmRenderer.swift
//  把 FilmTest.metal 接到 MTKView 上，每帧刷新一次 uniform
//

import UIKit
import MetalKit
import QuartzCore

/// 与着色器里 struct Uniforms 完全一一对应（字段顺序不能改）
struct FilmUniforms {
    var time: Float = 0
    var filmStrength: Float = 0.60
    var grainAmount: Float = 0.05
    var haloPower: Float = 0.16
    var colorDensity: Float = 0.85
    var blackRaise: Float = 0.03
    var inputMode: Int32 = 0
    var pad0: Float = 0
}

final class FilmRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private let startTime = CACurrentMediaTime()

    /// 状态：着色器是否编译成功，用来在界面上显示
    private(set) var pipelineReady = false

    var uniforms = FilmUniforms()

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()
        buildPipeline()
    }

    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "fullscreen_vertex"),
              let fragmentFn = library.makeFunction(name: "film_fragment") else {
            return
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "FilmLabTestPipeline"
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        pipelineReady = (pipelineState != nil)
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipelineState,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        // 照片模式 external 传 0 即可；此处按时间推进，方便看颗粒流动
        uniforms.time = Float(CACurrentMediaTime() - startTime)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms,
                                 length: MemoryLayout<FilmUniforms>.stride,
                                 index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
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
        clearColor = MTLClearColorMake(0, 0, 0, 1)

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
        fatalError("init(coder:) 不用于这个测试视图")
    }

    func apply(inputMode: Int, filmStrength: Double, grain: Double, halo: Double, colorDensity: Double) {
        renderer?.uniforms.inputMode = Int32(inputMode)
        renderer?.uniforms.filmStrength = Float(filmStrength)
        renderer?.uniforms.grainAmount = Float(grain)
        renderer?.uniforms.haloPower = Float(halo)
        renderer?.uniforms.colorDensity = Float(colorDensity)
    }
}
