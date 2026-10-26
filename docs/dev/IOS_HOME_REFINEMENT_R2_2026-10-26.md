# 首页、全局底栏与开始入口 R2 · 2026-10-26

本轮是针对真机退回截图的实际源码整改。R1 的静态通过不代表视觉通过；R2 尚无修复后的 Xcode/真机结果。未执行 add、commit、push、pull、reset、stash、clean 或切分支，交由总控统一提交。

## 已查看的真机证据

使用图像工具实际打开了以下两张原图，未生成替代截图：

- `C:/Users/win11/AppData/Local/Temp/codex-clipboard-b5e887a0-f357-43dd-9dbd-abb327413793.png`：首页 Tab 胶囊与左侧开始按钮视觉中心不同，功能按钮仍呈玻璃外观，开始仅显示普通黑加号。
- `C:/Users/win11/AppData/Local/Temp/codex-clipboard-33c86054-b115-40f6-9475-f141285f7471.png`：喝水页的记录与自定义操作被全局 Tab 实际覆盖。

旧源码将独立 UITabBar 的 `sizeThatFits` 整体高度（包含系统自己的安全区/内部布局）直接作为 SwiftUI HStack 的居中外框，并额外用 `max(60, ...)` 限制高度。这不能保证系统实际条目区域与旁边按钮同心。截图证明了偏移和遮挡，但没有提供 UIKit 运行时 frame，因此本轮不虚构一个已经量到的内部偏移值，也未使用负 padding/负 offset 将胶囊强行挪动。

## 本轮 before 与精确增量

写入前保存目录：

`C:/Users/win11/AppData/Local/Temp/opengym-home-r2-before-00787719f79e4605a6b5cdd87cf6fa1b`

其中包含原路径 before 文件、`manifest.json`、`after/` 文件、`home-r2.patch` 和 `r2-delta.json`。本地 HEAD 仍为 `ac83d8bb16eec39d1cf87bdad9519557e0997c7c`；三个 before 文件经读取 Git 对象，均与总控提供的已发布 R1 提交 `c2ca4a1b` 对应文件一致。以下增量相对本轮 before，**不是相对旧本地 HEAD 的全部 diff**。

| 仓库路径 | 本轮增量 |
| --- | --- |
| `frontend/ios/App/App/Native/RootView.swift` | +250 / -98：统一 UIKit 底栏宿主、实际条目区域测量、真实安全区预留、实色开始入口 |
| `frontend/ios/App/App/Native/TodayView.swift` | +52 / -31：前景独立 viewport、功能按钮实色/轻量样式、设置按钮去工具栏玻璃背景 |
| `scripts/ios/check-native-home.py` | +10 / -5：更新宿主/对齐/安全区/功能按钮检查 |
| `docs/dev/ios-home-r2-static-checks-2026-10-26.json` | 新增本轮静态结果和依赖 SHA-256 |
| `docs/dev/IOS_HOME_REFINEMENT_R2_2026-10-26.md` | 新增本文 |

没有修改 WaterView、其他页面、Store/业务数据、Xcode 工程、Package.swift、R1 文档/报告或其他对话的文件。共享真实索引仍只有原有五项 API 文件，未暂存本轮文件。

## 底栏坐标与页面安全区协议

### 同一个 UIKit 宿主负责布局

`NativeRootHost` / `RootNavigationController` 承载一个页面 `UIHostingController`、一个真实 `UITabBar` 和一个独立 `UIButton`，三者处于同一 UIKit 坐标系。

1. 宿主延伸到容器边缘，通过窗口的 `safeAreaLayoutGuide` 转换到本地坐标取得系统安全区；横竖屏/窗口尺寸变化会重新布局，不假定固定 34 点 Home indicator。
2. UITabBar 锚定宿主实际底边，在已经加入窗口并定位后读取 `sizeThatFits`，再布局、复测。去掉 SwiftUI `max(60, fitted.height)` 与外部 HStack 整框居中；系统 Tab 本身决定自身高度、背景与内部间距。
3. 布局后读取系统实际条目/控件的 UIView frame：优先识别本代码赋给四个 tab item 的 accessibilityIdentifier，否则仅在恰好找到四个原生 UIControl 时使用它们的区域。读取公开 UIView 属性，不使用私有类名、KVC、替换内部视图或自定义手势。
4. 独立开始按钮的中心使用上述条目区域的 `midY`；不再与包含底部安全区的 UITabBar 外框中心对齐。若当前系统结构无法识别四个条目，使用公开 `safeAreaLayoutGuide` 回退，并在调试日志明确标注，不能把这个回退当作视觉验收通过。
5. 底部占用取 Tab 外框、实际条目区域、开始按钮三者最靠上的边缘，另留 12 点内容间距。这 12 点是页面与导航的留白，不是移动 Tab 的补偿。页面 `UIHostingController.additionalSafeAreaInsets` 接收该占用；计算先减去之前附加的 inset，避免反复布局把 Home indicator 或已有预留重复累加。
6. 键盘出现时隐藏底栏，并恢复仅系统安全区。访问过的页面栈、真实选择回调、开始/继续训练、scenePhase 转发与原有同步生命周期继续保留。

### 与喝水页 R2 的衔接

已只读检查 WaterView R2：该页现在以前景 GeometryReader 的宽高作为 viewport，把 WaterBackground 放入 background；没有再补一个固定 Tab 高度，也不自行增加底部 safeAreaInset。**Root 是底栏占用的唯一所有者，各页面消费 UIKit 宿主提供的可用区域。**

Today 同样改为前景 GeometryReader 决定尺寸，水体只作为 background。前景宽高仅扣既有水平 16 / 垂直 8 点页边距，不使用 ignoresSafeArea 绕过宿主，不额外重复扣 Tab 高度。普通/紧凑布局和完整内容保留。

## 按钮整改

- 开始按钮：52 点圆形 `UIButton.Configuration.filled()`，靛蓝实色、白色训练语义图标；已有训练显示播放图标。仍是独立动作，不成为第五个 tab，不恢复大绿球。
- 首页确定：实色 accentColor 主按钮，白色标签；服用记录、服用设置：轻量色块次按钮。私有 `HomeFunctionButtonStyle` 只使用 Color 与形状，没有 material/shader/glass 效果，保留按下和禁用状态、至少 44 点高度。
- 顶部设置：plain 功能按钮，并通过 `sharedBackgroundVisibility(.hidden)` 去掉该 toolbar item 自带的玻璃背景。没有改整个导航栏或系统 Tab 的材质。
- Root / Today 的显式 `glass`、`glassProminent`、`glassEffect` 调用为零。内容卡片原有 standard regularMaterial 并非 Liquid Glass；未给卡片增加玻璃效果。
- 滚轮仍只改变 pendingWaterML，确定回调仍是首页唯一 addWater 调用；服用记录、设置、同步详情等业务动作未换成演示行为。

依据：[Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)、[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)。按钮去玻璃是本轮用户要求，不将其表述成 Apple 禁止所有玻璃按钮。宿主预留使用公开 [additionalSafeAreaInsets](https://developer.apple.com/documentation/uikit/uiviewcontroller/additionalsafeareainsets)，工具栏功能背景使用 [sharedBackgroundVisibility](https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:))。

## 验证与诊断

已执行：

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONPATH = "$env:TEMP\opengym-swift-syntax-tools"
& 'C:\Users\win11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  scripts/ios/check-native-home.py `
  --swift-file frontend/ios/App/App/Native/RootView.swift `
  --swift-file frontend/ios/App/App/Native/TodayView.swift `
  --report docs/dev/ios-home-r2-static-checks-2026-10-26.json

git diff --check -- frontend/ios/App/App/Native/RootView.swift frontend/ios/App/App/Native/TodayView.swift scripts/ios/check-native-home.py
```

结果：两个 Swift 文件语法解析无 ERROR/missing 节点，29/29 项静态项目/源码连接检查通过，空白检查通过。保存了本轮 before/after SHA-256 与独立增量；没有以旧报告或旧本地 HEAD 证明本轮完成。

Debug 构建增加 `[RootDockLayout]` 日志，仅在几何结果改变时输出：宿主 bounds、窗口系统安全区、Tab frame/拟合高度、实际条目区域、测量来源、开始按钮 frame、页面预留量、hosting additional/实际 safe area。它不显示在产品 UI，也不包含用户健康数据。

| 修改后源码 | SHA-256 |
| --- | --- |
| RootView.swift | `d2aaa0b0cde5ac1ef8c1a41ec3f1ef98064b66ac4183a23bae3e6483a2054ee3` |
| TodayView.swift | `c41e73c41e3b496ed692b2c54255104a34550e7794e20fec8eb73897dfa626d7` |
| check-native-home.py | `386794a31547531d29abfe759bd3d2e3e622b524cce5df2439a3bb9a8a8a0d65` |

## 未验证与总控验收项

本机没有 Xcode / Swift 编译环境，**未执行 Swift 类型检查、Xcode 构建、修复后 iOS 截图、原生拖动或真机交互验证**。没有已采集的 R2 `[RootDockLayout]` 设备日志；29 项静态通过不能代替这些项目。

总控合并后须在 iOS 26 运行：

1. 复现两张截图状态，确认 Tab 胶囊与开始按钮视觉中心一致、位于正确底部位置；读取 `[RootDockLayout]` 核对实际 frame 与页面安全区。若来源为 `safe-area-guide-fallback`，重点检查该系统上的控件结构和对齐，不能直接验收。
2. 喝水记录/自定义、首页最后一张服用卡片完整位于导航上方，系统 Home indicator 不重复预留；横竖屏、小屏、大字体、切页、键盘出现/收回后保持成立。
3. 原生选中胶囊及左右拖动仍由 UITabBar 自己处理，落点与页面一致；已有页面栈、滚动和选择状态保留。
4. 新训练、继续训练、关闭训练后再次继续，以及 sheet/fullScreenCover/错误提示正常；水体在新的 hosting 环境中仍按真实 scenePhase 和当前页面运行。
5. 主按钮清晰实色、次按钮轻量，亮/暗色下可读；首页滚轮不落库、确定才记录，服用/设置入口仍真实可用。

本轮源码整改已交接，视觉/运行验收保持未通过，等待上述新证据。
