//
//  FilmTest.metal
//  FilmLab 测试包着色器（第一款验证用）
//
//  目的：验证设备 + Metal 链路 + 胶片模拟核心算法能否跑起来
//  这个文件里有两件东西：
//   1) 对数（Log）编解码 —— 以 18% 中灰、100% 白两个锚点拟合，可逆
//   2) 胶片冲印管线 —— S 曲线 / 色彩密度 / 橙片基 / Halation / 密度联动颗粒 / 相纸响应
//
//  重要：Log 曲线的锚点常数目前是按公开资料的中灰、白点码值做的「观感近似」，
//        正式版必须替换成各厂商公开规范里的精确系数（见 docs/TODO 清单），不要直接上架。
//

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float time;          // 视频时序，照片固定 0
    float filmStrength;  // 胶片总强度 0~1
    float grainAmount;   // 颗粒总量
    float haloPower;     // Halation 强度
    float colorDensity;  // 色彩密度
    float blackRaise;    // 黑位抬升
    int   inputMode;     // 0=Rec.709 直通 1=S-Log3 2=D-Log 3=N-Log
    float pad0;
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

// ---------------------------------------------------------------- 顶点

vertex VSOut fullscreen_vertex(uint vid [[vertex_id]]) {
    // 一个覆盖全屏的大三角形，比四边形少一个顶点
    float2 corners[3] = {
        float2(-1.0f, -1.0f),
        float2( 3.0f, -1.0f),
        float2(-1.0f,  3.0f)
    };
    VSOut out;
    out.position = float4(corners[vid], 0.0f, 1.0f);
    // uv 的 y 翻转，让 uv=(0,0) 落在左上角
    out.uv = corners[vid] * float2(0.5f, -0.5f) + float2(0.5f, 0.5f);
    return out;
}

// ---------------------------------------------------------------- Rec.709 传递函数

float rec709_to_linear(float c) {
    return (c >= 0.081f) ? pow((c + 0.099f) / 1.099f, 2.4f) : (c / 4.5f);
}

float linear_to_rec709(float l) {
    return (l >= 0.018f) ? (1.099f * pow(l, 1.0f / 2.4f) - 0.099f) : (l * 4.5f);
}

// ---------------------------------------------------------------- Log 编解码
// 以「18% 中灰码值 c18」「100% 白码值 c100」为锚点的对数映射。
// encode 与 decode 互为反函数，所以可以拿来做链路自检：编码再解码后画面应完全复原。

float log_slope(float c18, float c100) {
    return (c100 - c18) / log10(1.0f / 0.18f);
}

// 注意：这里故意不把码值钳到 [0,1]。
// 一旦在暗部钳位，低于黑点的线性值会被压成同一个码值，decode 回来就丢信息，
// 编码→解码不再可逆（实测偏差会到 8e-2，画面上一眼能看出黑条被抬成灰）。
// 物理上的暗部截止（toe）应该在正式版按厂商规范实现，并同步改掉自检标准。
float log_encode_linear(float lin, float c18, float c100) {
    float k = log_slope(c18, c100);
    return c18 + k * log10(max(lin, 1e-4f));
}

float log_decode_code(float code, float c18, float c100) {
    float k = log_slope(c18, c100);
    return pow(10.0f, (code - c18) / k);
}

// 注意：Metal 不允许 void f(float &x) 这种「引用出参」（MSL 要求引用必须带地址空间限定，
// 写 thread float& 才行，而且容易在宿主与着色器之间产生歧义）。这里改成返回结构体，
// 是 MSL 里最稳妥的写法。
struct LogAnchors {
    float c18;
    float c100;
};

LogAnchors log_anchors(int mode) {
    // TODO(正式版)：替换为厂商公开规范数值，当前为锚点近似
    LogAnchors a;
    if (mode == 1) {          // Sony S-Log3（18% 灰≈0.410，白≈0.616）
        a.c18 = 0.410f; a.c100 = 0.616f;
    } else if (mode == 2) {   // DJI D-Log
        a.c18 = 0.330f; a.c100 = 0.650f;
    } else if (mode == 3) {   // Nikon N-Log
        a.c18 = 0.369f; a.c100 = 0.620f;
    } else {                  // Rec.709 直通（不使用）
        a.c18 = 0.180f; a.c100 = 1.000f;
    }
    return a;
}

// ---------------------------------------------------------------- 测试图
// 8 条标准色条 + 底部横向灰度渐变。灰度渐变是用来肉眼检查曲线有没有压死的。

float3 test_pattern(float2 uv) {
    float3 color;
    float idx = floor(uv.x * 8.0f);
    if      (idx < 1.0f) color = float3(1.0f, 1.0f, 1.0f);
    else if (idx < 2.0f) color = float3(1.0f, 1.0f, 0.0f);
    else if (idx < 3.0f) color = float3(0.0f, 1.0f, 1.0f);
    else if (idx < 4.0f) color = float3(0.0f, 1.0f, 0.0f);
    else if (idx < 5.0f) color = float3(1.0f, 0.0f, 1.0f);
    else if (idx < 6.0f) color = float3(1.0f, 0.0f, 0.0f);
    else if (idx < 7.0f) color = float3(0.0f, 0.0f, 1.0f);
    else                 color = float3(0.0f, 0.0f, 0.0f);

    // 底部 20% 区域替换为水平灰度渐变 0→100%
    if (uv.y > 0.80f) {
        float g = clamp((uv.x - 0.02f) / 0.96f, 0.0f, 1.0f);
        color = float3(g, g, g);
    }
    return color;
}

// ---------------------------------------------------------------- 颗粒

float3 film_grain(float2 uv, float lum, float t) {
    float2 p = uv * 1400.0f + float2(t * 0.31f, t * 0.19f);
    float r = fract(sin(dot(p, float2(7.13f, 19.41f))) * 37421.23f);
    float g = fract(sin(dot(p + 0.22f, float2(6.84f, 17.22f))) * 29154.72f);
    float b = fract(sin(dot(p + 0.44f, float2(8.31f, 21.66f))) * 24812.91f);
    // 暗部颗粒更明显，高光颗粒更细，但不清零（负片特性）
    float weight = mix(0.40f, 1.0f, smoothstep(0.0f, 0.70f, 1.0f - lum));
    return (float3(r, g, b) - 0.5f) * weight;
}

// ---------------------------------------------------------------- 胶片 S 曲线
// 端点归一化：x=0 映射到 0、x=1 映射到 1，只在中调提高反差。
// 不这么归一的话，tanh 曲线会把纯黑抬成中灰，看起来像"算法写错了"。

float film_s_curve(float x, float strength) {
    float k = 1.0f + strength * 1.6f;
    float amp = 0.5f;
    float lo = 0.5f - tanh(0.5f * k) * amp;
    float hi = 0.5f + tanh(0.5f * k) * amp;
    float s = (0.5f + tanh((x - 0.5f) * k) * amp - lo) / max(hi - lo, 1e-4f);
    return clamp(mix(x, s, strength), 0.0f, 1.0f);
}

// ---------------------------------------------------------------- 主片段

fragment float4 film_fragment(VSOut in [[stage_in]],
                              constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float3 display = test_pattern(uv);

    // 显示参考值 → 场景线性光
    float3 scene = float3(rec709_to_linear(display.r),
                          rec709_to_linear(display.g),
                          rec709_to_linear(display.b));

    // 输入色彩空间：Log 模式下先编码成 log 码值再解码回来，
    // 若四种模式画面完全一致，说明 Log 链路数学上自洽（这就是本测试包的核心自检项）
    float3 lin;
    if (u.inputMode == 0) {
        lin = scene;
    } else {
        LogAnchors anchors = log_anchors(u.inputMode);
        float c18 = anchors.c18;
        float c100 = anchors.c100;
        float3 code = float3(log_encode_linear(scene.r, c18, c100),
                             log_encode_linear(scene.g, c18, c100),
                             log_encode_linear(scene.b, c18, c100));
        lin = float3(log_decode_code(code.r, c18, c100),
                     log_decode_code(code.g, c18, c100),
                     log_decode_code(code.b, c18, c100));
    }

    lin = clamp(lin, 0.0f, 1.0f);

    // 黑位抬升
    lin += u.blackRaise * u.filmStrength;

    float3 lumaW = float3(0.2126f, 0.7152f, 0.0722f);

    // 胶片 S 曲线：逐通道过曲线，端点归一到 0/1，黑位不会被曲线自己抬起来
    lin = float3(film_s_curve(lin.r, u.filmStrength),
                 film_s_curve(lin.g, u.filmStrength),
                 film_s_curve(lin.b, u.filmStrength));

    // 色彩密度：高饱和不收死，中调更饱满
    float y = dot(lin, lumaW);
    lin = y + (lin - y) * mix(0.45f, 1.0f, u.colorDensity);

    // 橙色片基（弱一些，太强就成滤镜了）
    lin += float3(0.18f, 0.07f, 0.02f) * (1.0f - y) * 0.10f * u.filmStrength;

    // Halation 红橙光晕
    float halo = smoothstep(0.72f, 0.97f, y);
    lin += float3(1.0f, 0.72f, 0.55f) * halo * u.haloPower;

    // 密度联动颗粒
    lin += film_grain(uv, y, u.time) * u.grainAmount;

    lin = clamp(lin, 0.0f, 1.0f);

    // 相纸响应：反差略降、黑位不死黑、白位不是纯白
    // 用 filmStrength 做闸门，强度归零时这一级必须完全直通
    float3 paper = lin;
    paper = smoothstep(0.0f, 0.30f, paper) * 0.50f + paper * 0.50f;
    paper = paper * 0.94f + 0.03f;
    lin = mix(lin, paper, u.filmStrength);

    float3 outColor = float3(linear_to_rec709(lin.r),
                             linear_to_rec709(lin.g),
                             linear_to_rec709(lin.b));
    return float4(clamp(outColor, 0.0f, 1.0f), 1.0f);
}
