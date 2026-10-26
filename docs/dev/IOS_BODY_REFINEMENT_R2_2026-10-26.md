# 身体页 R2 真机反馈整改 · 2026-10-26

状态：本轮代码和静态复核已完成，**未取得修改后的 Xcode/模拟器/真机证据，视觉与整屏分页仍待验收**。上一轮静态报告没有被当作本轮视觉通过依据。

## 实际查看的输入

已使用图片查看工具读取 `C:/Users/win11/AppData/Local/Temp/codex-clipboard-d8b1f3f2-4ebf-4ccb-b402-3f1e62e9f72e.png`：

- “身体”标题比旁边四项胶囊导航弱，导航的玻璃背景和选中圆片占据过多注意力。
- 肌肉卡中的详情按钮有显式玻璃外观。
- 全局底栏下方仍露出下一张“强度”标题，不能认定已经整块一屏。

这是修改前的真机反馈，不是本轮修改后的运行截图。

## 本轮基线与精确写入范围

写入前快照：`C:/Users/win11/AppData/Local/Temp/opengym-body-r2-before-e36dbb60f15742d3a0225987c1f664ac`。包含本页相关源文件、旧说明/报告、`hashes.json` 和当时完整 `git status --short` 的 `status.txt`。

本地 HEAD 未随上一批独立远程提交移动，工作区已有上一批修改；**不能把相对 HEAD 的整个 diff 当成 R2 增量**。本轮以下对照均以刚保存的 before 快照为准。

仅写入四个路径：

| 路径 | 相比本轮 before 的增量 |
| --- | --- |
| `frontend/ios/App/App/Native/BodyView.swift` | 重排顶部标题/四项导航；统一滚动视口与每页的尺寸来源；替换 7 处显式玻璃按钮样式 |
| `scripts/ios/check-native-body.py` | 原生内容按钮检查改为标准按钮；增加无显式玻璃、共用视口尺寸和轻量文字导航检查 |
| `docs/dev/body-page-refinement-r2-static-checks-2026-10-26.json` | 新增 R2 静态报告，不覆盖 R1 报告 |
| `docs/dev/IOS_BODY_REFINEMENT_R2_2026-10-26.md` | 本交接文档 |

两个已有文件的 before / after SHA-256：

```text
BodyView.swift
before 9F8FEDA9424ACC7274071412DF95612439F773B0FFEFECF04C03754BD8C8C981
after  E4D5C3C45BDFE137FC34525DB4DFAE6F8153C5C3AF7FBE527CB60163674E61FF

check-native-body.py
before FCC47BC3782A87FC09A1B09BCA9741B06F0B77B7E25A19B1479FB4498CC46FD2
after  4913D48076F102F15A2C955F8F14A8ADE31ED50D5543634754E045549B77607E
```

本轮核对了 `BodyMuscleMap.swift`、`BodyRecordsSection.swift`、`BodyEntrySheet.swift`、R1 说明/报告和 10 月 23 日说明/报告的原始哈希，均与 before 相同。它们在总工作区里可能仍显示为修改或未跟踪，那是先前内容，不是 R2 新增。

RootView、全局 Tab、TodayView、PlanView、WaterView、WorkoutView、工程文件及所有其他任务路径未写入。未执行 add、commit、push、pull、reset、stash、clean 或分支切换，远程交付由总控统一处理。

## 顶部与按钮调整

- “身体”从导航组内普通 headline 改为左上角独立 `.title2.bold()`，四项导航放在同栏中部。
- 四项导航改为原生 Button + `.plain`：无整体 segmented 胶囊，选中项用主文字色、加粗和下划线标识，并提供 VoiceOver 选中状态；每项至少 44 × 44 的点击区域。
- 使用系统 `.sharedBackgroundVisibility(.hidden)` 仅去掉标题/文字导航两个 toolbar item 的共享背景，不自绘导航背景。导航栏与加号 Menu 的系统默认行为保留。
- 狭窄宽度或辅助功能大字号继续提供原生 Menu，所有四个目标都可达；正常尺寸展示四个文字入口。
- 文字按钮和 Menu 继续使用同一个 `pageSelection`，与 `.scrollPosition(id: $visibleSection, anchor: .top)` 双向同步，未另建导航状态。
- 内容层 2 处 `.glassProminent` 改为系统 `.borderedProminent`，5 处 `.glass` 改为 `.bordered`。覆盖主卡详情、记体重、最近日期、极短高度入口，以及详情中的记体重、目标、记围度。
- 对全部 `Body*.swift` 的扫描确认没有 `.glass` / `.glassProminent` 按钮、`.glassEffect` 或 GlassEffectContainer。录入 sheet、记录编辑/删除和系统导航原本没有显式玻璃样式，保留原生默认控件。

按 Apple 的 [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) 区分导航层与内容层，避免在内容层叠加 Liquid Glass；按钮采用 [SwiftUI 标准 Button 样式](https://developer.apple.com/documentation/SwiftUI/Button?language=_11)。toolbar item 背景调整使用 [系统共享背景 API](https://developer.apple.com/documentation/swiftui/customizabletoolbarcontent/sharedbackgroundvisibility%28_%3A%29?changes=_4)。

## 整页高度修正及边界

旧代码由每页内部 GeometryReader 加 `containerRelativeFrame(.vertical)` 得到页高，而 `.paging` 按 ScrollView 几何决定停靠。ScrollView 在系统导航/底部安全区下的延展与相对容器扣除安全区可能导致两种尺寸口径。**这是从代码发现的风险，截图只能证明露页，不能单独证明实际运行时的 inset 数值。**

本轮把 GeometryReader 移到 ScrollView 外，在 NavigationStack 内容区域只测量一次。四页各自的 frame 与 ScrollView 的 frame 都使用同一个 `viewport.size.width/height`；卡片 padding 位于页框内部，零间距栈及系统 `.paging` 保留。删除每页的 `containerRelativeFrame`，不再重复推算或扣除安全区。

没有添加 `.clipped()`、clipShape、mask、隐藏下一页、硬编码底栏高度、UIScreen 高度或忽略安全区。通过统一布局尺寸处理问题，没有删掉卡片内容来凑高度。完整/紧凑/最简详情入口的原有适配仍保留。

Root 任务同时负责底栏实际高度及安全区；这里消费宿主提供的安全区域，没有修改 Root。必须基于双方最终组合在同一台 iPhone 复测，当前不能宣称“已确认不再露页”。

四张卡片、真实数据、所有图表与详情 sheet、日期筛选、目标、体重/围度编辑删除和 RIR 补录均保留；本轮没有更改统计和保存逻辑。

## 验证

```powershell
$env:PYTHONPATH = 'C:\Users\win11\.codex\tmp\opengym-body-deps'
& 'C:\Users\win11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' scripts/ios/check-native-body.py --paging --report docs/dev/body-page-refinement-r2-static-checks-2026-10-26.json
git diff --check -- frontend/ios/App/App/Native/BodyView.swift scripts/ios/check-native-body.py
```

结果：静态检查退出码 0，22 项通过；12 个 Swift 文件语法树无错误，工程引用检查无缺失，38 个矢量资源仍匹配；拥有路径的 diff 空白检查通过。已对 before 与当前源代码做独立 `git diff --no-index` 复核，并核对受保护文件哈希。

新增检查只证明源代码中一个外层 GeometryReader 给目标/视口提供相同 frame、文字导航使用同一绑定以及没有显式玻璃/额外裁切，**不能证明 UIKit 实际视口高度、SwiftUI 类型推导或视觉效果**。

当前 `swift`、`xcodebuild` 均不可用，未运行 Xcode 编译或 12 项既有 XCTest。没有生成伪真机图来替代本次验收。报告包含检查时点共享文件哈希，总控合并其他任务后需重新验证最终树。

## 总控接续验收

1. Xcode 26+ 编译，重点检查 toolbar 共享背景 API、文字导航和分页的 SwiftUI 类型推导。
2. 使用提交反馈的同一设备/字体/方向复测：标题明显强于导航；四个文字项和加号不挤压；没有原截图的大胶囊；主卡和 sheet 的普通功能按钮无显式玻璃。
3. 结合 Root 最终安全区改动，在四页分别执行慢拖、快速滑动及顶部点击。停靠后整张卡位于顶部栏与底栏之间，底栏下不再露出下一标题，内容和详情入口均可见。
4. 验证上下滑动与顶部选中项双向同步、切换全局 Tab 后恢复、旋转及改变字号；特别检查短高度/辅助功能字号下的详情入口。
5. 复核图表选点与翻页手势协作；日期打开当天明细、录入/编辑/删除、目标和 RIR 操作仍能正确保存与显示错误。

以上设备和视觉项目全部保持**未验证**，不能因本轮静态检查通过而关闭真机退回项。
