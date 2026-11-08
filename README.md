# EasyBarcode

macOS 26 / 27 上的原生条码生成小工具。常驻菜单栏，按 `⌥B` 显示/隐藏主窗口，按 `⌥H`（应用内）打开/关闭历史窗口；输入数字后按 `⏎` 生成条码并复制，生成记录会进入历史（带条码图片、备注，可单条删除）。

## 功能

- **快捷键**：主窗口默认 `⌥B`（全局生效）；历史记录默认 `⌥H`（仅 EasyBarcode 激活时生效，应用内快捷键）。两个都可以在「设置」中分别修改，配置持久化。
- **模式感知输入**：输入限制跟随格式切换——
  - 自动 / Code 128 / QR：允许任意文本（上限 256 字符，自动过滤换行）
  - EAN-13 / UPC-A：仅数字（上限 64 位，粘贴的文本会自动过滤出数字）
  - Code 128 不支持中文等非 ASCII 字符，会提示改用 QR；QR 完整支持 UTF-8（含中文）
- **按需生成**：输入时只显示解析结果（格式、位数、校验位），按 `⏎` 才生成图片并复制，不会每敲一个数字就重绘。
- **点击复制**：按 `⏎` 或直接点击主窗口的条码预览图即可复制（PNG + TIFF + 数字文本），并显示玻璃「已复制」反馈；主窗口不再有单独的复制按钮。
- **自动格式**：纯数字按零售规则解析；文本内容自动落到 Code 128（纯 ASCII）或 QR（含中文）。
  - 13 位 → EAN-13（校验位错误会自动修正并提示）
  - 12 位 → EAN-13（自动补校验位；完整 UPC-A 请手动选择）
  - 11 位 → UPC-A（自动补校验位）
  - 其他位数 → Code 128
  - 手动可切换 EAN-13 / UPC-A / Code 128 / QR，手动选择优先。
- **历史记录**：每次按 `⏎` 生成后写入历史，最多保留 50 条并跨启动保存。按 `⌥H`、点击底部时钟按钮或菜单栏「历史记录」打开独立的历史窗口：条码图片是卡片主体，数字、格式、时间作为次要信息。点击图片自动复制条码；每条支持多行备注，也可以单独删除；底部支持一键清空。
- **历史图片落盘**：每条历史记录会保存一张 PNG 到历史图片目录（默认 `~/Library/Application Support/EasyBarcode/History`），可在设置中更换目录，也可以一键在 Finder 中打开。
- **历史导出**：历史窗口底栏「导出」支持两种格式——
  - **xlsx**：五列（# / 内容 / 格式 / 生成时间 / 备注 / 图片），每行把条码 PNG 直接**内嵌到单元格**里（基于 [XLKit](https://github.com/TheAcharya/XLKit)，MIT）
  - **Word（.docx）**：与 Markdown 同版式——「条目」下每条一个项目符号段（内容 / 内嵌图片 / 备注 / 格式 / 生成时间），文末「导出信息」；图片以内联方式嵌进文档，单文件即可分发
  - **Markdown**：正文「条目」下每条记录一个无序列表项（内容 / 限宽图片 / 备注 / 格式 / 生成时间），文末「导出信息」记录导出时间与条数；图片存入同名文件夹（`EasyBarcode历史-日期图片/`）以相对路径引用，Typora / VS Code / 飞书文档导入即可显示条码缩略图
- **设置**：菜单栏「设置」里可分别修改全局（主窗口）与应用内（历史记录）快捷键，打开 / 选择 / 恢复历史图片目录，以及登录时启动。
- **普通窗口**：标准标题栏、红黄绿按钮，可移动、缩放、最小化、关闭；失去焦点不会消失，再次按快捷键显隐。最小尺寸 300 × 335（此时预览图约 230 × 120）。
- **Liquid Glass**：`NSGlassEffectView` 原生玻璃背景，自动适配浅色/深色外观；静态玻璃，点击无回弹。

## 系统要求

- 运行：macOS 26 或 macOS 27。
- 构建：Xcode 26+（当前使用 Xcode 27.2 / Swift 6.4）。

## 构建与安装

```bash
make test     # 单元测试 + Vision 回环解码
make app      # 构建 build/EasyBarcode.app（含图标与 ad-hoc 签名）
make install  # 安装到 /Applications
make run      # 构建并启动（带 --show）
```

如果 `/Applications` 没有写权限，`make install` 会提示使用：

```bash
sudo ditto build/EasyBarcode.app /Applications/EasyBarcode.app
```

## 使用

1. 启动 EasyBarcode（菜单栏出现 barcode 图标，无 Dock 图标）。
2. 在任意 App 中按 `⌥B`，主窗口出现；再按一次隐藏。EasyBarcode 激活时按 `⌥H` 打开/关闭历史窗口（应用内快捷键）。
3. 输入数字，按 `⏎`：生成条码、复制图片到剪贴板，并写入历史；之后点击预览图也可以再次复制。
4. 按 `⌥H`（或点击底部时钟按钮 / 菜单栏「历史记录」）打开历史窗口：点击条码图片即复制；点击备注文字可编辑（支持多行）；右上角垃圾桶可单独删除；底栏「导出」弹出两个选项：「导出为 Excel（.xlsx）…」（内嵌图片）或「导出为 Markdown（.md）…」（表格 + 图片文件夹）。
5. 菜单栏「设置」：分别修改主窗口/历史记录快捷键、打开或更换历史图片目录、登录启动。
6. `⌘W` 关闭窗口（应用继续驻留菜单栏）。

## 命令行

App 二进制内置渲染命令，便于脚本或批量生成：

```bash
./build/EasyBarcode.app/Contents/MacOS/EasyBarcode \
  --render 6901234567892 --format ean13 --width 1600 --out /tmp/ean13.png
```

- `--format auto|ean13|upca|code128|qr`
- `--width` 目标像素宽，默认 1600
- 调试参数：`--show`、`--demo <digits>`、`--preferences`、`--print-window-id`、`--copy`（启动后触发一次复制，验证反馈）

## 实现说明

- SwiftPM + AppKit，零第三方依赖，部署目标 `macOS 26.0`。
- 窗口为普通 `NSWindow`（`.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView`），内容使用 `NSGlassEffectView`。
- 玻璃为**静态**：没有开启 macOS 27 的 `effectIsInteractive`，因此点击窗口不会有回弹/果冻效果。
- 主窗口使用 Carbon `RegisterEventHotKey` 注册全局热键（默认 `⌥B`）；历史记录使用应用内 keyDown 本地监听（默认 `⌥H`），只有 EasyBarcode 激活时才响应，不会抢占其他 App 的按键。两个快捷键均可在设置中修改。唤起窗口使用 `NSRunningApplication.current.activate(options: [.activateAllWindows])`。
- EAN-13 / UPC-A 使用自研 95 模块编码器 + CoreGraphics 整数模块矢量绘制；Code 128 / QR 使用 CoreImage 生成后整数倍最近邻放大，保证条宽均匀。
- 历史记录保存在 UserDefaults（最多 50 条）；对应的条码图片以 UUID.png 的形式保存在历史图片目录中，设置里可以打开、更换目录，已有图片会复制到新目录。
- 测试通过 Vision `VNDetectBarcodesRequest` 对生成图片做回环解码，EAN-13 / UPC-A / Code 128 / QR 全部通过。
- 图标由 `Scripts/make-icon.swift` 用 CoreGraphics 生成，`iconutil` 打包为 `.icns`。

## 第三方依赖

- [XLKit](https://github.com/TheAcharya/XLKit)（MIT）— xlsx 生成与图片内嵌
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)（MIT）— docx 打包（原为 XLKit 传递依赖，现为直接依赖）

## 目录

```
Sources/BarcodeKit/     格式解析、校验位、编码器、图片渲染（可单测）
Sources/EasyBarcode/    AppKit 窗口、玻璃 UI、全局热键、菜单栏、设置、历史
Tests/BarcodeKitTests/  编码单测 + Vision 回环测试
Scripts/                构建 .app、生成图标
Resources/Info.plist    LSUIElement / 最低系统版本 / bundle id
```

## License

MIT © 2026 chenkeyu
