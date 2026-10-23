# iOS 身体页重构 · 2026-10-23

状态：原生代码及工程接入已完成，Windows 静态检查通过；尚未经过 Xcode 编译与 iPhone 运行验收。

## 页面与组件

一条连续的原生 `List`：体重 → 训练概览 → 肌肉分布 → 强度 → 更多趋势 → 日历及记录。顶部 `safeAreaBar` 内使用系统 `ControlGroup` 导航按钮，直接滚动定位；重复点击同一区域仍可定位，不切换四个页面。

| 区域 | 默认显示 | 原位展开与操作 |
| --- | --- | --- |
| 体重 | 最新已记录体重及日期、所选期间变化、7/30/90天/全部曲线、目标 | 体脂率与估算去脂体重曲线、称重列表；点记录编辑，滑动删除 |
| 训练概览 | 本月次数、本周次数、连续训练周数 | 不伪造每周目标 |
| 肌肉分布 | 正背面人体图、前三肌群的有效组数 | 其余肌群、未覆盖肌群；7/30/90天/全部与强度共用范围 |
| 强度 | 已评分组平均 RIR、RIR≤3 占比、评分覆盖量 | 按周趋势、分布；无评分显示未记录 |
| 更多趋势 | 动作力量趋势、围度折叠入口 | 各动作最大重量/次数、最新围度、录入围度 |
| 日历与记录 | 原生月历、所选月份/累计训练次数、日期标记 | 年度次数图、全部/训练/称重/围度筛选、全部历史、按天记录、动作及逐组明细、RIR 补录 |

使用系统 `NavigationStack`、`List`、`Section`、`ControlGroup`、`Button`、`Menu`、`Picker`、`DisclosureGroup`、`ProgressView`、`Form`、`DatePicker`、sheet/alert 和 Swift Charts。录入/目标按钮使用 `.glassProminent` / `.glass`，工具栏与导航采用系统样式；没有自绘玻璃、模拟模糊、WebView 或截图填充页面。内容区域保留系统分组列表材质，避免给每条数据叠加玻璃。

日历是 `UICalendarView`，`UIViewRepresentable` 只做日期、单选和系统装饰点的绑定；没有手绘日期网格。显示训练/称重/围度/多项标记，点日期过滤记录，取消日期选择可恢复整月或全部历史。

人体图属于图示内容，使用已有 `frontend/src/lib/body-paths.js` 的 MIT 轮廓，导出 38 个 Xcode SVG template image，交给原生 `Image` 绘制和按实际数据着色。许可随 App 资源打包。没有新增图像生成素材或第三方运行时依赖。

本轮未修改 RootView/NativeTabBarAnchor 或首页其他并行改动。Xcode 工程及 Package.swift 的接入是在当前内容上增量添加，保留已有条目。

## 数据与持久化

- `WorkoutSet.rir`、`WeighIn.bodyFatPercent` 为可选字段；旧记录缺失时为 nil。新增 `bodyMeasurements` 存档字段为可选，旧快照恢复为空数组。
- 体脂与围度可从身体页新增、更新；旧称重入口更新体重时保留已有体脂。新表单允许清空体脂。去脂体重仅由同日体重与体脂计算，明确标记估算。
- 已完成训练组支持在“开始”页选填 RIR，也可在身体页历史明细中补录/清除。仅已完成且 RIR 在 0…10 的组纳入强度统计。未评分不当作 0；目前没有可信的强度估算来源，页面不生成估算评分。
- 肌肉训练量 = 已完成组数 × 目录中的肌群参与权重；颜色按本期最大值归一化。未记录疲劳/恢复信号，因此不展示推测的恢复结果。
- 体重范围按当前本地自然日筛选，不把最后一次记录日期冒充今天。体重的“最新”摘要独立于筛选范围。
- 训练统计及日历按完成日期归属；未结束、将来的训练不计入 BodyAnalytics。周从周一开始；本周未训练且尚未结束时，允许延续上周的连续周数。
- 写入失败时称重、围度、RIR、记录删除和目标变更恢复内存状态，显示系统错误提示。录入表单仅成功保存后关闭。没有迁移/删除用户实际存档。

## 文件入口

- `frontend/ios/App/App/Native/BodyView.swift`：主体及趋势。
- `BodyRecordsSection.swift` / `BodyCalendarView.swift`：记录、日历与评分补录。
- `BodyEntrySheet.swift`：称重、体脂及围度原生表单。
- `BodyMuscleMap.swift` / `Assets.xcassets/BodyMap` / `BodyMapNotices.txt`：人体矢量资源。
- `BodyAnalytics.swift`：纯 Foundation 统计。
- `GymModels.swift` / `GymStore.swift` / `WorkoutView.swift` / `Catalogue.swift`：可选记录字段、保存与训练评分接入。
- `frontend/ios/Tests/BodyCoreTests/BodyAnalyticsTests.swift`：12 项 XCTest，已加入但未执行。

## 验证状态

已执行 `scripts/ios/check-native-body.py`：12 个 Swift 文件语法树解析、工程对象/引用、38 个矢量资源与源轮廓逐路径对照、许可资源、原生组件与无网页仿制检查均通过。结果保存在 `body-page-static-checks-2026-10-23.json`，含文件 SHA-256。`git diff --check` 对本轮已跟踪修改通过。

这些检查不是 Swift 类型检查，也不是 Xcode 编译。当前 Windows 未找到 Swift/Xcode 或可用 Mac 入口，因此以下项目仍未验证：

1. Swift XCTest 的 12 项行为测试（旧字段解码、记录往返、日期范围、跨午夜、跨年/DST、连续周数、缺失评分、分组均值、肌肉贡献、日期合并）。
2. Xcode 26+ 编译、SwiftUI 类型检查、SVG 资源编译及既有壳工程依赖生成。
3. iPhone/iPad 上原生 Liquid Glass、目录定位、展开收起、日历翻月和筛选、表单保存后重启恢复。
4. 浅色/深色、大字号、VoiceOver、横屏以及长记录列表。

复核命令：

```text
python scripts/ios/check-native-body.py
swift test --package-path frontend/ios --filter BodyAnalyticsTests
```

在 Mac 上，按同目录 `WATER_HOME_IMPLEMENTATION_2026-10-23.md` 的既有壳工程准备步骤生成 Pods/public/config 等依赖后，使用 Xcode 26+ 构建模拟器。没有执行打包、签名、上传、提交或推送。

API 依据：[Apple Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[safeAreaBar](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:))、[UICalendarView](https://developer.apple.com/documentation/uikit/uicalendarview)。

## 远程交付准备

本次交付以 `origin/main` 的 `32d9f434935d07d4fc45fd8ffe888f3d4c4c0531` 为基线，保留远程新增的签名配置，仅加入本页及必需数据/录入改动。共享文件中并行开发的其他训练功能、饮水页改动未纳入。静态检查在隔离的候选提交内容上重新执行，报告中的 SHA-256 对应该候选内容；编译与真机验收状态不变。
