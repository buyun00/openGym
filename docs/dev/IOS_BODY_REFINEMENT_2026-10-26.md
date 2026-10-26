# iOS 身体页整改交接 · 2026-10-26

状态：本轮代码已实现，Windows 静态检查通过；**未经过 Swift 类型检查、Xcode 编译或设备视觉/手势验收**。本轮没有执行 Git 暂存、提交、推送、拉取、重置、清理、stash 或切换分支，交由总控统一处理。

旧版 `d90f43a3` 已在远程的事实只对应 10 月 23 日长列表版本，不能作为本轮整屏分页的交付或验收依据。本轮是新的工作区改动。

## 截图与本轮范围

已实际查看 `C:/Users/win11/AppData/Local/Temp/codex-clipboard-c1c8e242-45f3-4c25-a296-099ec7eb77e5.png`。截图中的旧页面有大标题下独立四项导航、长列表、体重历史区域与底部 Tab 重叠以及下一块露出的问题。该截图是整改输入，不是修改后运行证据。

已检查仓库和祖先目录，未发现适用的 `AGENTS.md`。只写下列六个路径：

| 本轮路径 | 内容 |
| --- | --- |
| `frontend/ios/App/App/Native/BodyView.swift` | 四张原生分页卡片、顶部导航同步、四类详情 sheet、共用体重图表、紧凑/大字号布局 |
| `frontend/ios/App/App/Native/BodyMuscleMap.swift` | 人体图按卡片可用高度等比缩放；详情保留原完整图例 |
| `frontend/ios/App/App/Native/BodyRecordsSection.swift` | 接收所选日期/月作为 sheet 初始状态；筛选菜单和日期取消操作适配换行 |
| `scripts/ios/check-native-body.py` | 新增 `--report` 输出路径和 `--paging` 结构检查，保留旧检查能力 |
| `docs/dev/body-page-refinement-static-checks-2026-10-26.json` | 本轮新静态报告及检查时点的文件哈希 |
| `docs/dev/IOS_BODY_REFINEMENT_2026-10-26.md` | 本交接文档 |

没有新增 Swift 文件，不需要调整 Xcode 工程或 Package.swift。没有修改 RootView、TodayView、全局 Tab、PlanView、WorkoutView、WaterView、同步/持久化模型或统计算法。

## 布局和交互

- 主界面只有“体重、肌肉、强度、记录”四个目标。零间距 `LazyVStack` 配合系统 `.scrollTargetBehavior(.paging)`；每页 `.containerRelativeFrame(.vertical)` 按最近 ScrollView 的安全区可用高度布局。卡片的内外间距在页框内部，未写屏幕高度、Tab 高度、忽略安全区或自定义拖动吸附。
- 当前 RootView 已通过底部 `safeAreaInset` 给全局 Tab 预留空间；身体页继承该安全区，不接管底栏。页面可用高度仍需要在实际宿主和旋转时验证。
- 顶部改为 inline 导航栏，“身体”、四项系统 segmented Picker 和原生加号 Menu 同处一栏。没有旧的大标题下导航行。窄宽度/辅助功能字号时四项入口收进同栏原生 Menu，保持文字可读。
- `ForEach`、页 `.id`、`.scrollPosition` 使用同一 `BodySection` 类型；Picker 通过同一个绑定翻页，手动翻页回写顶部选中项。减少动态效果开启时取消程序化翻页动画。
- 内容卡使用系统 GroupBox，操作使用系统 `.glass` / `.glassProminent`、Picker、Menu、sheet 和 alert。图表使用 Swift Charts，人体图沿用已授权矢量资源；没有自绘玻璃、模糊叠层或网页仿制。
- 主卡没有 DisclosureGroup、List 或嵌套滚动日历。卡片内容通过系统 `ViewThatFits` 在完整、紧凑和简明入口间选择，字号不缩小、不截断文字、不裁切图表。极短高度和最大辅助字号下完整内容由可滚动详情承载，主卡保留可读入口。

| 主卡 | 默认内容 | sheet 中完整保留的内容 |
| --- | --- | --- |
| 体重 | 实际最新体重/日期、所选期间变化、范围选择、曲线、录入及详情入口 | 目标设置/清除、完整体重图、体脂率/去脂体重图、称重编辑/删除/加载更早、围度及录入 |
| 肌肉 | 范围、正背面人体图、覆盖肌群数、训练最多的肌群 | 全肌群组数、进度条、未覆盖部位、完整图例和统计说明 |
| 强度 | 共用训练范围、实际平均 RIR、评分覆盖量、周趋势 | 强度分布、周趋势、说明、动作重量/次数趋势；缺失评分保持未记录 |
| 记录 | 所选月/累计/本周次数、连续周数、近 12 个月次数图、最近两个实际记录日期 | 原生可翻月日历、所有记录类型、全部历史、按日期过滤、训练/动作/逐组明细、RIR 补录、编辑/删除/加载更早 |

记录主卡以实际最近日期为快捷入口。点日期把所选日期和月份交给记录 sheet；点“日历与全部记录”清除日期过滤，进入所选月份并可打开全部历史。完整 UICalendarView 放入 sheet，避免内部月历滚动与主界面的垂直翻页竞争。紧凑卡省去最近日期快捷行，完整历史仍在 sheet 中。

详情与主卡共用体重/训练范围绑定。详情中的录入使用它自己的原生子 sheet，避免在父 sheet 展示期间从主页面重复发起展示。新增/编辑/删除/目标/RIR 均继续调用现有 GymStore；保存失败提示仍在当前显示层出现。围度的同步扩展字段和体脂率保留展示。

API 依据：[Apple 原生分页](https://developer.apple.com/documentation/swiftui/pagingscrolltargetbehavior)、[Apple 容器相对尺寸与安全区](https://developer.apple.com/documentation/swiftui/view/containerrelativeframe%28_%3Aalignment%3A_%3A%29?changes=_1)。这些文档说明 API 行为，不能替代本项目运行验收。

## 开始写入前的已有改动

本轮开始写入时，三个 Body Swift 文件和身体页检查脚本均未修改。以下内容已经脏，本轮没有将它们纳入修改范围。并行任务之后可能继续改变该列表。

```text
 M .dockerignore
 M .gitignore
M  api/Dockerfile
M  api/server.js
M  api/test/server-admin-delete.test.js
A  api/test/workout-sync-events.test.js
A  api/workout-sync-events.js
 M docs/dev/BODY_PAGE_IMPLEMENTATION_2026-10-23.md
 M docs/dev/IOS_SHARED_BACKEND_2026-10-23.md
 M docs/dev/body-page-static-checks-2026-10-23.json
 M frontend/ios/App/App.xcodeproj/project.pbxproj
 M frontend/ios/App/App/Native/GymCloudSync.swift
 M frontend/ios/App/App/Native/GymConnectionView.swift
 M frontend/ios/App/App/Native/PlanView.swift
 M frontend/ios/App/App/Native/RootView.swift
 M frontend/ios/App/App/Native/TodayView.swift
 M frontend/ios/App/App/Native/WaterView.swift
 M frontend/ios/App/App/Native/WellnessSettingsSheet.swift
 M frontend/ios/App/App/Native/WorkoutExerciseCard.swift
 M frontend/ios/App/App/Native/WorkoutSheets.swift
 M frontend/ios/App/App/Native/WorkoutView.swift
 M scripts/ios/check-native-home.py
 M scripts/ios/check-native-sync.py
 M scripts/ios/check-native-workout.py
?? api/ios-personal.js
?? api/test/ios-personal.test.js
?? docs/dev/IOS_HOME_REFINEMENT_2026-10-26.md
?? docs/dev/IOS_PLAN_REFINEMENT_2026-10-26.md
?? docs/dev/IOS_WATER_REFINEMENT_2026-10-26.md
?? docs/dev/ios-home-static-checks-2026-10-26.json
?? docs/dev/ios-workout-refinement-static-checks-2026-10-26.json
?? scripts/ios/embed-personal-connection.sh
?? scripts/ios/setup-personal-connection.mjs
```

写入前快照位于本机临时目录 `C:/Users/win11/AppData/Local/Temp/opengym-body-refinement-4f2ac46af54847199d7ca92c630f8866`。旧身体页说明和旧报告的 SHA-256 在本轮复查时与写入前一致：没有覆盖其已有脏内容。

## 验证结果

执行：

```powershell
$env:PYTHONPATH = 'C:\Users\win11\.codex\tmp\opengym-body-deps'
& 'C:\Users\win11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' scripts/ios/check-native-body.py --paging --report docs/dev/body-page-refinement-static-checks-2026-10-26.json
git diff --check -- frontend/ios/App/App/Native/BodyView.swift frontend/ios/App/App/Native/BodyMuscleMap.swift frontend/ios/App/App/Native/BodyRecordsSection.swift scripts/ios/check-native-body.py
```

- 静态检查退出码 0，19 项检查通过；12 个 Swift 文件语法树无错误、Xcode 工程引用完整、38 个原生矢量资源与源轮廓一致。
- 本轮附加检查包含四页声明、系统分页/容器尺寸、同类型分页 ID 与双向绑定、顶部 inline 导航、主卡无展开/内嵌月历/忽略安全区/裁切、大小布局和详情入口、日期传递以及编辑与错误处理入口仍存在。
- 这些结构检查只能证明源代码结构，不能证明实际分页停靠、SwiftUI 类型推导、原生材质或屏幕布局正确。
- 本轮拥有路径的 `git diff --check` 通过。旧报告和旧说明的原始文件哈希保持不变。
- 当前 Windows 找不到 `swift` 和 `xcodebuild`。已有 12 项 BodyAnalytics XCTest 未运行；本轮没有更改统计算法。

报告也包含检查时点的共享模型、WorkoutView 和工程文件哈希；这些文件属于并行工作。总控集成完成后应以最终树重跑检查，不能将本报告当作后续共享修改的证明。

## 仍需 Mac / 设备验收

1. 用现有 iOS 构建流程执行 Xcode 26+ 编译和 `swift test --package-path frontend/ios --filter BodyAnalyticsTests`。
2. 小屏及标准 iPhone 竖屏：四页分别完整停靠在导航栏与底部 Tab 之间；慢拖、快速滑动、连续翻页均不在半张卡停住，不遮挡底部操作。
3. 顶部选择任意页、再手动上下翻页，验证双向选中状态；返回全局“身体”Tab、旋转设备、改变字号后仍定位正确。
4. 曲线轻触/横向选点和从曲线区域上下翻页的手势协作；记录 sheet 内月历翻月不影响外部页码。
5. 最近日期打开对应日明细；打开全部记录清除日期过滤；筛选、加载更早、训练逐组 RIR、新增/编辑/删除/目标保存、失败提示、重启持久化及实际同步均回归验证。
6. 浅色/深色、辅助功能最大字号、VoiceOver、减少动态效果、短高度横屏/iPad 分屏；确认完整/紧凑/最简入口切换后全部数据仍可从 sheet 阅读和编辑。

本轮没有修改后模拟器截图或真机录像；不得标记视觉、整屏适配、手势或设备验收通过。完成上述检查和统一 Git 交付的责任仍在总控流程。
