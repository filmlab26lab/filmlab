#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
preview_shader.py —— 在电脑上把 FilmTest.metal 的数学原样跑一遍，出图。
为什么要有这个：
    手机装机流程要绕一圈（云端编译 → 下载 → 签名 → 安装），
    但算法对不对，在 Windows 上就能先验证完。这个脚本和着色器一一对应，
    改了着色器就同步改这里，出图对了再上手机，能省掉「装了发现画面不对」的来回。

它会输出一张 2x2 对照图：
    左上 直通（所有胶片参数归零，画面应等于输入）
    右上 默认胶片（强度 0.6 / 颗粒 0.05 / 光晕 0.16 / 密度 0.85）
    左下 重胶片（强度 0.9 / 颗粒 0.15 / 光晕 0.35）
    右下 Log 自检：Rec.709 与 S-Log3 两条链路的像素差 ×500 后显示
        纯黑 = 两条链路数学上完全一致（误差小于 1/255 看不出来）

用法： python preview_shader.py
"""

import math
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "预览")
OUT_FILE = os.path.join(OUT_DIR, "测试画面_胶片.png")

QUAD_W = 480
QUAD_H = 270


# ---------------------------------------------------------------- 基础函数

def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else (hi if x > hi else x)


def mix(a, b, t):
    return a + (b - a) * t


def smoothstep(edge0, edge1, x):
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def fract(x):
    return x - math.floor(x)


def rec709_to_linear(c):
    return math.pow((c + 0.099) / 1.099, 2.4) if c >= 0.081 else c / 4.5


def linear_to_rec709(l):
    return 1.099 * math.pow(l, 1.0 / 2.4) - 0.099 if l >= 0.018 else l * 4.5


# ---------------------------------------------------------------- Log 编解码（与着色器同一套锚点）

LOG_ANCHORS = {
    1: (0.410, 0.616),   # S-Log3
    2: (0.330, 0.650),   # D-Log
    3: (0.369, 0.620),   # N-Log
}


def log_slope(c18, c100):
    return (c100 - c18) / math.log10(1.0 / 0.18)


def log_encode_linear(lin, c18, c100):
    # 与着色器一致：不钳位，否则暗部不可逆
    k = log_slope(c18, c100)
    return c18 + k * math.log10(max(lin, 1e-4))


def log_decode_code(code, c18, c100):
    k = log_slope(c18, c100)
    return math.pow(10.0, (code - c18) / k)


# ---------------------------------------------------------------- 测试图

def test_pattern(u, v):
    idx = math.floor(u * 8.0)
    bars = [(1, 1, 1), (1, 1, 0), (0, 1, 1), (0, 1, 0),
            (1, 0, 1), (1, 0, 0), (0, 0, 1), (0, 0, 0)]
    color = bars[min(int(idx), 7)]
    if v > 0.80:
        g = clamp((u - 0.02) / 0.96)
        color = (g, g, g)
    return color


# ---------------------------------------------------------------- 胶片管线

def film_s_curve(x, strength):
    k = 1.0 + strength * 1.6
    amp = 0.5
    lo = 0.5 - math.tanh(0.5 * k) * amp
    hi = 0.5 + math.tanh(0.5 * k) * amp
    s = (0.5 + math.tanh((x - 0.5) * k) * amp - lo) / max(hi - lo, 1e-4)
    return clamp(mix(x, s, strength))


def film_grain(u, v, lum, t):
    px = u * 1400.0 + t * 0.31
    py = v * 1400.0 + t * 0.19
    r = fract(math.sin(px * 7.13 + py * 19.41) * 37421.23)
    g = fract(math.sin((px + 0.22) * 6.84 + (py + 0.22) * 17.22) * 29154.72)
    b = fract(math.sin((px + 0.44) * 8.31 + (py + 0.44) * 21.66) * 24812.91)
    weight = mix(0.40, 1.0, smoothstep(0.0, 0.70, 1.0 - lum))
    return ((r - 0.5) * weight, (g - 0.5) * weight, (b - 0.5) * weight)


def render_pixel(u, v, p):
    """p: dict，参数含义与着色器 uniform 一致"""
    display = test_pattern(u, v)
    scene = tuple(rec709_to_linear(c) for c in display)

    mode = p.get("inputMode", 0)
    if mode == 0:
        lin = list(scene)
    else:
        c18, c100 = LOG_ANCHORS[mode]
        lin = [log_decode_code(log_encode_linear(c, c18, c100), c18, c100) for c in scene]

    lin = [clamp(c) for c in lin]
    fs = p.get("filmStrength", 0.0)

    # 黑位抬升
    lin = [c + p.get("blackRaise", 0.0) * fs for c in lin]

    # S 曲线（逐通道）
    lin = [film_s_curve(c, fs) for c in lin]

    luma_w = (0.2126, 0.7152, 0.0722)
    y = sum(c * w for c, w in zip(lin, luma_w))

    # 色彩密度
    sat = mix(0.45, 1.0, p.get("colorDensity", 1.0))
    lin = [y + (c - y) * sat for c in lin]

    # 橙色片基
    base = (0.18, 0.07, 0.02)
    lin = [c + b * (1.0 - y) * 0.10 * fs for c, b in zip(lin, base)]

    # Halation
    halo = smoothstep(0.72, 0.97, y) * p.get("haloPower", 0.0)
    lin = [c + h * halo for c, h in zip(lin, (1.0, 0.72, 0.55))]

    # 颗粒
    gr = film_grain(u, v, y, p.get("time", 0.0))
    ga = p.get("grainAmount", 0.0)
    lin = [c + g * ga for c, g in zip(lin, gr)]

    lin = [clamp(c) for c in lin]

    # 相纸响应（用 filmStrength 做闸门）
    paper = [smoothstep(0.0, 0.30, c) * 0.50 + c * 0.50 for c in lin]
    paper = [c * 0.94 + 0.03 for c in paper]
    lin = [mix(a, b, fs) for a, b in zip(lin, paper)]

    return tuple(clamp(linear_to_rec709(c)) for c in lin)


# ---------------------------------------------------------------- 出图

def to_byte(v):
    return int(clamp(v) * 255.0 + 0.5)


def write_png(path, width, height, rgb):
    def chunk(tag, data):
        return tag + struct.pack(">I", len(data)) + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += rgb[y * width * 3:(y + 1) * width * 3]

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


PRESETS = {
    "passthrough": dict(filmStrength=0.0, grainAmount=0.0, haloPower=0.0,
                        colorDensity=1.0, blackRaise=0.0, inputMode=0),
    "default": dict(filmStrength=0.60, grainAmount=0.05, haloPower=0.16,
                    colorDensity=0.85, blackRaise=0.03, inputMode=0),
    "heavy": dict(filmStrength=0.90, grainAmount=0.15, haloPower=0.35,
                  colorDensity=0.70, blackRaise=0.05, inputMode=0),
    "logdiff": dict(filmStrength=0.60, grainAmount=0.0, haloPower=0.0,
                    colorDensity=0.85, blackRaise=0.03, inputMode=0),
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    width, height = QUAD_W * 2, QUAD_H * 2
    rgb = bytearray(width * height * 3)

    quad_keys = ["passthrough", "default", "heavy", "logdiff"]
    max_log_diff = 0.0

    for q, key in enumerate(quad_keys):
        ox = (q % 2) * QUAD_W
        oy = (q // 2) * QUAD_H
        preset = PRESETS[key]
        for j in range(QUAD_H):
            v = (j + 0.5) / QUAD_H
            for i in range(QUAD_W):
                u = (i + 0.5) / QUAD_W
                if key == "logdiff":
                    # 同一组参数下，Rec.709 与 S-Log3 两条链路的输出差
                    a = render_pixel(u, v, dict(preset, inputMode=0))
                    b = render_pixel(u, v, dict(preset, inputMode=1))
                    diff = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
                    max_log_diff = max(max_log_diff, diff)
                    val = clamp(diff * 500.0)
                    col = (val, val, val)
                else:
                    col = render_pixel(u, v, preset)
                px = ((oy + j) * width + (ox + i)) * 3
                rgb[px] = to_byte(col[0])
                rgb[px + 1] = to_byte(col[1])
                rgb[px + 2] = to_byte(col[2])

    write_png(OUT_FILE, width, height, rgb)
    print("已输出：%s" % OUT_FILE)
    print("Rec.709 与 S-Log3 两条链路的最大像素差：%.3e（小于 1e-3 即可认为可逆）" % max_log_diff)

    # 直通自检：直通图上某个色条像素应该和输入一致
    p = PRESETS["passthrough"]
    worst = 0.0
    for (u, v) in [(0.06, 0.2), (0.31, 0.2), (0.56, 0.2), (0.81, 0.2), (0.93, 0.9), (0.02, 0.95)]:
        src = test_pattern(u, v)
        out = render_pixel(u, v, p)
        worst = max(worst, max(abs(a - b) for a, b in zip(src, out)))
    print("直通模式最大偏差：%.3e（应接近 0，说明所有参数归零时管线完全直通）" % worst)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
