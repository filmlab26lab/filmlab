//
//  FilmSettings.swift
//  胶片参数的单一数据源：预设、Log 输入模式、默认值持久化的 key。
//  照片项目页、设置页都从这里取，避免两边各写一套默认值最后对不上。
//

import SwiftUI

/// 一整套胶片参数。字段与着色器里的 Uniforms 一一对应（顺序见 FilmRenderer.swift）
struct FilmParams: Equatable {
    var strength: Double = 0.60      // 胶片总强度
    var grain: Double = 0.05         // 颗粒量
    var halo: Double = 0.16          // Halation 强度
    var colorDensity: Double = 0.85  // 色彩密度
    var blackRaise: Double = 0.03    // 黑位抬升
    var inputMode: Int = 0           // 0=Rec.709 1=S-Log3 2=D-Log 3=N-Log
}

/// 预设：给刚上手的人一个不用调就能看的起点
enum FilmPreset: String, CaseIterable, Identifiable {
    case neutral = "标准负片"
    case warm = "暖调负片"
    case dense = "高密度负片"
    case clean = "清淡负片"

    var id: String { rawValue }

    var note: String {
        switch self {
        case .neutral: return "中性反差，色彩密度适中，接近常见民用彩负"
        case .warm:    return "橙片基更明显，高光光晕更足，人像肤色偏暖"
        case .dense:   return "反差与色彩密度都推高，适合街景与有质感的静物"
        case .clean:   return "强度收着用，暗部干净，接近「几乎没调」的观感"
        }
    }

    func params() -> FilmParams {
        switch self {
        case .neutral: return FilmParams(strength: 0.60, grain: 0.05, halo: 0.16, colorDensity: 0.85, blackRaise: 0.03, inputMode: 0)
        case .warm:    return FilmParams(strength: 0.72, grain: 0.06, halo: 0.24, colorDensity: 0.90, blackRaise: 0.04, inputMode: 0)
        case .dense:   return FilmParams(strength: 0.85, grain: 0.08, halo: 0.20, colorDensity: 1.00, blackRaise: 0.02, inputMode: 0)
        case .clean:   return FilmParams(strength: 0.38, grain: 0.03, halo: 0.10, colorDensity: 0.70, blackRaise: 0.02, inputMode: 0)
        }
    }
}

/// 输入色彩空间：决定进管线前要不要先做一次 Log 还原
enum LogMode: Int, CaseIterable, Identifiable {
    case rec709 = 0
    case slog3 = 1
    case dlog = 2
    case nlog = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .rec709: return "Rec.709"
        case .slog3:  return "S-Log3"
        case .dlog:   return "D-Log"
        case .nlog:   return "N-Log"
        }
    }

    var hint: String {
        switch self {
        case .rec709: return "普通照片与视频的默认输入，直接进胶片管线"
        case .slog3:  return "索尼 S-Log3 素材，先还原再调色"
        case .dlog:   return "大疆 D-Log 素材"
        case .nlog:   return "尼康 N-Log 素材"
        }
    }
}

enum FLKey {
    static let defaultPreset = "fl.defaultPreset"
}

extension Bundle {
    var flVersionText: String {
        let short = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(short) · build \(build)"
    }
}
