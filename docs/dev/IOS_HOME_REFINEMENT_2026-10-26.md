# iOS 首页与全局底栏调整 · 2026-10-26

本批按总控分工修改首页、全局导航和独立开始入口。工作在共享 checkout 中完成，未执行暂存、提交、推送、拉取、重置、stash、clean 或切换分支；提交交由总控统一处理。

## 改动路径与行为

| 路径 | 改动 |
| --- | --- |
| `frontend/ios/App/App/Native/TodayView.swift` | 首页移除外层 ScrollView，使用行内标题；按实际可用高度在完整的普通/紧凑布局间选择，横向宽屏使用双列。保留今日训练、今日饮水总量和完整的维生素 B/D 服用卡片。 |
| 同上 | 删除整条同步文案卡片；在“今天”右侧显示状态符号。符号分别读取真实 busy、errorMessage、lastSync、status、connected 状态，点按仍进入 GymConnectionView，VoiceOver 可读完整状态。未修改同步实现。 |
| 同上 | 删除首页目标设置按钮、目标进度/未设置说明和“已记录 xx mL”提示。总量右侧为原生 wheel Picker，下方“确定”。滚轮只修改 pendingWaterML；唯一的 addWater 调用位于确认回调，成功后更新总量并给成功触感，失败继续使用原有错误提示。 |
| 同上 | 快捷水量为 50–2000 mL、步进 50 mL，并保留设置中的现有杯量（即使不是 50 的倍数）；进入首页初始化一次，更改杯量设置会同步更新待添加值。独立喝水页和历史编辑入口未改。 |
| `frontend/ios/App/App/Native/RootView.swift` | 删除 HomeDock 自绘导航和隐藏系统 TabView 的实现，改为真正的独立 UITabBar，四个 UITabBarItem 分别为今天、计划、身体、喝水。通过 UITabBarDelegate 将系统选中结果映射回 store.tab。 |
| 同上 | 保留系统背景、选中指示器、触摸处理和辅助功能，不绘制选中胶囊、不增加拖动识别器、不改 UITabBarAppearance；只在外部导航发生变化时更新 selectedItem，避免重建 items 打断系统交互。 |
| 同上 | 左侧开始入口改用 `.buttonStyle(.glass)` / `.buttonBorderShape(.circle)`，去掉绿色大面积填充。新训练显示加号，已有训练显示播放符号；均进入现有 WorkoutView 流程，不添加第五个 tab item。重复点按继续入口也能重新打开现有训练。 |
| 同上 | 底部控制区通过 safeAreaInset 为页面保留高度，系统 tab 的高度读取 sizeThatFits，键盘出现时隐藏底部控制区。访问过的各页 NavigationStack 保持挂载和状态，未访问页延迟创建；非当前页禁止触摸并从辅助功能树移除。 |
| `scripts/ios/check-native-home.py` | 将旧自绘底栏检查替换为系统 UITabBar、四个导航项、独立动作、确认后写水量及首页源代码约束；新增 `--report` 参数，避免覆盖历史报告。 |
| `docs/dev/ios-home-static-checks-2026-10-26.json` | 本批静态检查结果与依赖文件 SHA-256。校验针对当前共享工作区，不代表总控之后合并/提交版本的运行结果。 |

普通和紧凑布局都保留全部三块主要内容，不对卡片设置固定高度、裁切、隐藏文字或整页缩放。唯一 `.clipped()` 用于水量滚轮自身的滚动视口；它有明确的宽高与 contentShape，避免滚轮命中区域覆盖旁边总量或下方确定按钮。长训练名称和服用说明允许换行。

## 系统公开 API 核实

- [Apple UITabBar 文档](https://developer.apple.com/documentation/uikit/uitabbar)明确支持将 UITabBar 作为独立控件使用，通过 setItems 配置条目，通过 UITabBarDelegate 接收选择。这允许左侧动作按钮和右侧真正的系统 tab 控件并列。
- [Apple Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)说明标准 SwiftUI/UIKit 控件自动采用新材质，并建议让系统决定导航背景；因此本实现保留原生 UITabBar 外观与交互，不在其上叠加自制玻璃或选中背景。
- [tabViewBottomAccessory](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:))在展开状态位于 tab bar 上方，折叠时才同行，不是本次所需的左侧动作布局接口。

系统 UITabBar 代码接入已完成；**选中胶囊的实际 Liquid Glass 外观、按住左右拖动的完整系统行为尚未在 iOS 26 上验证**。这里没有用点击切换或自绘拖动来冒充验证结果。

## 已执行验证

Windows PowerShell，使用本机已有 Python 和 Swift 语法解析依赖：

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONPATH = "$env:TEMP\opengym-swift-syntax-tools"
& 'C:\Users\win11\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' `
  scripts/ios/check-native-home.py `
  --swift-file frontend/ios/App/App/Native/RootView.swift `
  --swift-file frontend/ios/App/App/Native/TodayView.swift `
  --report docs/dev/ios-home-static-checks-2026-10-26.json

git diff --check -- frontend/ios/App/App/Native/RootView.swift frontend/ios/App/App/Native/TodayView.swift scripts/ios/check-native-home.py docs/dev/IOS_HOME_REFINEMENT_2026-10-26.md
```

结果：两个改动 Swift 文件的语法树解析无 ERROR/missing 节点，24 项静态项目/源码连接检查通过，`git diff --check` 通过。该解析器不做 Swift 类型检查。未改动 Xcode 工程、Package.swift、同步后端及凭据相关文件，未改独立喝水页、训练详情页、身体页或计划页。

## 尚未完成的验证与总控接手项

本机 Windows 无可用 Xcode / Swift 编译命令；未执行 Xcode 构建、Swift 测试、模拟器或真机验证。项目当前还缺少静态报告列出的生成依赖（Pods / public / Capacitor 配置），由 Mac 端按现有构建流程准备。

需在 iOS 26 的实际 App 中检查以下场景，当前均不标为通过：

1. 常见竖屏尺寸 375×667、375×812、390×844、393×852、430×932：不滚动首页即可看全今日训练、饮水总量/滚轮/确定、B/D 卡片；最后一行和按钮不落入底栏或 Home indicator。并检查横屏、长训练名、五位饮水总量及大字体；极端辅助功能字号是否仍可完整排下不能由本次静态检查保证。
2. 四项导航的系统选中胶囊与左右拖动选择；拖动结束后的页面和选中项一致；从计划等页面程序化进入训练后能回到各页，已有导航层级仍保留。
3. 新建训练、已有训练继续、关闭训练全屏后再次点左侧入口，以及训练完成/取消后的正确返回。动作入口不能出现为第五个 tab。
4. 上下滚动水量选择器不会改变今日总量、不会写入饮水记录；点一次确定才写入一笔对应水量。检查滚轮仍在减速时点确定、连续添加、跨日和写入失败提示。
5. B/D 记录、已服用记录查看与 D 计划设置入口完整可点；错误、待同步、同步中、同步成功状态符号及连接详情入口；亮/暗色、VoiceOver 与降低透明度。

请总控只收取上述改动路径，并保留其他制作对话的 staged/unstaged 工作。最终提交若改变依赖源码或本批文件，应重新生成当前报告并复核原生行为，不能沿用本报告宣称真机验收通过。
