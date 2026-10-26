# iOS 喝水页 R2 整改交接 · 2026-10-26

本轮针对用户真机退回截图实际修改 WaterView.swift，处理底部记录操作被 Tab 遮挡和功能按钮显式玻璃样式。**R1 的静态通过没有被当成视觉通过；R2 仍只完成源码与静态核对，尚未完成 Swift 类型检查、Xcode 构建或修复后真机验收。**

## 已实际查看的截图

已通过图像工具打开并查看：

`C:/Users/win11/AppData/Local/Temp/codex-clipboard-33c86054-b115-40f6-9475-f141285f7471.png`

截图中今日饮水为 250 mL、未设置目标；饮品条及 150/250/350/500 mL 杯量条位于下方，“记录水”和右侧自定义按钮与底部 Tab 明显重叠。记录按钮上的文字还受到玻璃折射干扰。这是修复前证据，不能证明 R2 的最终效果。

## 本轮 before 快照与精确写入范围

写入前已保存当前工作树文件，**没有用旧本地 HEAD 作为本轮 diff 基线**：

- before：`C:/Users/win11/AppData/Local/Temp/opengym-water-r2-cbc0bbcf0a4040d3a1fadac3c3a0088a/WaterView.before.swift`
- 宿主只读快照：同目录 `RootView.observed.swift`。
- 起始状态：同目录 `before.json`，记录 HEAD、文件 SHA-256 和已有暂存路径。
- 本轮独立增量：同目录 `WaterView.r2.diff`。
- 本轮检查脚本及输出：同目录 `check-r2.py`、`static-checks.json`。

用户/总控提供的上一批远端交付基线是 c2ca4a1b，本地 HEAD 仍为 ac83d8bb16eec39d1cf87bdad9519557e0997c7c。本轮直接对 before 快照做增量比较：WaterView.swift **增加 90 行、删除 42 行**；没有把之前未落入本地 HEAD 的 R1 修改算成本轮新增。

本轮仅写入两个仓库路径：

1. `frontend/ios/App/App/Native/WaterView.swift`
2. `docs/dev/IOS_WATER_REFINEMENT_R2_2026-10-26.md`（新增本文）

未修改 RootView、TodayView、其他页面、数据模型/Store、Xcode 工程、Package.swift、R1 交接文档或旧静态报告。未发现适用 AGENTS.md。没有执行 add、commit、push、pull、reset、stash、clean 或切换分支。

## 本轮实现增量

### 1. 独立前景 viewport，背景不参与撑高

旧结构把忽略安全区的 WaterBackground 与 GeometryReader 并列放在 ZStack 中，前景再使用无限扩展的 maxHeight，竖向布局还包含两个 Spacer。这些使“用于选择布局的理想高度”和“最终把按钮推向哪里”依赖多层扩展；同时宿主的底栏安全区也正在独立修复。**截图不能单独证明所有遮挡都来自本页，因此本轮同时修正本页布局契约，并明确依赖总控完成宿主修复。**

新结构让前景 GeometryReader 成为 NavigationStack 内容的唯一尺寸来源，WaterBackground 改为它的 background。前景使用 GeometryReader 提供的实际宽高：

- 内容宽度：可用宽度减去既有左右各 16 点页边距，并限制正常最大阅读宽度。
- 内容高度：可用高度减去既有上下各 8 点页边距。
- 显式把布局约束到这个尺寸；没有加一个猜测的 Tab 高度，没有新增本页底部 safeAreaInset 或底部硬编码补偿。

这 32/16 点只对应既有页面边距，并非额外 Tab 避让。全屏水体继续忽略背景安全区，前景不使用 ignoresSafeArea。

### 2. 测量实际内容并锚定底部操作区

新增文件内私有 WaterDashboardLayout（SwiftUI Layout）：

- 在给定宽度下测量摘要、可选服用提醒、完整快捷操作的自然高度；requiredHeight 为真实内容高度之和加最小间距。
- ViewThatFits 用这个内容高度选择普通或紧凑版本，不再依赖两个可扩展 Spacer。
- 最终布局只把剩余高度分配到内容块之间；只要该候选布局可容纳，快捷操作块底边精确落在前景 bounds.maxY。
- 继续保留上一轮紧凑模式的饮品横向条、杯量菜单、操作分行，以及矮宽窗口的双栏布局；没有裁切、隐藏操作或恢复整页纵向滚动。

本轮不声称任意极端窗口与最大字号组合均已通过；Layout、ViewThatFits 的真实测量和最终宿主安全区必须一起做 iOS 验证。

### 3. 普通功能按钮去显式玻璃

新增文件内私有 WaterActionButtonStyle，只使用 Color 填充或透明背景，无系统 Material / shader 折射：

- 主按钮“记录”和 DoseSheet 的“确认这次已服用”：实色 accentColor 背景、白色标签。
- 设置每日目标、紧凑杯量菜单入口、自定义、撤销，以及 DoseSheet 的撤销：轻量标签样式，破坏性撤销保留红色语义。
- 点击目标至少 44×44 pt，提供按下/禁用状态；原有记录、自定义、撤销的无障碍名称和动作不变。
- 本文件原有的 7 处 glass / glassProminent 功能样式全部移除，也没有新增 glassEffect。
- 顶部导航、系统菜单、弹窗工具栏继续使用系统默认外观，没有给整个 NavigationStack 全局套自定义按钮样式。

这遵循用户本次“功能按钮不用液态玻璃”的产品要求。Apple 的 [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) 强调内容层与导航/控制层区分、节制使用玻璃；[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) 建议用样式突出主要动作；[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) 保留系统框架自身的导航外观。没有把 Apple 指南曲解为“官方禁止所有玻璃按钮”。布局接口参考 [SwiftUI Layout](https://developer.apple.com/documentation/swiftui/layout)。

## 最新宿主只读核对与整合边界

本轮开始和提交交接前均读取了当时工作树的 RootView.swift，SHA-256：

`7de20219076520c08e33edbc60c5d6715b23c287757bc40cef475d39d689464d`

当时仍是 RootView 外层 ZStack + safeAreaInset(bottom) 承载底栏的版本，包含 workoutRequest。Root 对话仍在并行整改，**本轮没有把尚未看到的宿主最终版本说成已核对或已验收**。本页不消费额外底栏高度参数、不重复扣 Tab 高度；总控应把 Root 最终提供的前景可用区域与本页一起运行验证。

## 已执行的检查

- tree-sitter 解析修改后整个 WaterView.swift（含私有 Layout、ButtonStyle 和各 sheet），无 ERROR / missing 节点。
- 当前 Xcode 工程中 WaterView.swift 已在 Sources Build Phase，无需修改工程。
- 对比 R2 before：从 DrinkKind 图标映射到 DoseSheet 之前的历史行、历史页和记录编辑页逐字不变；DoseSheet 只有上述按钮样式替换。
- 本页仍只有两个显式 horizontal ScrollView；没有默认纵向 ScrollView、原来的纵向 Spacer、前景裁切或前景安全区绕过。
- 全文件显式玻璃调用为零。
- `git -c core.autocrlf=false diff --check -- frontend/ios/App/App/Native/WaterView.swift` 退出码 0。
- 真实暂存路径仍为原有五项 API 文件：api/Dockerfile、api/server.js、api/test/server-admin-delete.test.js、api/test/workout-sync-events.test.js、api/workout-sync-events.js。本轮未改真实索引。

SHA-256：

| 文件状态 | SHA-256 |
| --- | --- |
| R2 before WaterView.swift | 8e9e0180864f81975caa249a9ae69a66c9be63397f2aea36d4777ed36468cdbd |
| R2 after WaterView.swift | d7156fb0e647678bcfdc7d22f6329ae0ac8bc2787fa28601cbae2ecc918fc1ba |

未新增模拟 SwiftUI 视觉的替代测试。**未运行 Swift 类型检查、XCTest、Xcode/Metal 构建或修复后 iOS 界面；没有生成或伪造修复后截图。**

## 总控合并后必须验收

1. 复现截图状态：250 mL、未设目标、普通字号，确认饮品、杯量、记录和自定义完整位于最终 Tab 栏上方，文字没有玻璃折射。
2. 连续记录后成功反馈与撤销出现时，再次检查底部高度；修改目标、存在/不存在服用计划、超目标时不能重新遮挡。
3. 小屏、横屏、iPad 窗口、各级动态字体：检查普通/紧凑切换和实际测量结果，没有裁切或不可达按钮；不能以 Windows 静态通过替代这些检查。
4. 页面空白处上下拖动不滚动；饮品/杯量横滑、杯量菜单、自定义、真实保存/撤销正常。
5. DoseSheet 确认与撤销按钮、历史编辑/删除、自定义日期和系统工具栏正常；主按钮为实色，次按钮不再显式玻璃。
6. 与 Root 最新底栏一起核对安全区、点击范围、系统导航层外观和全屏水体连续性。

由总控统一审查、构建验证和 Git 交付。
