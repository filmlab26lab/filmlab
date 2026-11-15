# FilmLab（胶片实验室）

一个 iOS / iPadOS 的胶片模拟 App 工程。桌面新建，2026-11-16 起。
算法方向沿用你手机端对话里定下来的那套：**负片—染料—相纸**链路 + Dehancer 风格的四要素
（Halation 红橙光晕、密度联动颗粒、色彩密度、分段胶片曲线），加上 S-Log3 / D-Log / N-Log 的 Log 还原。

---

## 这一轮做了什么

| 东西 | 位置 | 状态 |
|---|---|---|
| 项目骨架 | `App/` | 已完成 |
| 测试包 App（设备信息 + Metal 实时画面 + 四个滑块） | `App/FilmLab/` | 已完成 |
| 胶片冲印着色器（含 Log 编解码 + 链路自检） | `App/FilmLab/Shaders/FilmTest.metal` | 已完成 |
| IPA 体检工具 | `Tools/ipa_check.py` + `Tools/检查IPA.bat` | 已完成，已自测通过 |
| 云端编译出 IPA 的流水线 | `.github/workflows/build-test-ipa.yml` | 已完成，待你推到 GitHub |
| 签名 / 装机 / 验收清单 | `docs/02_签名与安装步骤.md` | 已完成 |

**还没做、也不会假装做完的：** 一个能直接装手机的 `.ipa` 文件。
原因很硬：iOS 二进制必须有 macOS + Xcode 才能编译，这台 Windows 上没有（`swift`、`xcodebuild` 都不存在）。
具体怎么办见 `01_第一步_先拿到可安装的IPA.md` —— 三条路，第一条免费。

---

## 目录结构

```
FilmLab/
├─ 01_第一步_先拿到可安装的IPA.md    ← 先看这个
├─ docs/
│  └─ 02_签名与安装步骤.md            ← 签名、装机、装完怎么验收
├─ App/
│  ├─ project.yml                    ← XcodeGen 工程描述（在 Mac 上生成 .xcodeproj）
│  └─ FilmLab/
│     ├─ FilmLabApp.swift
│     ├─ TestView.swift              ← 测试包界面
│     ├─ FilmRenderer.swift          ← Metal 渲染 + uniform
│     └─ Shaders/FilmTest.metal      ← 着色器（核心算法都在这）
├─ Tools/
│  ├─ ipa_check.py                   ← IPA 体检（结构/加密/描述文件/UDID/最低系统）
│  ├─ 检查IPA.ps1 / 检查IPA.bat       ← 拖拽即用
│  └─ make_fixture.py                ← 生成自测样例包，验证体检工具本身没写错
└─ .github/workflows/build-test-ipa.yml
```

---

## 测试包为什么这么设计

一个能验证链路的测试包，不是"能跑就行"，得能**证伪**。所以它内置了两个自检：

1. **Log 链路可逆性自检**
   着色器把测试图按 Rec.709 反解成场景线性光，再按选中的 Log 曲线编码成码值、再解码回来。
   如果 Rec.709 / S-Log3 / D-Log / N-Log 四档画面**完全一致**，说明每条曲线的 encode/decode 数学上自洽。
   肉眼看不出问题，比任何日志都直接。

2. **直通对照**
   把「胶片强度 / 颗粒 / Halation」都拉到 0、色彩密度拉到 1，画面必须和输入完全一致。
   如果这时候还有偏色或整体压暗，说明管线里混进了不受滑块控制的常数项。

---

## 已知待办（写进代码注释里了，不用记）

- [ ] **Log 曲线换真数值**。当前 `log_anchors()` 里的中灰/白点是用公开资料做的锚点近似，
      正式版要替换成 Sony / DJI / Nikon 公开规范里的精确系数，否则暗部和高光的分离度会不准。
- [ ] 色域矩阵（S-Gamut3.Cine / Rec.2020 / Rec.709 之间的转换）还没加，现在只做了 Gamma 曲线。
- [ ] 相机页（AVCaptureSession + 逐帧进 Metal）和照片/视频导入导出。
- [ ] 视频导出（AVAssetWriter，4K，保持 Rec.709 输出）。
- [ ] App 上架合规：应用名和预设名不要出现 Dehancer / Portra / Vision3 等商标，
      预设叫「电影负片」「人像暖调」这种功能性名字。

---

## 快速命令

```powershell
# 体检任意一个 IPA（拖到 bat 上也行）
powershell -NoProfile -ExecutionPolicy Bypass -File "Tools\检查IPA.ps1" -Ipa "C:\path\app.ipa"

# 体检时同时核对设备 UDID 和系统版本
powershell -NoProfile -ExecutionPolicy Bypass -File "Tools\检查IPA.ps1" `
  -Ipa "C:\path\app.ipa" -Udid 00008120-001A70160EF8A01E -IosVersion 26.7.3

# 自检：造一个样例包，验证体检工具本身
python Tools\make_fixture.py
python Tools\ipa_check.py Tools\_fixture\DemoFixture.ipa
```
