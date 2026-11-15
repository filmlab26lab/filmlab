# 第一步：怎么把「测试包」变成手机上能点开的图标

## 先说清楚一件硬事实（这不是推脱，是技术边界）

iOS 的 App 安装包（IPA）里装的东西是一个 **arm64 的 Mach-O 二进制**，它必须由 **macOS + Xcode** 编译出来。
你这台 Windows 电脑上：

- 没有 Xcode（苹果不发布 Windows 版）
- 没有 iOS SDK（UIKit / SwiftUI / Metal 的 iOS 版框架不在 Windows 上）
- 没有 Swift 编译器（查过了，`swift` 不在本机）

所以 **"在 Windows 上直接点一下生成 IPA" 这条路不存在**。任何号称 Windows 本地一键出 IPA 的工具，实质都是拿别人编译好的包在改再重签，出不来你自己的代码。

**但不必买 Mac。** 下面三条路，第 1 条免费，是最合适的。

---

## 路线 1（推荐，免费）：GitHub 云端 macOS 编译

思路：把代码丢到 GitHub，它的免费 macOS 服务器帮你编译，产出**未签名 IPA**；下载回 Windows，用你已经在用的爱思助手签名装到手机上。

1. 注册 / 登录 GitHub（免费）：https://github.com
2. 新建一个仓库，名字随意，比如 `filmlab`，**设为 Public**（公开仓库的 Actions 免费额度不限）。
3. 把这个项目里的 `App`、`.github`、`Tools`、`docs` 一起上传（网页上直接拖文件也行：
   `Add file → Upload files`）。
4. 打开仓库的 **Actions** 标签页 → 左侧选「生成测试IPA」→ 右边 **Run workflow** → 点绿色按钮。
5. 等 5～15 分钟（第一次要装工具，慢一些）。
6. 编译成功后，点这次运行的记录 → 页面底部 **Artifacts** → 下载 `FilmLab-test-unsigned.zip`
   → 解压得到一个 `FilmLab-test-unsigned.ipa`。

> 这一步失败最可能的原因：`project.yml` 里的包名 / 路径和你上传的目录层级不一致。
> 把红色报错那几行发给我，我按报错改。

---

## 路线 2：借一台 Mac（10 分钟）

任何一台装了 Xcode 的 Mac（朋友的、公司的、网吧式的 Mac 租赁都行）：

```bash
cd App
brew install xcodegen      # 只装一次
xcodegen generate          # 生成 FilmLab.xcodeproj
open FilmLab.xcodeproj     # 在 Xcode 里打开
```

然后在 Xcode 里：选中你的 iPhone 作运行目标 → 直接 Run。
要 IPA 就在 `Product → Archive → Distribute App → Development` 导出，或按路线 1 的方式打未签名包。

---

## 路线 3：云 Mac 租用（花钱）

阿里云 / 腾讯云 / AWS 都有 macOS 实例，按月计费。除非你要长期天天打 iOS 包，否则不建议，成本远高于路线 1。

---

## 拿到 IPA 之后的固定流程

**签之前先体检**（这就是这次给你做的那个工具）：

把 IPA 拖到 `Tools\检查IPA.bat` 上，或者命令行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\检查IPA.ps1 `
  -Ipa "C:\Users\Administrator\Downloads\FilmLab-test-unsigned.ipa" `
  -Udid 00008120-001A70160EF8A01E -IosVersion 26.7.3
```

它会告诉你：包结构对不对、Bundle ID 是什么、最低系统版本、二进制有没有被加密、有没有描述文件、签名缺失项。

然后签名 + 安装：见 `docs/02_签名与安装步骤.md`。

---

## 关于你自己的包 vs 别人的包

这个工程产出的 IPA 是你自己的代码编译的，签名装到自己手机上完全没问题。
从别处下载的第三方 IPA（尤其是号称"解锁订阅"的包）属于另一件事：那类包本质是花钱买的应用被破解重打包，签名装上属于侵权使用，出问题也不会有任何支持，我不会帮你处理这条链路。
