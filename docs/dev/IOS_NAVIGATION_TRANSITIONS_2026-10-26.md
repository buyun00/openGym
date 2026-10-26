# 统一导航转场 · 2026-10-26

本轮已实际替换 Tab 的即时透明度路由，并把训练入口统一为一层原生全屏模态。只修改 RootView、WorkoutView 的导航衔接及专属静态检查；Today 卡片、四个 Tab 的页面内容、水体算法和训练数据操作保持原实现。

未执行 git add、commit、push、pull、reset、stash、clean 或切换分支，由总控审查后统一交付。以下源码/静态结果不能作为动画流畅、状态保留或真机手势验收通过。

## 导航路径

| 操作 | 本轮路径和转场 |
| --- | --- |
| 今天→计划→身体→喝水，或跨项向后选择 | 原生水平 UIPageViewController，按目标索引大于当前索引使用 forward，从右进入、当前页向左退出 |
| 逆序选择 | 使用 reverse，从左进入、当前页向右退出；跨几项仍只按索引方向切换一次 |
| 无 active，点击首页开始/再次训练 | Root 的原生 fullScreenCover 自下进入训练选择页 |
| 有 active，点击继续训练；或计划页已创建 active 后进入 | 同一个模态直接装入 ActiveWorkoutView，不先展示选择页，也不自动再弹第二层 |
| 在选择页确定某个计划/自由训练 | 原有 Store 方法创建记录；在同一模态内用 0.16 秒淡入切到实际训练内容，没有第二个 fullScreenCover |
| 选择页返回首页或按原要求向左划 | 同一关闭回调让模态向下退出，返回今天；不创建、保存、结束或放弃训练 |
| 进行中收起训练 | 同一关闭回调，向下退出，active 保留 |
| 成功结束/放弃训练 | 原有保存/确认逻辑完成后关闭这一层模态，未改数据逻辑或确认流程 |
| 已有页面 sheet / NavigationStack push | 保留系统原转场，没有给按钮或整棵 SwiftUI 树统一套动画 |

方向来自 [UIPageViewController.NavigationDirection](https://developer.apple.com/documentation/uikit/uipageviewcontroller/navigationdirection)：水平 forward 对应从右向左。页面切换使用公开 [setViewControllers](https://developer.apple.com/documentation/uikit/uipageviewcontroller/setviewcontrollers(_:direction:animated:completion:))，没有自绘 Tab 或读取原生内部视图。

## Tab 状态与快速操作

Root 不再用 `ZStack + opacity(store.tab == …)` 隐藏/显示页面。原生 UITabBar 仍有四个项目、使用整行导航可用宽度；内容交由水平 `.scroll` UIPageViewController 承载。

- 每个 AppTab 的 UIHostingController 创建后保存在 `hosts` 字典中，切回时复用同一控制器和 SwiftUI 身份，更新环境内容而不重新创建宿主。设计上保留 NavigationStack、表单状态和滚动视图；真实设备的滚动位置仍待验证。
- `requestedSelection` 只存最后一次目标，`displayedSelection` 记录实际已显示页。`transitionInFlight` 为真时不再调用 setViewControllers，避免重入原生动画。
- 完成回调从 `pager.viewControllers` 读取实际结果；若 UIKit 未落到目标，下一次恢复不用动画。解锁与处理后续目标放到下一次主队列，覆盖“SwiftUI update 在完成回调尚未退出时重入”的情况。
- 例如今天→计划过程中依次点喝水、身体，先完成当前一次转场，然后只处理最后的身体；不会排队依次播放所有中间点击。今天→喝水过程中又点今天，则当前转场结束后按逆序返回。
- 转场未稳定或模态正被请求时，页面区域禁止点击和 VoiceOver 访问；Tab 本身在正常页面转场时仍可接收最后一个目标。没有两个页面同时可操作的设计路径。
- 旋转/尺寸转场期间延后新请求；初次显示、宿主未显示、模态覆盖下的路由和异常恢复不播放水平位移。
- pager 不设置 dataSource，因此不额外添加全屏横滑导航手势，不抢占页面原有滚动、输入、图表或动作控件手势。原生 Tab 的选择行为保留。此用法依据 [UIPageViewController](https://developer.apple.com/documentation/uikit/uipageviewcontroller) 的程序控制/手势数据源边界。

没有以截图/快照替代页面，没有维护一次性页面副本。UIKit 动画中实际的暂停、旋转和快速拖动表现仍须真机验证。

## 训练模态与真实数据边界

Root 的 `workoutPresented` 通过 `store.tab` 路由变化驱动，当前代码只有 Root 一个训练 `fullScreenCover`。WorkoutView 的 `resuming` 参数在进入时读取真实 active，初始化 `showingActive`；继续路径首帧就是实际训练界面。

选择页创建 active 后只把 `showingActive` 从 false 改为 true；成功结束/放弃后不再改回 false，因此关闭时不会短暂重现选择列表。若 active 已消失，则走同一关闭回调。退出回调只设置 `.today` 和模态状态，不调用 finish、discard、save 或 start。

ActiveWorkoutView 相对 before 只有三处导航替换：原 `dismiss` 环境入口改为 `onClose`；active 变为 nil 时调用 `onClose`；“收起训练”调用 `onClose`。结束菜单、放弃二次确认、记录写入、保存失败处理、计时、媒体及其 sheet 原逻辑未动。训练选择列表的数据来源、三个开始入口和左划阈值代码逐段相等。

选择页原有“返回首页”按钮、中文左划提示以及 `dx <= -100 / dy <= 32 / -dx >= dy * 3` 的左划判定保留；只在无 active 且仍处于选择页时有效。识别动作仍是向左划，退出视觉统一由原生模态向下关闭。

## Reduce Motion 与安全区

- Root 读取 `accessibilityReduceMotion`。开启时 pager 使用 `animated: false`，选择完成后的短淡入也改为立即切换；训练模态 binding 的单次 Transaction 设置 `disablesAnimations`。没有在全局 `.transaction` 或 `.animation` 中关闭其他页面已有的系统转场。
- 正常情况下使用系统全屏模态的进入/退出动画。关闭回调集中到 Root，避免实际训练页直接调用 dismiss 绕过 Reduce Motion 的事务。
- 四项原生 Tab 的尺寸、窗口安全区与 12 点内容间距沿用上轮。原先 single hosting 的附加安全区现在由 pager 持有并传给当前子页；减去旧附加值再计算新值的公式保留，避免重复累加。各页面仍消费宿主给出的 viewport，不自行减 Tab 高度。
- 安全区的所有者由单个 UIHostingController 调整为 UIPageViewController，必须在 iPhone 横竖屏和键盘收起后检查底部内容未受遮挡；公式相同不等于运行时 viewport 已验证。

## before 与本轮精确增量

写入前快照：

`C:/Users/win11/AppData/Local/Temp/opengym-navigation-before-d226d2e5-0665-4143-9a24-89a043e125c1`

包含 `before/`、`before.json`、`scope-verification.json`，交付时补充 `after/`、`navigation-transitions.patch`、`navigation-transitions-delta.json`。before 与已发布 `3aed74779538ae6917769d368b3311ca30602b83` 对应文件一致（统一换行后）；本地 HEAD 仍为旧的 `ac83d8bb16eec39d1cf87bdad9519557e0997c7c`。下列增量相对本轮 before，不是相对旧 HEAD 的累计变化。

| 路径 | 本轮增量 |
| --- | --- |
| `frontend/ios/App/App/Native/RootView.swift` | +149 / -40：原生分页、宿主缓存、串行目标切换、交互门控、单层训练模态及减少动态效果 |
| `frontend/ios/App/App/Native/WorkoutView.swift` | +40 / -25：选择/继续同一模态、保留返回与左划、集中关闭回调 |
| `scripts/ios/check-native-home.py` | +12 / -4：更新导航/单模态连接，增加缓存、串行、交互和减少动态效果检查 |
| `docs/dev/ios-navigation-transitions-static-checks-2026-10-26.json` | 新增：Root/Workout 语法与连接检查报告 |
| `docs/dev/ios-navigation-workout-static-checks-2026-10-26.json` | 新增：原训练模块静态检查报告 |
| `docs/dev/IOS_NAVIGATION_TRANSITIONS_2026-10-26.md` | 新增：本文 |

TodayView、水体、Store 及其余受保护的 39 个 Native 文件 SHA-256 未变化。`scripts/ios/check-native-workout.py` 只读取执行，未修改。真实索引仍为原有五项 API 路径，未暂存本轮内容；历史报告未覆盖。

| 修改后源码 | SHA-256 |
| --- | --- |
| RootView.swift | `34c9df6197d108780ba1bce23860e54f04459d9fc051da2ea520c2d2c4be5897` |
| WorkoutView.swift | `fe8388478c6f519d907ecff7b5b61c840909663bb013d33bfdbbbc18304e0a3b` |
| check-native-home.py | `4fb21ba0e496e02d08e344aeaf2425963861652f13f8969e643200feedc324d6` |

## 执行过的验证

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONPATH = "$env:TEMP\opengym-swift-syntax-tools"
& 'C:\Users\win11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  scripts/ios/check-native-home.py `
  --swift-file frontend/ios/App/App/Native/RootView.swift `
  --swift-file frontend/ios/App/App/Native/WorkoutView.swift `
  --report docs/dev/ios-navigation-transitions-static-checks-2026-10-26.json

& 'C:\Users\win11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  scripts/ios/check-native-workout.py `
  --output docs/dev/ios-navigation-workout-static-checks-2026-10-26.json

git diff --check -- frontend/ios/App/App/Native/RootView.swift frontend/ios/App/App/Native/WorkoutView.swift scripts/ios/check-native-home.py
```

结果：导航 **42/42** 项静态检查通过、Root/Workout 语法无 ERROR/missing 节点；训练模块 **15/15** 项静态检查通过，解析 15 个相关 Swift 文件。Python 脚本语法、空白检查、before/发布基线比对、范围和索引检查通过。训练报告列出的 11 个既有 Swift 测试只是定义计数，**没有执行 XCTest**。

Windows 无 Xcode；未做 Swift 类型检查、iOS 编译、动画帧率/流畅度、模拟器或真机手势测试。现有生成依赖前置条件仍包括 `public`、`config.xml`、`capacitor.config.json` 和 Pods。

交付后重点复核：四个 Tab 双向/跨项切换，快速连点和原生 Tab 拖动的最终目标，表单/滚动/导航栈复入，转场中的旋转与前后台切换，正常与 Reduce Motion 两种设置，以及无 active 开始、有 active 继续、选择页左划、进行中收起、保存失败和结束/放弃确认。任何白屏、双层呈现、状态丢失或安全区遮挡均保持未通过，不能用上述静态结果替代。
