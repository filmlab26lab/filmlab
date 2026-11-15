//
//  TestView.swift
//  测试包界面：设备信息 + Metal 实时画面 + 三个滑块
//  上线后这一页会被相机页替换，现在它的唯一任务是证明「能跑、算得对」
//

import SwiftUI
import UIKit
import Metal

struct TestView: View {

    @State private var inputMode: Int = 0
    @State private var filmStrength: Double = 0.60
    @State private var grain: Double = 0.05
    @State private var halo: Double = 0.16
    @State private var colorDensity: Double = 0.85
    @State private var metalStatus: String = "Metal 初始化中"

    private let modeTitles = ["Rec.709", "S-Log3", "D-Log", "N-Log"]

    var body: some View {
        VStack(spacing: 12) {
            header

            FilmPreview(inputMode: $inputMode,
                        filmStrength: $filmStrength,
                        grain: $grain,
                        halo: $halo,
                        colorDensity: $colorDensity,
                        statusText: $metalStatus)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1))

            Text(metalStatus)
                .font(.caption)
                .foregroundStyle(metalStatus.contains("成功") ? Color.green : Color.orange)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("输入色彩空间", selection: $inputMode) {
                ForEach(0..<modeTitles.count, id: \.self) { i in
                    Text(modeTitles[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)

            Text("四种模式下画面应完全一致 —— 这就是 Log 链路自检；不一致说明曲线不可逆")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            slider(title: "胶片强度", value: $filmStrength, range: 0...1)
            slider(title: "颗粒", value: $grain, range: 0...0.20)
            slider(title: "Halation", value: $halo, range: 0...0.40)
            slider(title: "色彩密度", value: $colorDensity, range: 0...1)

            Spacer(minLength: 0)

            infoFooter
        }
        .padding(16)
        .background(Color(.systemBackground))
    }

    // MARK: 子视图

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FilmLab 测试包")
                .font(.title2.bold())
            Text("验证设备 / Metal / 胶片冲印管线")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("机型", UIDevice.current.model)
            row("系统", "iOS \(UIDevice.current.systemVersion)")
            row("Metal 设备", MTLCreateSystemDefaultDevice()?.name ?? "无")
            row("构建", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key).frame(width: 76, alignment: .leading)
            Text(value).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private func slider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

/// 把 FilmMetalView 包进 SwiftUI
struct FilmPreview: UIViewRepresentable {

    @Binding var inputMode: Int
    @Binding var filmStrength: Double
    @Binding var grain: Double
    @Binding var halo: Double
    @Binding var colorDensity: Double
    @Binding var statusText: String

    final class Coordinator {
        var view: FilmMetalView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FilmMetalView {
        let view = FilmMetalView()
        context.coordinator.view = view
        statusText = view.statusText
        return view
    }

    func updateUIView(_ uiView: FilmMetalView, context: Context) {
        uiView.apply(inputMode: inputMode,
                     filmStrength: filmStrength,
                     grain: grain,
                     halo: halo,
                     colorDensity: colorDensity)
        if statusText != uiView.statusText {
            statusText = uiView.statusText
        }
    }
}
