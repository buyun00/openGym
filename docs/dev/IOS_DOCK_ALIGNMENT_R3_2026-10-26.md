# 底栏可见中心对齐 R3 · 2026-10-26

本轮只修左侧靛蓝开始按钮与原生 Tab 可见胶囊的垂直中心偏差及布局刷新。已实际修改源码；水体算法、其他页面、开始按钮的实色外观、R2 页面安全区协议均未改动。未执行 add、commit、push、pull、reset、stash、clean 或切换分支，由总控统一提交。

R2 的真机退回成立。R3 当前只有源码和静态验证结果，没有修改后的 Xcode 编译、模拟器或真机视觉证据，不能写成底栏视觉验收通过。

## 原图测量

已实际打开原图 `C:/Users/win11/AppData/Local/Temp/codex-clipboard-30160dcb-3775-46cd-b844-ee5f6389bf65.png`，并对磁盘原始像素做只读分析，没有使用聊天缩略图或生成替代截图。

- 原始分辨率：1260 × 2736。
- SHA-256：`4ba8c098bf15195548f0caa3decd44ee4d4674572ae9480cfd277edc5263c474`。
- 坐标：左上为原点，像素中心使用整数；相邻采样的边缘过渡使用半像素坐标。可见胶囊边界取外描边到内侧材质的强过渡，不包括外部阴影。

| 对象 | 原图边界 / 中心（px） |
| --- | --- |
| 靛蓝圆形按钮填色像素包围盒，含端点 | x=48…203，y=2482…2637 |
| 按钮轮廓拟合圆心 | x=125.500，y=2559.966 |
| Tab 可见材质边界 | left=290.5，top=2486.5，right=1172.5，bottom=2672.5 |
| Tab 可见材质中心 | x=731.5，y=2579.5 |
| Tab 中心减按钮中心 | **+19.534 px：按钮偏高** |

按钮以底部左侧靛蓝色阈值提取外轮廓，按每行/列最外侧采样拟合圆；白色训练图标不参与质心估算。改变蓝绿通道差阈值为 60、70、90、110，得到的中心差范围为 19.500…19.535 px。三组横向采样带 `[504,1008)`、`[604,907)`、`[403,1108)` 均得到相同上下边界及中心；边缘定义保留约 ±1 px 容差。因此可以确认约 19.5 px 偏差，不能从这张图单独确认 UIKit 内部采用了哪个 frame 或 R2 哪条回退分支。

没有假定图片的 point/pixel scale，也没有把 19.5 px、其换算值或任何固定负 offset 写进 App。测量脚本的颜色及区域假设只服务于这张证据图。

可复现结果见 [测量 JSON](dock-alignment-r3-measurements-2026-10-26.json)，脚本为 `scripts/ios/measure-dock-alignment.py`。

## R2 的问题与证据边界

R2 的 `tabItemRegion()` 优先组合带四个 item accessibilityIdentifier 的视图；无法识别时组合四个 UIControl；再失败则使用 `tabBar.safeAreaLayoutGuide.layoutFrame`。三者都不能代表可见胶囊背景的边界。按钮使用该区域的 `midY`，只在父控制器布局时更新；没有响应 Tab 自身后续的内部布局完成。

截图直接证明中心不同；源码直接证明上述定位依据和刷新范围。由于没有该次真机的 `[RootDockLayout]` 日志，不能声称已经证实是 identifier、UIControl、safe-area 回退或延迟布局中的某一个独立分支造成全部偏移。R3 移除了这三种区域作为最终对齐锚点，并覆盖原生 Tab 的后续布局。

## R3 实现

1. 保留一个真实 UITabBar 和独立 52 点 UIButton。`LayoutReportingTabBar` 只覆盖 `layoutSubviews()`，先调用 `super` 再通知宿主；不接管系统 Tab 绘制、选中样式、命中测试或手势。
2. 对齐改为读取可见的 `UIVisualEffectView`：优先 `UIGlassEffect`，其次 `UIBlurEffect`；兼容候选为有实际不透明背景色和圆角的宽背景视图。候选必须覆盖至少 70% 的 Tab 宽度，且具有横向背景形状，排除单个选中项的胶囊。容器 effect 和 vibrancy 不作为绘制表面。
3. 通过公开 `UIView.convert` 统一到宿主坐标，考虑材质自身 mask 和祖先裁剪，使用表面矩形的 `midY` 设置开始按钮。只读取原生视图，不修改其内部 frame、effect 或层级。没有私有类名、KVC、选择器调用或截图像素补偿。
4. 原生 Tab 完成布局后，合并为一次主队列异步复测；视图出现和尺寸转换结束时也复测。复测只调整独立按钮及其内容占用，不主动再次触发 Tab/root 布局，没有计时器或每帧轮询。
5. 安全区 guide 只在材质尚未可识别时提供初始位置。无法识别材质时，日志明确为 `source=unresolved-bootstrap-not-validated`、`visualCenterError=unresolved`；不再悄悄拿 UIControl 区域充当可见背景。R2 的条目区域只保留在 DEBUG 日志中作对照。
6. `windowSafeInsets()` / `reserveContent()` 保持 R2 实现：由 Root 唯一负责底栏占用，先扣除已有附加 inset，避免重复计算。Tab 原有底边放置、原生拟合高度、键盘显隐、页面栈、选择和开始/继续动作保持不变。

公开 API 依据：[UIGlassEffect](https://developer.apple.com/documentation/uikit/uiglasseffect)、[UIVisualEffectView](https://developer.apple.com/documentation/uikit/uivisualeffectview)、[UIGlassContainerEffect](https://developer.apple.com/documentation/uikit/uiglasscontainereffect)、[UIView.layoutSubviews](https://developer.apple.com/documentation/uikit/uiview/layoutsubviews())。Apple 文档区分渲染玻璃的 effect 与组合玻璃的 container，并提供视图布局回调；**它没有保证 UITabBar 的内部视图层级，也没有公开可见胶囊的专用 layout guide**。本轮识别依赖实际层级中存在上述公开类型/几何，不能把公开 API 文档当作已在用户系统上命中该路径的证明。

## 本轮 before 与精确增量

写入前快照：

`C:/Users/win11/AppData/Local/Temp/opengym-dock-r3-15c2cd1a66f24e6287bf0ae0f6a8ca8e`

目录包含 `before/` 两个源文件和 `before.json`，交付时补充 `after/`、`dock-r3.patch`、`r3-delta.json`。本地 HEAD 仍为 `ac83d8bb16eec39d1cf87bdad9519557e0997c7c`。通过只读 Git 对象比较，两个 before 文件均与已发布 R2 `40eb991bf131a8ad106418b6a36c837f5a4a3774` 相同（统一换行后）。下表是相对本轮 before 的增量，不是相对旧 HEAD 的累计改动。

| 仓库路径 | R3 增量 |
| --- | --- |
| `frontend/ios/App/App/Native/RootView.swift` | +129 / -20：材质区域定位、原生布局完成复测、诊断 |
| `scripts/ios/check-native-home.py` | +5 / -3：更新材质定位、布局刷新与公开 API 源码检查 |
| `scripts/ios/measure-dock-alignment.py` | 新增：原图只读像素测量 |
| `docs/dev/dock-alignment-r3-measurements-2026-10-26.json` | 新增：原始图测量、阈值交叉检查及局限 |
| `docs/dev/ios-dock-r3-static-checks-2026-10-26.json` | 新增：R3 静态结果及依赖 SHA-256 |
| `docs/dev/IOS_DOCK_ALIGNMENT_R3_2026-10-26.md` | 新增：本文 |

Root 页面映射及生命周期部分、`update` 的按钮配置/选择动作、`windowSafeInsets` 和 `reserveContent` 已与 before 做文本相等校验。没有修改 TodayView、WaterView、WaterPhysics、WaterMotion、WaterScene、Xcode 工程或其他页面。没有覆盖 R1/R2 文档与报告。

| 修改后源文件 | SHA-256 |
| --- | --- |
| RootView.swift | `2645e0cd9e8eeb6c6e41abe3bcbc8fae83677d96c38d11a2325f74901fac465e` |
| check-native-home.py | `fb47b4d40d4e588600dd076c8dc34d0c7e3152f4b2aea52002f2c6bc2cbb6c80` |

## 已执行验证

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONPATH = "$env:TEMP\opengym-water-render-tools"
& 'C:\Users\win11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  scripts/ios/measure-dock-alignment.py `
  'C:\Users\win11\AppData\Local\Temp\codex-clipboard-30160dcb-3775-46cd-b844-ee5f6389bf65.png' `
  --report docs/dev/dock-alignment-r3-measurements-2026-10-26.json

$env:PYTHONPATH = "$env:TEMP\opengym-swift-syntax-tools"
& 'C:\Users\win11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  scripts/ios/check-native-home.py `
  --swift-file frontend/ios/App/App/Native/RootView.swift `
  --report docs/dev/ios-dock-r3-static-checks-2026-10-26.json

git diff --check -- frontend/ios/App/App/Native/RootView.swift scripts/ios/check-native-home.py
```

结果：原图测量完成；Root Swift tree-sitter 语法解析无 ERROR/missing 节点；31/31 项项目/源码连接检查通过；所改已跟踪文件空白检查通过。这些检查包括保留的水体连接检查，但本轮未修改或重新运行水体模拟，不借用它们宣称水体真机通过。共享真实索引仍只有原来的五个 API 路径，本轮未暂存任何文件。

当前 Windows 无 `swift` / `xcodebuild`。静态工具报告的 `public`、`config.xml`、`capacitor.config.json`、`Pods` 缺失是现有生成/依赖前置条件，未在本轮改写。没有 Swift 类型检查、iOS 编译、原生触摸测试或修改后截图。

## 真机复核要求

Debug `[RootDockLayout]` 在几何变化时记录 `pass`、Tab frame、`surface/source`、R2 `hitRegion`、start frame、`visualCenterError`、候选数和 hosting 安全区，不含健康记录内容。`visualCenterError=0` 仅说明所选矩形与按钮的数学中心一致，**仍必须确认所选 surface 对应屏幕上完整可见胶囊**。

- 在同一设备、原始分辨率下取得 R3 截图和日志；检查 `source` 命中完整背景，按钮/胶囊中心在可见边缘的约 1 px 测量容差内。若是 unresolved 或误选背景，保持未通过，继续定位。
- 复核首次进入、Tab 切换、键盘收起、返回前台及旋转/窗口尺寸变化后的稳定状态；不能只以第一次布局相等作为全部状态通过。
- 确认今天/计划/身体/喝水仍是四个原生 Tab，系统选择交互保持正常，独立开始/继续训练可点，按钮仍为既有靛蓝圆形。
- 复核喝水页底部记录/自定义操作不被遮挡，页面没有因复测重复增加安全区；其他页面和水体行为沿用 R2。
