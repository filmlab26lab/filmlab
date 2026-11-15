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
    int   useTexture;    // 0=用测试色卡 1=采样输入纹理
    // 裁剪窗口（归一化到源图，原点左上）：画面只取这块区域
    float cropX;
    float cropY;
    float cropW;
    float cropH;
    float colorTemp;     // 色温：-1 冷 / +1 暖（模拟不同底片的白平衡倾向）
    float tintShift;     // 色偏：-1 偏绿（富士系）/ +1 偏品红（柯达系）
    float chroma;        // 1=彩色 0=黑白（黑白底片型号用这个去色）
    int   rotateQuarter; // 0/1/2/3 个 90°：视频的旋转变换（相册里竖拍的片子靠这个摆正）
    float exposure;      // 曝光补偿（EV）：-1~+1
    float contrast;      // 反差：-1 更平 / +1 更硬
    float glow;          // 光晕：亮部向外扩散的柔光（四向八抽样近似）
    float vignette;      // 暗角
    // 相纸（打印阶段）：两段式冲印里第二段的四个量
    float paperWarmth;   // 相纸色偏：-1 偏冷 / +1 偏暖
    float paperContrast; // 相纸反差 0~1（相纸肩部比胶片长）
    float paperWhite;    // 高光压缩：相纸的白不到纯 1.0
    float paperBlack;    // 相纸黑位抬升：相纸的黑永远带一点密度
};

// 把「显示方向」的 uv 转回「源画面」的 uv。
// 用整数映射而不是三角函数：四个象限的对应关系是精确的，不存在浮点误差导致的半像素抖动。
float2 rotate_uv(float2 uv, int quarter) {
    if (quarter == 1) return float2(uv.y, 1.0f - uv.x);
    if (quarter == 2) return float2(1.0f - uv.x, 1.0f - uv.y);
    if (quarter == 3) return float2(1.0f - uv.y, uv.x);
    return uv;
}

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

// 同一个片段函数服务两种输入：
//   useTexture=1 时采样照片纹理（照片项目页、导出都走这里）
//   useTexture=0 时画内置测试色卡（没选照片的空态）
// 采样器必须一直绑着，所以宿主会塞一张 1x1 占位纹理，别让采样读到空对象。
fragment float4 film_fragment(VSOut in [[stage_in]],
                              constant Uniforms &u [[buffer(0)]],
                              texture2d<float> src [[texture(0)]],
                              sampler samp [[sampler(0)]]) {
    float2 uv = in.uv;
    // 裁剪在「显示方向」上取窗口，再旋转回源画面 —— 用户看到的框就是最终构图
    float2 duv = float2(u.cropX + uv.x * u.cropW, u.cropY + uv.y * u.cropH);
    float2 suv = rotate_uv(duv, u.rotateQuarter);
    float3 display = (u.useTexture != 0)
        ? src.sample(samp, clamp(suv, 0.0f, 1.0f)).rgb
        : test_pattern(uv);

    // 光晕（glow）：在画面周围 8 个方向取样，只把「亮部」加回来，近似出柔光扩散。
    // 用 8 抽样而不是高斯卷积，是因为手机上一帧要跑满 60fps，多 8 次采样已经很贵了。
    float3 glowAccum = float3(0.0f);
    if (u.glow > 0.001f) {
        float radius = 0.006f + u.glow * 0.022f;
        for (int gi = 0; gi < 8; gi++) {
            float ang = float(gi) * 0.7853982f;          // 每 45°
            float2 off = float2(cos(ang), sin(ang)) * radius;
            float2 gduv = clamp(float2(u.cropX + (uv.x + off.x) * u.cropW,
                                       u.cropY + (uv.y + off.y) * u.cropH), 0.0f, 1.0f);
            float3 s = (u.useTexture != 0)
                ? src.sample(samp, clamp(rotate_uv(gduv, u.rotateQuarter), 0.0f, 1.0f)).rgb
                : display;
            float l = dot(s, float3(0.2126f, 0.7152f, 0.0722f));
            glowAccum += s * smoothstep(0.52f, 0.95f, l);
        }
        glowAccum *= 0.125f;
    }

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

    // 曝光补偿：线性光域里翻 EV，暗部不会像曲线抬升那样发灰
    lin = clamp(lin * exp2(u.exposure), 0.0f, 1.0f);

    // 黑位抬升
    lin += u.blackRaise * u.filmStrength;

    float3 lumaW = float3(0.2126f, 0.7152f, 0.0722f);

    // 胶片 S 曲线：逐通道过曲线，端点归一到 0/1，黑位不会被曲线自己抬起来
    lin = float3(film_s_curve(lin.r, u.filmStrength),
                 film_s_curve(lin.g, u.filmStrength),
                 film_s_curve(lin.b, u.filmStrength));

    // 底片型号的色偏：色温（冷/暖）与色偏（绿/品红）。
    // 数值刻意做得很小 —— 型号差异应该是「一眼能分辨、但不像滤镜」，不是换了个 App。
    float tempW = u.colorTemp * 0.075f;
    lin.r *= (1.0f + tempW);
    lin.b *= (1.0f - tempW);
    float tintW = u.tintShift * 0.05f;
    lin.g *= (1.0f + tintW);
    lin.r *= (1.0f - tintW * 0.5f);
    lin.b *= (1.0f - tintW * 0.5f);
    lin = max(lin, 0.0f);

    // 黑白底片：去色但保留通道比例，便于后面黑白颗粒仍然成立
    float y0 = dot(lin, float3(0.2126f, 0.7152f, 0.0722f));
    lin = mix(float3(y0, y0, y0), lin, clamp(u.chroma, 0.0f, 1.0f));

    // 色彩密度：高饱和不收死，中调更饱满
    float y = dot(lin, lumaW);
    lin = y + (lin - y) * mix(0.45f, 1.0f, u.colorDensity);

    // 橙色片基（弱一些，太强就成滤镜了）
    lin += float3(0.18f, 0.07f, 0.02f) * (1.0f - y) * 0.10f * u.filmStrength;

    // Halation 红橙光晕
    float halo = smoothstep(0.72f, 0.97f, y);
    lin += float3(1.0f, 0.72f, 0.55f) * halo * u.haloPower;

    // 光晕：亮部扩散的柔光，颜色偏暖，权重很小 —— 它的作用是「让亮处发光」，不是给整张加雾
    lin += glowAccum * float3(1.0f, 0.88f, 0.74f) * (u.glow * 0.85f);

    // 密度联动颗粒；颗粒坐标用裁剪后的 uv，换裁剪框时颗粒不会跟着画面漂
    lin += film_grain(suv, y, u.time) * u.grainAmount;

    lin = clamp(lin, 0.0f, 1.0f);

    // 相纸响应（第二段）：负片印到相纸上，纸的反差肩部、白点、黑位、色偏都在这里。
    // 顺序是「先过相纸曲线 → 再压白位 → 再抬黑位 → 最后纸的色偏」，也就是纸实际成像的顺序。
    // 全部用 filmStrength 做闸门：强度归零时这一段必须完全直通。
    float3 pap = lin;
    if (u.paperContrast > 0.001f) {
        float pc = clamp(u.paperContrast, 0.0f, 1.0f);
        pap = float3(film_s_curve(pap.r, pc * 1.2f),
                     film_s_curve(pap.g, pc * 1.2f),
                     film_s_curve(pap.b, pc * 1.2f));
    }
    // 高光压缩：分母里带自己，亮部越亮压得越多，白位停在 1/(1+w) 附近而不是纯白
    pap = pap / (1.0f + pap * max(u.paperWhite, 0.0f));
    // 黑位抬升：相纸有纸基，再好的纸也印不出纯 0
    pap = pap * (1.0f - clamp(u.paperBlack, 0.0f, 0.2f)) + clamp(u.paperBlack, 0.0f, 0.2f);
    // 纸的色偏
    float pw = u.paperWarmth * 0.06f;
    pap.r *= (1.0f + pw);
    pap.b *= (1.0f - pw);
    pap = max(pap, 0.0f);

    // 旧的通用相纸柔化：让暗部过渡不硬，只在有纸时生效
    float3 soft = smoothstep(0.0f, 0.30f, pap) * 0.50f + pap * 0.50f;
    pap = mix(soft, pap, clamp(u.paperContrast * 1.6f, 0.0f, 1.0f));

    lin = mix(lin, pap, u.filmStrength);

    float3 outColor = float3(linear_to_rec709(lin.r),
                             linear_to_rec709(lin.g),
                             linear_to_rec709(lin.b));
    outColor = clamp(outColor, 0.0f, 1.0f);

    // 反差：在显示域里绕 0.5 拉开，比在线性域里拉开更符合「看起来的对比度」
    float k = 1.0f + u.contrast * 0.55f;
    outColor = clamp((outColor - 0.5f) * k + 0.5f, 0.0f, 1.0f);

    // 暗角：到画面中心的距离平方做衰减，四角最暗，中心完全不动
    float2 vp = uv - 0.5f;
    float d2 = clamp(dot(vp, vp) * 2.0f, 0.0f, 1.0f);
    outColor *= (1.0f - u.vignette * d2);

    return float4(clamp(outColor, 0.0f, 1.0f), 1.0f);
}
