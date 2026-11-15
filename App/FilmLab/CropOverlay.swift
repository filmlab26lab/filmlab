//
//  CropOverlay.swift
//  自由裁剪：可拖动移框、右下角手柄缩放、配合比例锁定。
//  坐标一律用「归一化到源图」的 CGRect（0~1），这样预览、视频帧、导出三条路径共用同一套数。
//

import SwiftUI
import CoreGraphics

enum CropMath {
    static var fullRect: CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }

    /// 某个比例能放下的最大框（居中，未裁剪的整幅图内）
    static func maxRect(ratio: CGFloat?, imageAspect: CGFloat) -> CGRect {
        guard let ratio, ratio > 0, imageAspect > 0 else { return fullRect }
        var w = 1.0
        var h = imageAspect / ratio   // 归一化坐标下的高：像素比 = (w*imgW)/(h*imgH)
        if h > 1.0 {
            h = 1.0
            w = ratio / imageAspect
        }
        w = min(w, 1.0)
        h = min(h, 1.0)
        return CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    /// 按比例修正并钳进图像范围
    static func fit(_ rect: CGRect, ratio: CGFloat?, imageAspect: CGFloat) -> CGRect {
        var r = rect
        if let ratio, ratio > 0, imageAspect > 0 {
            var w = max(0.08, r.size.width)
            var h = w * imageAspect / ratio
            if h > 1 - r.minY {
                h = max(0.08, 1 - r.minY)
                w = h * ratio / imageAspect
            }
            if w > 1 - r.minX {
                w = max(0.08, 1 - r.minX)
                h = w * imageAspect / ratio
            }
            r.size = CGSize(width: w, height: h)
        }
        r.size.width = max(0.08, min(r.size.width, 1.0))
        r.size.height = max(0.08, min(r.size.height, 1.0))
        r.origin.x = min(max(0, r.origin.x), 1 - r.size.width)
        r.origin.y = min(max(0, r.origin.y), 1 - r.size.height)
        return r
    }

    /// 围绕中心把框缩放到「最大框的 fraction」
    static func scaled(_ rect: CGRect, fraction: Double, ratio: CGFloat?, imageAspect: CGFloat) -> CGRect {
        let maxR = maxRect(ratio: ratio, imageAspect: imageAspect)
        let f = max(0.08, min(1.0, fraction))
        let w = maxR.width * f
        let h = maxR.height * f
        let cx = rect.midX
        let cy = rect.midY
        var x = cx - w / 2
        var y = cy - h / 2
        x = min(max(0, x), 1 - w)
        y = min(max(0, y), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// 叠在预览图上的裁剪框
struct CropOverlay: View {

    @Binding var crop: CGRect
    var ratio: CGFloat?
    var imageAspect: CGFloat
    /// 预览图本身是「没裁剪的整幅」，所以框的坐标直接按容器尺寸换算
    var showsGrid: Bool = true

    @State private var moveStart: CGRect?
    @State private var resizeStart: CGRect?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let rect = CGRect(x: crop.minX * size.width,
                              y: crop.minY * size.height,
                              width: crop.width * size.width,
                              height: crop.height * size.height)

            ZStack(alignment: .topLeading) {
                shade(size: size, hole: rect)

                Rectangle()
                    .stroke(Color.white.opacity(0.92), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)

                if showsGrid {
                    grid(rect: rect)
                }

                // 移动手势层
                Color.clear
                    .frame(width: max(1, rect.width), height: max(1, rect.height))
                    .offset(x: rect.minX, y: rect.minY)
                    .contentShape(Rectangle())
                    .gesture(moveGesture(size: size))

                // 右下角缩放手柄
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(FL.ink.opacity(0.35), lineWidth: 1))
                    .offset(x: rect.maxX - 7, y: rect.maxY - 7)
                    .contentShape(Circle().inset(by: -14))
                    .gesture(resizeGesture(size: size))
            }
        }
    }

    // MARK: 遮罩

    private func shade(size: CGSize, hole: CGRect) -> some View {
        let color = Color.black.opacity(0.62)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(color)
                .frame(width: size.width, height: max(0, hole.minY))
                .offset(x: 0, y: 0)
            Rectangle().fill(color)
                .frame(width: size.width, height: max(0, size.height - hole.maxY))
                .offset(x: 0, y: max(0, hole.maxY))
            Rectangle().fill(color)
                .frame(width: max(0, hole.minX), height: hole.height)
                .offset(x: 0, y: hole.minY)
            Rectangle().fill(color)
                .frame(width: max(0, size.width - hole.maxX), height: hole.height)
                .offset(x: max(0, hole.maxX), y: hole.minY)
        }
        .allowsHitTesting(false)
    }

    private func grid(rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1..<3, id: \.self) { i in
                let x = rect.minX + rect.width * CGFloat(i) / 3
                Rectangle().fill(Color.white.opacity(0.28))
                    .frame(width: 0.5, height: rect.height)
                    .offset(x: x, y: rect.minY)
            }
            ForEach(1..<3, id: \.self) { i in
                let y = rect.minY + rect.height * CGFloat(i) / 3
                Rectangle().fill(Color.white.opacity(0.28))
                    .frame(width: rect.width, height: 0.5)
                    .offset(x: rect.minX, y: y)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 手势

    private func moveGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = moveStart ?? crop
                if moveStart == nil { moveStart = start }
                var next = start
                let dx = value.translation.width / max(1, size.width)
                let dy = value.translation.height / max(1, size.height)
                next.origin.x = min(max(0, start.minX + dx), 1 - start.width)
                next.origin.y = min(max(0, start.minY + dy), 1 - start.height)
                crop = next
            }
            .onEnded { _ in moveStart = nil }
    }

    private func resizeGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = resizeStart ?? crop
                if resizeStart == nil { resizeStart = start }
                let dx = value.translation.width / max(1, size.width)
                var w = start.width + dx
                w = max(0.08, w)

                if let ratio, ratio > 0, imageAspect > 0 {
                    // 锁比例：宽度决定高度，再按图像边界收回来
                    var h = w * imageAspect / ratio
                    if h > 1 - start.minY {
                        h = max(0.08, 1 - start.minY)
                        w = h * ratio / imageAspect
                    }
                    if w > 1 - start.minX {
                        w = max(0.08, 1 - start.minX)
                        h = w * imageAspect / ratio
                    }
                    crop = CGRect(x: start.minX, y: start.minY, width: w, height: h)
                } else {
                    let dy = value.translation.height / max(1, size.height)
                    var h = start.height + dy
                    h = max(0.08, h)
                    if w > 1 - start.minX { w = 1 - start.minX }
                    if h > 1 - start.minY { h = 1 - start.minY }
                    crop = CGRect(x: start.minX, y: start.minY, width: w, height: h)
                }
            }
            .onEnded { _ in resizeStart = nil }
    }
}

/// 底部一排比例按钮
struct CropAspectBar: View {
    @Binding var aspect: CropAspect
    @Binding var crop: CGRect
    var imageAspect: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CropAspect.all) { item in
                    let active = (item == aspect)
                    Button {
                        aspect = item
                        if let r = item.ratio {
                            // 换算比例时把框改成该比例的最大居中框，避免出现「框比画面还扁」的怪状态
                            crop = CropMath.maxRect(ratio: r, imageAspect: imageAspect)
                        }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(active ? FL.ink : FL.card))
                            .foregroundStyle(active ? FL.paper : FL.ink)
                            .overlay(Capsule().stroke(FL.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }
}
