//
//  FilmSettings.swift
//  胶片参数的单一数据源：底片型号（stock）、预设、Log 输入模式、裁剪比例。
//  照片页与视频页共用同一套定义 —— 两边参数必须完全一致，否则同一个型号在两个页面观感会不一样。
//

import SwiftUI
import CoreGraphics

/// 一整套胶片参数。字段与着色器里的 Uniforms 一一对应（顺序见 FilmRenderer.swift）
struct FilmParams: Equatable {
    var strength: Double = 0.60      // 胶片总强度
    var grain: Double = 0.05         // 颗粒量
    var halo: Double = 0.16          // Halation 强度
    var colorDensity: Double = 0.85  // 色彩密度
    var blackRaise: Double = 0.03    // 黑位抬升
    var inputMode: Int = 0           // 0=Rec.709 1=S-Log3 2=D-Log 3=N-Log
    var colorTemp: Double = 0.0      // -1 冷 / +1 暖
    var tintShift: Double = 0.0      // -1 偏绿 / +1 偏品红
    var chroma: Double = 1.0         // 1 彩色 / 0 黑白
    var exposure: Double = 0.0       // 曝光补偿，单位 EV，-1~+1
    var contrast: Double = 0.0       // -1 更平 / +1 更硬，0 为不改
    var glow: Double = 0.10          // 光晕：亮部向外扩散的柔光（与 Halation 的红橙溢光是两件事）
    var vignette: Double = 0.18      // 暗角
    // 相纸（打印阶段）：型号本身不带相纸，由「相纸」选择器叠上来
    var paperWarmth: Double = 0.0    // -1 偏冷 / +1 偏暖
    var paperContrast: Double = 0.0  // 相纸反差 0~1（相纸的肩部比胶片长，反差要靠它给）
    var paperWhite: Double = 0.10    // 高光压缩：相纸的白不是纯 1.0
    var paperBlack: Double = 0.02    // 相纸黑位抬升：相纸的黑永远带一点密度
}

/// 底片类别：负片 / 反转片 / 黑白。反转片没有「印到相纸」这一步，黑白则单独一套味道。
enum FilmKind: String, CaseIterable, Identifiable {
    case negative = "负片"
    case slide = "反转片"
    case mono = "黑白"
    var id: String { rawValue }
}

/// 底片型号（stock）。
/// 注意：这些型号给的是「风格参考」，参数是按各型号的公开印象拟合的近似值，
/// 与厂商无任何关联，也不是精确的色彩科学复刻 —— 上架文案里必须写清楚这一点。
/// 片库口径对齐 SpektraLab / spektrafilm 的实测目录（负片 + 反转片 + 黑白），
/// 但**参数是自己拟合的近似曲线**，没有直接搬它的实测光谱数据（那套数据是 CC BY-SA 4.0）。
struct FilmStock: Identifiable, Equatable {
    let id: String
    let brand: String
    let name: String
    let note: String
    let params: FilmParams
    var kind: FilmKind = .negative

    var displayName: String { "\(brand) \(name)" }
}

extension FilmStock {
    static let none = FilmStock(
        id: "none", brand: "中性", name: "原片",
        note: "强度归零，整条管线完全直通，用来做前后对比的基准",
        params: FilmParams(strength: 0.0, grain: 0.0, halo: 0.0, colorDensity: 0.85,
                           blackRaise: 0.0, inputMode: 0, colorTemp: 0.0, tintShift: 0.0, chroma: 1.0)
    )

    static let all: [FilmStock] = [
        none,
        FilmStock(
            id: "portra400", brand: "柯达", name: "Portra 400",
            note: "人像常青款：宽容、暖调、高光带一点奶油感",
            params: FilmParams(strength: 0.62, grain: 0.05, halo: 0.18, colorDensity: 0.82,
                               blackRaise: 0.03, inputMode: 0, colorTemp: 0.18, tintShift: 0.10, chroma: 1.0)
        ),
        FilmStock(
            id: "portra800", brand: "柯达", name: "Portra 800",
            note: "比 400 更暖、颗粒更明显，夜景与弱光常用",
            params: FilmParams(strength: 0.70, grain: 0.10, halo: 0.24, colorDensity: 0.86,
                               blackRaise: 0.04, inputMode: 0, colorTemp: 0.22, tintShift: 0.08, chroma: 1.0)
        ),
        FilmStock(
            id: "gold200", brand: "柯达", name: "Gold 200",
            note: "日常快照的暖黄色调，蓝天会压成偏青的金黄感",
            params: FilmParams(strength: 0.68, grain: 0.07, halo: 0.22, colorDensity: 0.88,
                               blackRaise: 0.04, inputMode: 0, colorTemp: 0.28, tintShift: 0.14, chroma: 1.0)
        ),
        FilmStock(
            id: "ektar100", brand: "柯达", name: "Ektar 100",
            note: "颗粒细、反差与饱和度都高，风景利器，人像偏硬",
            params: FilmParams(strength: 0.78, grain: 0.03, halo: 0.14, colorDensity: 1.00,
                               blackRaise: 0.02, inputMode: 0, colorTemp: 0.06, tintShift: 0.18, chroma: 1.0)
        ),
        FilmStock(
            id: "pro400h", brand: "富士", name: "Pro 400H",
            note: "清冷的青绿调，肤色干净，偏「日系」的那种克制",
            params: FilmParams(strength: 0.58, grain: 0.05, halo: 0.16, colorDensity: 0.90,
                               blackRaise: 0.03, inputMode: 0, colorTemp: -0.10, tintShift: -0.20, chroma: 1.0)
        ),
        FilmStock(
            id: "superia400", brand: "富士", name: "Superia 400",
            note: "青绿更重、饱和更高，街拍与扫街的常见观感",
            params: FilmParams(strength: 0.72, grain: 0.08, halo: 0.18, colorDensity: 0.95,
                               blackRaise: 0.03, inputMode: 0, colorTemp: -0.14, tintShift: -0.24, chroma: 1.0)
        ),
        FilmStock(
            id: "c200", brand: "富士", name: "C200",
            note: "最清淡的一支：反差低、偏绿、适合日常随手拍",
            params: FilmParams(strength: 0.60, grain: 0.06, halo: 0.14, colorDensity: 0.78,
                               blackRaise: 0.04, inputMode: 0, colorTemp: -0.06, tintShift: -0.16, chroma: 1.0)
        ),
        FilmStock(
            id: "hp5", brand: "依尔福", name: "HP5 Plus 400",
            note: "黑白：颗粒大、暗部有层次，去色后反差仍保留",
            params: FilmParams(strength: 0.74, grain: 0.12, halo: 0.10, colorDensity: 0.70,
                               blackRaise: 0.03, inputMode: 0, colorTemp: 0.0, tintShift: 0.0, chroma: 0.0),
            kind: .mono
        ),
        FilmStock(
            id: "trix", brand: "柯达", name: "Tri-X 400",
            note: "黑白：反差更高、颗粒更粗，纪实感强",
            params: FilmParams(strength: 0.78, grain: 0.13, halo: 0.08, colorDensity: 0.72,
                               blackRaise: 0.02, inputMode: 0, colorTemp: 0.0, tintShift: 0.0, chroma: 0.0),
            kind: .mono
        ),

        // ---- 柯达负片补充（片库口径对齐 SpektraLab 的实测目录）----
        FilmStock(
            id: "portra160", brand: "柯达", name: "Portra 160",
            note: "Portra 里最细最干净的一支，肤色柔和，白天人像首选",
            params: FilmParams(strength: 0.58, grain: 0.03, halo: 0.14, colorDensity: 0.80,
                               blackRaise: 0.03, inputMode: 0, colorTemp: 0.14, tintShift: 0.08, chroma: 1.0)
        ),
        FilmStock(
            id: "portra800push1", brand: "柯达", name: "Portra 800 Push 1",
            note: "按 1600 推冲的 800：颗粒变粗、反差和黄色一起上来，夜里更有味道",
            params: FilmParams(strength: 0.80, grain: 0.14, halo: 0.28, colorDensity: 0.92,
                               blackRaise: 0.06, inputMode: 0, colorTemp: 0.24, tintShift: 0.14, chroma: 1.0)
        ),
        FilmStock(
            id: "ultramax400", brand: "柯达", name: "Ultramax 400",
            note: "超市就能买到的那支：暖、颗粒适中、蓝紫容易偏",
            params: FilmParams(strength: 0.70, grain: 0.09, halo: 0.22, colorDensity: 0.90,
                               blackRaise: 0.04, inputMode: 0, colorTemp: 0.24, tintShift: 0.12, chroma: 1.0)
        ),
        FilmStock(
            id: "cinestill800t", brand: "CineStill", name: "800T",
            note: "去掉炭黑层的电影卷：钨丝灯平衡，夜景高光会拖着红橙光晕",
            params: FilmParams(strength: 0.74, grain: 0.10, halo: 0.34, colorDensity: 0.94,
                               blackRaise: 0.05, inputMode: 0, colorTemp: -0.22, tintShift: -0.06, chroma: 1.0)
        ),

        // ---- 富士负片 ----
        FilmStock(
            id: "xtra400", brand: "富士", name: "X-TRA 400",
            note: "富士的日常 400：绿很稳、肤色偏青、暗部带一点紫",
            params: FilmParams(strength: 0.70, grain: 0.08, halo: 0.18, colorDensity: 0.92,
                               blackRaise: 0.04, inputMode: 0, colorTemp: -0.12, tintShift: -0.22, chroma: 1.0)
        ),

        // ---- 反转片：没有负片那种橙片基，反差和饱和度天然更高 ----
        FilmStock(
            id: "ektachrome100", brand: "柯达", name: "Ektachrome E100",
            note: "反转片：干净、蓝调准，高光收得紧，扫出来偏冷",
            params: FilmParams(strength: 0.72, grain: 0.03, halo: 0.10, colorDensity: 1.00,
                               blackRaise: 0.01, inputMode: 0, colorTemp: -0.10, tintShift: 0.06, chroma: 1.0),
            kind: .slide
        ),
        FilmStock(
            id: "provia100f", brand: "富士", name: "Provia 100F",
            note: "反转片：最中性的那一支，宽容好，颜色克制",
            params: FilmParams(strength: 0.66, grain: 0.03, halo: 0.12, colorDensity: 0.98,
                               blackRaise: 0.01, inputMode: 0, colorTemp: -0.04, tintShift: -0.04, chroma: 1.0),
            kind: .slide
        ),
        FilmStock(
            id: "velvia100", brand: "富士", name: "Velvia 100",
            note: "反转片：饱和度拉满，红和绿都浓，风景专用，人像慎用",
            params: FilmParams(strength: 0.84, grain: 0.03, halo: 0.12, colorDensity: 1.00,
                               blackRaise: 0.00, inputMode: 0, colorTemp: -0.06, tintShift: -0.16, chroma: 1.0),
            kind: .slide
        ),

        // ---- 黑白补充 ----
        FilmStock(
            id: "fp4", brand: "依尔福", name: "FP4 Plus 125",
            note: "黑白：细颗粒、中反差，扫街与静物都稳",
            params: FilmParams(strength: 0.66, grain: 0.06, halo: 0.08, colorDensity: 0.70,
                               blackRaise: 0.03, inputMode: 0, colorTemp: 0.0, tintShift: 0.0, chroma: 0.0),
            kind: .mono
        ),
    ]
}

/// 相纸（打印阶段）。
/// SpektraLab 那套模型是「胶片曝光 → 显影 → 印到相纸 → 相纸显影」两段式，
/// 相纸不是滤镜，它决定成片的反差肩部、白点、黑位和整体色偏。
/// 这里同样做成第二段：型号定底片味道，相纸定「打进纸里」的样子。
struct FilmPaper: Identifiable, Equatable {
    let id: String
    let brand: String
    let name: String
    let note: String
    let warmth: Double     // -1 偏冷 / +1 偏暖
    let contrast: Double   // 相纸反差 0~1
    let white: Double      // 高光压缩，白位不到 1.0
    let black: Double      // 黑位抬升，相纸的黑带一点密度

    var displayName: String { "\(brand) \(name)" }

    /// 把相纸叠在胶片参数上：只动打印这四项，不覆盖底片自己的色味
    func applied(to base: FilmParams) -> FilmParams {
        var p = base
        p.paperWarmth = warmth
        p.paperContrast = contrast
        p.paperWhite = white
        p.paperBlack = black
        return p
    }
}

extension FilmPaper {
    static let none = FilmPaper(id: "none", brand: "无", name: "不印相纸",
                                note: "只走胶片这一段，不打印，反差和颜色都留在负片上",
                                warmth: 0, contrast: 0, white: 0, black: 0)

    static let all: [FilmPaper] = [
        none,
        FilmPaper(id: "crystalArchiveTypeII", brand: "富士", name: "Crystal Archive Type II",
                  note: "最常见的富士彩扩纸：青绿高光、反差中性，配 Portra 最稳",
                  warmth: -0.10, contrast: 0.30, white: 0.09, black: 0.025),
        FilmPaper(id: "portraEndura", brand: "柯达", name: "Portra Endura",
                  note: "柯达人像纸：暖、柔、肤色最好看",
                  warmth: 0.10, contrast: 0.24, white: 0.10, black: 0.030),
        FilmPaper(id: "enduraPremier", brand: "柯达", name: "Endura Premier",
                  note: "比 Portra Endura 硬一点、饱和高一点，日常冲印的主力纸",
                  warmth: 0.06, contrast: 0.34, white: 0.08, black: 0.020),
        FilmPaper(id: "supraEndura", brand: "柯达", name: "Supra Endura",
                  note: "商业彩扩纸：反差和饱和都更足，红色扎实",
                  warmth: 0.04, contrast: 0.42, white: 0.07, black: 0.020),
        FilmPaper(id: "ultraEndura", brand: "柯达", name: "Ultra Endura",
                  note: "柯达最浓的一张纸：反差高、黑位深，适合风景与商品",
                  warmth: 0.02, contrast: 0.52, white: 0.06, black: 0.015),
        FilmPaper(id: "ektacolorEdge", brand: "柯达", name: "Ektacolor Edge",
                  note: "老柯达味：偏青、灰阶偏冷，九十年代相册的观感",
                  warmth: -0.06, contrast: 0.38, white: 0.09, black: 0.025),
        FilmPaper(id: "vision2383", brand: "柯达", name: "Vision 2383",
                  note: "电影正片：白点压得死、高光偏暖，银幕上的黑是真空的黑",
                  warmth: 0.12, contrast: 0.60, white: 0.05, black: 0.010),
        FilmPaper(id: "vision2393", brand: "柯达", name: "Vision 2393",
                  note: "电影正片的另一支：更冷、更青，夜景与霓虹常用",
                  warmth: -0.10, contrast: 0.56, white: 0.06, black: 0.010),
        FilmPaper(id: "multigradeIV", brand: "依尔福", name: "Multigrade IV RC",
                  note: "黑白相纸：反差最硬、层次靠纸给，只对黑白片有意义的搭配",
                  warmth: 0.0, contrast: 0.70, white: 0.04, black: 0.000),
    ]
}

/// 裁剪比例。ratio 是「像素宽高比」；nil 表示自由裁剪（不锁比例）
struct CropAspect: Identifiable, Equatable {
    let id: String
    let title: String
    let ratio: CGFloat?

    static let all: [CropAspect] = [
        CropAspect(id: "free", title: "自由", ratio: nil),
        CropAspect(id: "16:9", title: "16:9", ratio: 16.0 / 9.0),
        CropAspect(id: "9:16", title: "9:16", ratio: 9.0 / 16.0),
        CropAspect(id: "4:3", title: "4:3", ratio: 4.0 / 3.0),
        CropAspect(id: "3:4", title: "3:4", ratio: 3.0 / 4.0),
        CropAspect(id: "1:1", title: "1:1", ratio: 1.0),
        CropAspect(id: "2.35:1", title: "2.35:1", ratio: 2.35),
    ]
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
    static let defaultStock = "fl.defaultStock"
    static let defaultPreset = "fl.defaultPreset"
    static let defaultPaper = "fl.defaultPaper"
}

/// 预设：给刚上手的人一个不用调就能看的起点（与型号正交，型号定「味道」，预设定「力度」）
enum FilmPreset: String, CaseIterable, Identifiable {
    case neutral = "标准"
    case warm = "暖调"
    case dense = "高密度"
    case clean = "清淡"

    var id: String { rawValue }

    var note: String {
        switch self {
        case .neutral: return "型号原味，不做额外缩放"
        case .warm:    return "强度与 Halation 略加，整体更暖"
        case .dense:   return "反差、颗粒、密度一起加，接近重曝光"
        case .clean:   return "整体减淡，人像与日常更清爽"
        }
    }

    /// 作用在当前参数上的力度系数：预设不覆盖型号，只把四个主参数按比例缩放
    var scale: (strength: Double, grain: Double, halo: Double, density: Double) {
        switch self {
        case .neutral: return (1.00, 1.00, 1.00, 1.00)
        case .warm:    return (1.15, 1.10, 1.40, 1.05)
        case .dense:   return (1.35, 1.50, 1.15, 1.15)
        case .clean:   return (0.65, 0.60, 0.65, 0.85)
        }
    }

    func applied(to base: FilmParams) -> FilmParams {
        var p = base
        let s = scale
        p.strength = min(1.0, base.strength * s.strength)
        p.grain = min(0.20, base.grain * s.grain)
        p.halo = min(0.40, base.halo * s.halo)
        p.colorDensity = min(1.0, base.colorDensity * s.density)
        return p
    }
}

extension Bundle {
    var flVersionText: String {
        let short = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(short) · build \(build)"
    }
}
