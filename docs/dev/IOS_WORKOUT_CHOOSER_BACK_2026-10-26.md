# 训练选择页返回按钮与左划返回（2026-10-26）

已完成源码修改和静态检查，**未运行 Swift 类型检查、Xcode、模拟器或 iPhone 手势测试**。没有操作真实训练记录，没有执行暂存、提交、推送、拉取、重置、stash、clean 或切换分支。由总控统一交付。

## 写前快照与本轮范围

写入前已保存 `WorkoutView.swift`、训练检查脚本的原始内容和 SHA-256：

`C:/Users/win11/AppData/Local/Temp/opengym-chooser-back-before-562luzir/`

`manifest.json` 记录基线；`chooser-back.patch` 是相对此 before 的源码增量。共享 checkout 含有此前已交付改动，**未将相对本地 HEAD 的全部 diff 计入本轮**。仓库和上级目录未找到适用的 AGENTS.md。

本轮写入仅以下三个文件，路径相对 `D:/其他项目/openGym`：

| 文件 | 本轮变化 |
| --- | --- |
| `frontend/ios/App/App/Native/WorkoutView.swift` | 训练选择页顶部返回按钮、只作用于选择列表的左划手势、共用返回动作 |
| `docs/dev/ios-workout-chooser-back-static-checks-2026-10-26.json` | 新的静态检查记录与文件哈希 |
| `docs/dev/IOS_WORKOUT_CHOOSER_BACK_2026-10-26.md` | 本交接 |

`scripts/ios/check-native-workout.py` 仅运行，没有修改。未写入 `RootView.swift`、`TodayView.swift` 或任何 Store/数据模型。

## 实现

- 无 active 训练时，在原生导航栏左侧显示“返回首页”及左箭头，显式 `.labelStyle(.titleAndIcon)`；标题使用 inline 模式，保持返回入口清楚可见。按钮不增加显式玻璃效果。
- 把无 active 的模板/自由训练列表提取为 `chooserList`。本页当前只有纵向 List、普通模板按钮和空状态，没有横向模板滚动区或 swipeActions。
- **按用户指定支持向左划返回**，没有改成通常的向右划。手势仅挂在这个选择列表上，不挂到整个 NavigationStack、工具栏、已有 active 的继续入口或 ActiveWorkoutView，因此不会作用于进行中训练的横向动作选择。
- 使用 `simultaneousGesture(DragGesture(...))` 与纵向列表手势共存，不使用 highPriorityGesture 抢占列表。最小拖动识别距离 32 pt，仅在结束时检查实际位移：`dx <= -100`、`abs(dy) <= 32`、`-dx >= abs(dy) * 3` 全部成立才返回。不使用预测终点，因此很短的快速 flick 不会单凭速度返回。API 依据：[Apple DragGesture](https://developer.apple.com/documentation/swiftui/draggesture)、[Apple simultaneousGesture](https://developer.apple.com/documentation/swiftui/view/simultaneousgesture(_:including:))。
- 按钮和手势共用 `returnToToday()`。它再次确认 `store.tab == .workout`、`store.active == nil`、`presenting == false`，然后只设置 `store.tab = .today`。这是已有页面路由，不依赖用户点击底部 Tab，不调用开始、结束、保存、放弃或任何持久化方法。
- `RootView` 当前已根据 `store.tab` 显示训练选择页，并观察 `.today` 路由；因此无需全局文件配合。

## 分支核对（源码，不是设备操作）

| 状态/输入 | 本轮代码路径 |
| --- | --- |
| 没有模板 | “还没有计划”和自由训练入口仍位于 chooserList；返回按钮和左划与模板数量无关 |
| 有普通模板/今天计划 | 原模板按钮、其他训练日、开始全部今天计划的条件和动作原样保留；返回处理不创建训练 |
| 已有 active 训练 | 使用不带该手势的继续训练 List；既有 onAppear/onChange/fullScreenCover 自动恢复流程保留；不显示选择页返回按钮 |
| 模板点击已经创建 active | 共用返回动作的 active/presenting guard 阻止退出该训练 |
| 点击、短划、右划 | 不满足左移 100 pt 的条件 |
| 明显纵向或斜向拖动 | 不满足纵向偏移/方向比例条件 |
| 进行中训练 | `enum WorkoutSheet` 之后的原文件内容与 before 完全一致，包括原有收起、结束、放弃、输入、计时及页面级手势范围 |

如果未来选择列表新增横向交互或模板行 swipeActions，应缩小该手势的挂载区域或加入手势协调，不能直接把当前“纯纵向列表”的假设沿用过去。当前改动没有给全局页面加左划手势。

## 已运行检查

在仓库根目录执行：

```powershell
& 'C:\Users\win11\AppData\Local\Temp\opengym-workout-checks\Scripts\python.exe' `
  'scripts/ios/check-native-workout.py' `
  --output 'docs/dev/ios-workout-chooser-back-static-checks-2026-10-26.json'

git --no-optional-locks diff --check -- `
  frontend/ios/App/App/Native/WorkoutView.swift `
  docs/dev/IOS_WORKOUT_CHOOSER_BACK_2026-10-26.md
```

结果：15 个 Swift 源/测试/Package 文件语法树检查通过；工程源/资源注册与 6554 个动作目录/媒体引用检查通过；训练显式玻璃调用仍为零；限定路径 diff 空白检查通过。已有 11 项 XCTest 未执行。

另外使用 Python 对比 before：`WorkoutSheet` 及其之后的内容没有变化，检查器 SHA-256 没有变化，并输出只含训练选择页变化的 `chooser-back.patch`。报告哈希与本轮完成时文件一致。没有把源码条件核对包装成手势测试通过。

## 待真机 / Mac 验证

1. Xcode 26+ 编译、Swift 类型检查及现有 XCTest。当前 Windows 无 Swift/Xcode 环境。
2. 从首页训练卡片进入空模板、单模板、多模板选择页；返回按钮文字、箭头和标题在小屏/大字号下可见，并正确回到首页。
3. 在列表空白、空状态及模板行区域分别向左划，验证 100 pt 阈值、纵向偏移限制及返回响应；右划、短划、点击、纵向滚动、斜划不返回。
4. 验证 SwiftUI List 与 simultaneousGesture 在实际 iOS 版本上的协调：长列表仍顺畅纵向滚动，普通模板点击仍只开始一次训练，拖动不会误触模板启动。这些运行时触摸竞争无法由静态检查确认。
5. 已有 active 的自动恢复、进行中动作切换/数值输入/收起/结束和放弃确认不受页面级左划影响；只使用专门测试会话验证，不执行用户真实训练的结束或放弃。

本轮不包含新的远程交付结论，供总控统一提交和设备验收。
