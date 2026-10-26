# 首页训练卡片与四项原生导航 · 2026-10-26

本轮按用户新决定替代 R3 独立训练按钮的对齐方案：底部仅保留今天、计划、身体、喝水四个原生 Tab；训练入口并入首页“今日训练”；“今日服用”移除整块背景。已修改源码，没有继续追旧对齐问题。

未执行 git add、commit、push、pull、reset、stash、clean 或切换分支，由总控统一交付。没有修改水体算法、其他页面或训练/服用数据模型。

## 本轮变化

### 原生底栏

- 删除独立 UIButton、训练按钮回调、workoutRequest、左侧占位、600 点宽度上限。
- 使用普通 `UITabBar(frame:)`，横向范围为 `system.left` 到 `view.bounds.width - system.right`；四个 item 保持 `.fill`，内部边距和胶囊绘制由 UIKit 负责。这里的整行宽度指导航可用区域，不拉伸或重画内部玻璃表面。
- 删除 `LayoutReportingTabBar`、材质/控件扫描、可见中心测量、异步对齐回调和 `[RootDockLayout]` DEBUG 诊断。R3 的测量脚本/报告作为历史证据保留，不被 App 调用。
- 保留 R2 的 UIKit 宿主、安全区计算与页面栈。底部预留只由原生 Tab 外框占用加原有 12 点内容间距计算；没有左侧独立按钮参与。键盘显隐和 Tab 选择回调继续使用原流程。

Apple 公开支持单独使用 [UITabBar](https://developer.apple.com/documentation/uikit/uitabbar)，[ItemPositioning.fill](https://developer.apple.com/documentation/uikit/uitabbar/itempositioning-swift.enum) 负责分布项目。保留现有宿主可继续向各页面提供 R2 已采用的安全区协议；不依赖原生内部视图结构。

### 今日训练卡片

整块卡片改为 SwiftUI Button，显示操作文案和右箭头，保留 44 点以上点击高度、圆角命中区域、按下反馈和无障碍 label/value/hint。未练过采用靛蓝实色高亮；已经练过保留现有灰色 `.regularMaterial` 卡片。没有给普通功能按钮增加 Liquid Glass。

点击仅执行 `store.tab = .workout`，进入现有 `WorkoutView`，不调用 `startToday` / `openToday` / `startFreestyle`，也不写入 active。WorkoutView 原有逻辑在存在 active 时展示 ActiveWorkoutView；否则保留计划选择和自由训练入口。

以下是已核对的源码路径，**不是已运行的真机状态测试**：

| 当天已完成训练 | 有未完成训练 | 卡片外观 / 操作 | 点击后的既有流程 |
| --- | --- | --- | --- |
| 否 | 否 | 靛蓝高亮 / 开始训练 | 打开训练选择；有计划可选计划，无计划仍可选自由训练 |
| 是 | 否 | 原有灰色 / 再次训练 | 打开训练选择，允许再开一次 |
| 否 | 是 | 靛蓝高亮 / 继续训练 | 恢复当前 active，不新建记录 |
| 是 | 是 | 原有灰色 / 继续训练 | 优先恢复 active，不用“再次训练”替换当前记录 |

`didTrainToday`、active、今日标题和组数继续来自真实 GymStore。进入训练页前卡片只在今天页可点，切换到 `.workout` 时条件插入 WorkoutView；不再需要通过重复点击全局按钮的 request ID 强制重建它。训练结束/放弃后的回首页逻辑未改。

### 今日服用

- 去掉整块服用 VStack 的 `.regularMaterial` 背景，保留原有 B/D 两行、分隔线、间距与 padding。今日训练卡片的灰色背景没有误删。
- 标题、补充剂名称和服用说明使用语义 primary 文字色，并增加只围绕字形的小阴影：浅色外观为浅色光晕，深色外观为黑色阴影；增强对比度时提高阴影强度。没有用大块不透明底板遮住水。
- 原来较淡的服用说明改用 primary 色；增强对比度时药片/进度符号和次按钮标签也使用 primary。完成状态仍通过文字、勾选形状表达，不只依靠颜色。
- B/D 标题、真实次数与时间、记录/查看记录和 D 周期设置回调保持不变。功能按钮继续使用现有非玻璃的小面积填色样式，最小高度 44 点。字体沿用动态字号，未增加裁剪或强制单行。

文字与移动水体的实际对比度、深色模式和 VoiceOver 朗读尚需设备复核，不能因加入阴影就写成可访问性验收通过。

## 写入前快照与精确增量

快照目录：

`C:/Users/win11/AppData/Local/Temp/opengym-training-card-before-335266fa-d547-42fb-b7a6-22f54b4c1bc6`

包含 `before/`、`before.json`、`scope-verification.json`，交付时补充 `after/`、`training-card.patch` 和 `training-card-delta.json`。三个 before 文件与已发布 `3ebc3bb6d611e2a7659c78ef3c7cd021d980e271` 对应文件一致（统一换行后）。本地 HEAD 仍为旧的 `ac83d8bb16eec39d1cf87bdad9519557e0997c7c`；以下增量相对本轮 before，不能用相对旧 HEAD 的全量 diff 代替。

| 仓库路径 | 本轮增量 |
| --- | --- |
| `frontend/ios/App/App/Native/RootView.swift` | +18 / -207：移除独立动作及全部对齐实现，四项 Tab 使用整行可用宽度 |
| `frontend/ios/App/App/Native/TodayView.swift` | +81 / -24：可点击训练卡片、状态外观与操作提示、服用区去底板和文字可读性 |
| `scripts/ios/check-native-home.py` | +16 / -9：替换旧对齐检查，增加卡片路由、状态、服用区与可访问性源码连接检查 |
| `docs/dev/ios-home-training-card-static-checks-2026-10-26.json` | 新增：本轮静态验证和证据文件 SHA-256 |
| `docs/dev/IOS_HOME_TRAINING_CARD_2026-10-26.md` | 新增：本文 |

| 修改后源码 | SHA-256 |
| --- | --- |
| RootView.swift | `7bce458ba443a0578ad3a4a14ffa0f0b266a101e81d0b1563595ff7782c0f3a8` |
| TodayView.swift | `c36ff4c7d398af513b89bedca16a6a6783dbea370a887ddad1f7f38a4c8de1b2` |
| check-native-home.py | `ee984beb8a7d0aa73525933d9a9f0f2c85873376e9f9501a3e7596877c5b9d37` |

已对比 before：其余 39 个 Native 文件 SHA-256 未变化；Root 的安全区 helper 与选中回调尾部未变化；Today 的饮水交互、补充剂记录/设置/文案函数、称重 sheet 均逐段相等。共享真实索引仍为原有五项 API 文件，本轮没有暂存任何文件。

## 验证命令与结果

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONPATH = "$env:TEMP\opengym-swift-syntax-tools"
& 'C:\Users\win11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  scripts/ios/check-native-home.py `
  --swift-file frontend/ios/App/App/Native/RootView.swift `
  --swift-file frontend/ios/App/App/Native/TodayView.swift `
  --report docs/dev/ios-home-training-card-static-checks-2026-10-26.json

git diff --check -- frontend/ios/App/App/Native/RootView.swift frontend/ios/App/App/Native/TodayView.swift scripts/ios/check-native-home.py
```

- Root/Today 的 tree-sitter Swift 语法解析无 ERROR/missing 节点；最终 **34/34 项静态项目/源码连接检查通过**。赋值检查已区分 `=` 与 `==`，不会把卡片的 active 判空识别为创建/替换记录。
- Python 检查脚本语法、所改源码空白检查、before 与发布基线比对、范围/索引保护检查通过。
- 新报告包含本轮 Root/Today、现有 WorkoutView/GymStore 及项目依赖的 SHA-256；旧 R1/R2/R3 报告未覆盖。
- 当前 Windows 没有 Xcode。没有 Swift 类型检查、iOS 编译、运行测试、修复后截图或真机点击验证。静态工具列出的现有 `public`、`config.xml`、`capacitor.config.json`、`Pods` 生成/依赖前置条件未在本轮处理。

设备验收应检查四个 Tab 的整体宽度与系统边距、键盘收起和横竖屏安全区、上述四种训练卡片状态/无计划流程，以及服用区在低/高水位、浅/深色、增强对比度、大字号和 VoiceOver 下的阅读与操作。水体运动算法及其他页沿用原实现，本轮不声称重新通过这些运行验证。
