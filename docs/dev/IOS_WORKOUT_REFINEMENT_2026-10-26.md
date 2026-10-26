# iOS 训练进行中页面调整交接（2026-10-26）

本轮已完成源码修改及静态检查，**未完成 Swift 类型检查、Xcode 构建、模拟器/真机视觉或弹窗交互验收**。没有操作用户的真实训练来执行结束、保存或放弃，没有构造训练记录。未执行 git add/commit/push/pull/reset/stash/clean 或切换分支，由总控统一交付。

## 输入与问题定位

实际查看了总控提供的两张用户截图：

- `C:/Users/win11/AppData/Local/Temp/codex-clipboard-88479b96-9809-4c3a-a194-60c3ac847b7f.png`：标题下横杠和留白占用高度，动作编号远离导航栏，数值输入被玻璃包裹，完成按钮呈椭圆。
- `C:/Users/win11/AppData/Local/Temp/codex-clipboard-c81f6c7e-67d9-4e72-be51-6a82ae9de15d.png`：结束 sheet 内部被分为多个卡片，放弃确认呈带箭头气泡，并叠在结束 sheet 上。

仓库及其上级目录没有找到适用的 `AGENTS.md`。开始前读取了 staged/unstaged 状态，保留现有 API、同步、计划、首页、喝水、身体及工程文件等工作现场。下面的文件是本轮写入范围，其他页面及全局 Tab 不在范围内。

## 精确文件范围

| 路径（相对 `D:/其他项目/openGym`） | 本轮改动 |
| --- | --- |
| `frontend/ios/App/App/Native/WorkoutView.swift` | 紧凑顶部、动作选择、放弃确认的呈现流程、结束 sheet 高度 |
| `frontend/ios/App/App/Native/WorkoutExerciseCard.swift` | 完成按钮形状与输入中心对齐、普通数值输入外观、小屏/大字体布局 |
| `frontend/ios/App/App/Native/WorkoutSheets.swift` | 结束操作放入同一个容器、继续训练、将放弃请求交回训练页 |
| `scripts/ios/check-native-workout.py` | 增加可选 `--output`，本轮检查不覆盖 10 月 23 日历史证据 |
| `docs/dev/ios-workout-refinement-static-checks-2026-10-26.json` | 本轮静态检查与源文件 SHA-256 |
| `docs/dev/IOS_WORKOUT_REFINEMENT_2026-10-26.md` | 本交接 |

## 实现

### 顶部空间、动作切换

横杠来自 `ActiveWorkoutView` 内容栈的 `ProgressView`，代表已完成组数 / 全部组数。顶部标题下的计数已经表达同一状态，因此移除重复进度条，保留实际计时、完成组数及 VoiceOver 描述。原来的零高度滚动锚点仍会在 `LazyVStack` 中产生相邻间距；现在把锚点设在内容栈本身，正文顶部内边距改为 8 pt。

收起按钮、训练标题、菜单和结束按钮保留在系统导航 toolbar。标题单行截断，完整文字仍是其无障碍内容；结束文字固定自身尺寸。辅助功能大字体时，导航栏显示短标题“训练中”，完整训练名（最多两行）和时间/组数移到紧邻其下的顶部区域，避免把全部信息挤在同一行。

动作选择通过 `safeAreaInset(edge: .top, spacing: 0)` 固定在导航栏下方，与正文滚动区域分开。使用公开 SwiftUI 安全区布局 API 为控件预留空间，避免用覆盖层遮挡正文。参考：[Apple safeAreaInset](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:))。

页内动作切换采用以下规则，不新增全局底栏：

- 普通字体、最多 5 个动作且横向宽度足够时，用原生 `.segmented` Picker，显示编号和完成标记。为每项预留至少 56 pt 宽度，选择区至少 44 pt 高，使用系统 large 控件尺寸。
- 动作更多、可用宽度不足或辅助功能大字体时，用横向滚动的 SwiftUI Button 页签，按钮至少 44×44 pt，保留编号、完成标记、选中态、动作完整名称的无障碍描述。切换“上一个/下一个”时会把对应页签滚到可见范围。
- 卡片模式切换后回到动作顶部；列表/紧凑模式保留滚动到指定动作的路径。

选择分段 Picker 是因为它适合有限数量的互斥选项；多动作时固定分段不适合继续压缩，故采用滚动页签回退。原生全局 TabView 会增加另一套顶层导航，分页 TabView 也不适合同时承担已有列表/紧凑模式的定位，因此本轮不引入。分段样式依据：[Apple SegmentedPickerStyle](https://developer.apple.com/documentation/swiftui/segmentedpickerstyle)。这些是实现选择，实际布局尺寸和点击范围仍需设备验证。

### 每组完成按钮与数值输入

完成按钮改为 `.plain`，使用圆形 SF Symbol，明确指定 44×44 pt 点击区域，去掉原来玻璃按钮默认边距与外层 40 pt 宽度的组合。新增私有 `workoutInputCenter` 对齐线，将数字输入控件的中心传递到整行；按钮不再按包含单位标题的整个单元格对齐。小屏/辅助功能回退布局中，完成按钮对齐最后一个数值输入框。

重量、次数、分钟、速度、坡度、秒数仍共用 `WorkoutNumberField`：

- 移除 `glassEffect`，使用普通系统填充背景、8 pt 圆角、细描边和焦点描边；TextField 显式采用 `.plain`。
- 次数/秒数用数字键盘，其他指标用小数键盘；保留逗号小数转换、清空、直接编辑、加减、单位、步长、最小值/最大值与失焦回读。
- 继续调用既有 `store.setMetric` / `WorkoutMetric.apply`。未修改指标边界、保存逻辑或旧记录结构。
- 常规横排每个字段最小宽度 80 pt；横向放不下时改为逐项排列，辅助功能字号直接使用逐项布局，避免靠缩字塞入固定列。宽布局加减按钮为 44 pt 宽，紧凑横排保留原来的 24 pt 宽加减按钮。

完成/撤销仍调用 `store.toggleSet`，按钮先取消该组的本地倒计时；倒计时到点、停止计时、复制/删除组、RIR/RPE 等路径保留。未通过实际用户训练执行这些操作。

### 结束与放弃

结束内容改为 ScrollView 内的一个 VStack 卡片，按顺序容纳状态说明、“结束并保存”、“继续训练”、分隔线和红色“放弃不保存”。不再将说明/保存与另一个放弃卡片分开。“继续训练”只关闭 sheet，不写入训练数据。

普通字体的结束 sheet 从固定 310 pt 改为 400 pt，并可上拉至 large；辅助功能大字体直接使用 large。内容超出时可滚动，避免用固定高度裁剪操作。零完成、部分完成、全部完成三类说明继续读取真实组数。

训练菜单和结束页的放弃按钮只提交请求：记录当前 session ID → 关闭 sheet → 在 `.sheet(... onDismiss:)` 回调中呈现训练页的标准 `.alert`。警告框提供“放弃不保存”（destructive）和“取消”（cancel），不使用 `confirmationDialog` 或 popover，也不使用人为延时来猜测 sheet 何时消失。破坏性按钮再次比对 session ID，避免确认等待期间会话变化而丢弃其他会话。只有此按钮调用 `store.discardActive()`。

警告框使用公开系统 API，参考：[Apple alert](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:))。保存失败提示及原有 Store 持久化回滚保持；动作选项内“移除/替换动作”的确认不是本轮的整次训练放弃流程，本轮未修改。

## 已运行的检查

在 `D:/其他项目/openGym` 执行：

```powershell
& 'C:\Users\win11\AppData\Local\Temp\opengym-workout-checks\Scripts\python.exe' `
  'scripts/ios/check-native-workout.py' `
  --output 'docs/dev/ios-workout-refinement-static-checks-2026-10-26.json'

git --no-optional-locks diff --check -- `
  frontend/ios/App/App/Native/WorkoutView.swift `
  frontend/ios/App/App/Native/WorkoutExerciseCard.swift `
  frontend/ios/App/App/Native/WorkoutSheets.swift `
  scripts/ios/check-native-workout.py `
  docs/dev/IOS_WORKOUT_REFINEMENT_2026-10-26.md
```

结果：15 个 Swift 源/测试/Package 文件语法树解析没有 ERROR 或缺失节点；Xcode 源引用、资源注册、6554 个目录 ID 与媒体路径检查通过；限定路径 diff 空白检查通过。Git 提示 Windows 后续可能转换 LF/CRLF，这是换行提示。已有 11 项 XCTest **未执行**。检查器中 `actual_native_video_playback` / `native_glass_and_system_presentations` 等字段检查的是源码 API 标记，不证明播放器、系统材质或系统弹窗已实际运行。

另已人工检查：本轮只有一个 `WorkoutSessionSheet` 调用点并传入 `requestDiscard`；整次训练放弃从 sheet 的 confirmationDialog 迁到根页 alert；完成按钮/字段仍连接既有 Store 方法。检查原机 `swift`、`xcodebuild` 命令均不可用，未尝试将语法树检查写成编译通过。

## 待总控在 Mac / iPhone 验证

1. 对统一交付版本运行 `swift test --package-path frontend/ios`，再用项目既有 Xcode 26+ 流程编译 App。合并其他页面后重新运行静态检查，因为报告包含当时共享工程文件的哈希。
2. 320/375/390/420 pt 宽度、普通/辅助功能字号、明暗模式、横屏：标题/收起/菜单/结束没有重叠，顶部页签和正文间距合理，数字输入不被压扁，完成按钮等宽高并对齐输入中心。
3. 1、5、6、较多动作与长名称：分段/滚动切换分支、编号/完成标记、VoiceOver 名称、上一个/下一个及列表模式定位。核验系统分段选择实际触达范围。
4. 使用专门测试会话验证所有指标键盘输入、小数/空值/步进/边界、完成与撤销、倒计时自动完成、RIR/RPE；不要使用用户真实训练做破坏性验收。
5. 零/部分/全部完成时结束内容完整可读，“继续训练”和下拉关闭均保留会话。普通字号默认 400 pt 时内容应完整可见；大字体与横屏检查滚动和按钮可达性。
6. 从菜单及结束页触发放弃：先关闭 sheet，再出现无尖角的标准模态 alert；取消返回训练，重复打开不会叠加。仅在专门测试数据中验证确认放弃、写入失败回滚与失败提示，以及等待确认时会话 ID 变化的保护。

本轮未要求全局文件配合。首页对话继续拥有 `TodayView.swift` / `RootView.swift` / 全局 Tab；本轮的页内动作选择不依赖全局 Tab 的具体排列。
