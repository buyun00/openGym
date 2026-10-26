# iOS 训练页 R2：普通功能按钮去玻璃（2026-10-26）

本轮已修改源码并通过静态检查，**没有取得修改后的 iPhone 截图、Xcode 编译或交互验证，不能视为视觉通过**。没有操作真实训练的完成、结束、保存或放弃。未暂存、提交、推送、拉取、重置、stash、clean 或切换分支，交由总控统一交付。

## 本轮基线与截图

写入前保存了所有 `Workout*.swift` 和训练静态检查脚本的原始字节、SHA-256 与当时本地 HEAD：

`C:/Users/win11/AppData/Local/Temp/opengym-workout-r2-before-6oua5j7c/`

其中 `manifest.json` 是 before 清单，`r2.patch` 是相对该快照的 5 个既有文件增量。**本轮以 before 快照对比，不把相对本地 HEAD 的全部 diff 当作 R2**；共享 checkout 中已经含有上一轮改动。R1 文档和检查报告均未覆盖。

实际重新查看了本任务收到的两张指定截图：

- `C:/Users/win11/AppData/Local/Temp/codex-clipboard-88479b96-9809-4c3a-a194-60c3ac847b7f.png`
- `C:/Users/win11/AppData/Local/Temp/codex-clipboard-c81f6c7e-67d9-4e72-be51-6a82ae9de15d.png`

截图仅作为用户反馈输入，不作为修改后效果证据。仓库和上级目录未找到适用的 AGENTS.md。

## 材质依据与范围

已读取 [Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Apple Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) 和 [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) 的官方正文。Apple 区分内容与导航/控制层，提醒节制自定义玻璃效果，并用按钮层级突出主要操作。

本轮按照用户更明确的偏好实施：普通功能按钮不显式使用玻璃；主要操作使用 `.borderedProminent` 实色样式，次要操作使用 `.bordered` 或 `.plain`。系统导航 toolbar、sheet、系统控件自身的默认材质不伪造、不叠加自制玻璃，也不通过全局 appearance 修改其他页面。不能仅凭源码断言每种系统版本的实际渲染已经验收。

## 精确写入范围与 R2 增量

以下路径均相对 `D:/其他项目/openGym`：

| 文件 | 仅本轮新增变化 |
| --- | --- |
| `frontend/ios/App/App/Native/WorkoutView.swift` | 导航栏“结束”移除显式 glassProminent、采用系统默认 toolbar 样式；添加动作用 borderedProminent；上一个/下一个、训练备注、页尾结束入口和休息操作改为 bordered |
| `frontend/ios/App/App/Native/WorkoutExerciseCard.swift` | 动作选项、加组、停止计时改为 bordered；开始计时改为 borderedProminent；历史入口改为 plain、主文字色和最小 44 pt 高点击区；缩略图放大角标改为系统纯色背景；动作备注改为系统实色内容背景 |
| `frontend/ios/App/App/Native/WorkoutSheets.swift` | 同一个结束容器内“结束并保存”从 glassProminent 改为 borderedProminent；其余结束布局、继续训练和放弃流程未改 |
| `frontend/ios/App/App/Native/WorkoutMediaView.swift` | 缩小、播放/暂停改为深灰实色底和白字的 borderedProminent 控件，使用 large 尺寸；去掉旧的 Liquid Glass 注释。播放器逻辑未改 |
| `scripts/ios/check-native-workout.py` | 旧的“必须包含玻璃 API”检查改为原生控件检查，并新增全部 Workout 源的显式玻璃调用扫描；视频检查字段更名为 `native_video_api_references`，避免把源码检查误写成播放通过 |
| `docs/dev/ios-workout-refinement-r2-static-checks-2026-10-26.json` | 新增本轮静态证据和文件哈希 |
| `docs/dev/IOS_WORKOUT_REFINEMENT_R2_2026-10-26.md` | 新增本交接 |

已审计其他训练文件：动作选项/历史、列表操作、设置、Picker、Toggle、警告框原本使用系统控件，没有显式玻璃样式，因此未改 `WorkoutExerciseOptions.swift`。本轮未写入 Store、模型、计时/媒体播放实现、共享 Xcode 工程、Package、首页、身体、喝水或全局 Tab。

保留 R1 成果：紧凑顶部与自适应动作选择、普通数值输入、44×44 完成按钮与中心对齐、一个容器的结束操作、关闭 sheet 后才出现的独立放弃 alert、session ID 保护，以及既有真实持久化路径。before/after 增量仅包含上述样式和检查器变化。

## 验证

工作目录 `D:/其他项目/openGym`：

```powershell
& 'C:\Users\win11\AppData\Local\Temp\opengym-workout-checks\Scripts\python.exe' `
  'scripts/ios/check-native-workout.py' `
  --output 'docs/dev/ios-workout-refinement-r2-static-checks-2026-10-26.json'

rg -n 'glass|GlassEffect' frontend/ios/App/App/Native -g 'Workout*.swift'

git --no-optional-locks diff --check -- `
  frontend/ios/App/App/Native/WorkoutView.swift `
  frontend/ios/App/App/Native/WorkoutExerciseCard.swift `
  frontend/ios/App/App/Native/WorkoutSheets.swift `
  frontend/ios/App/App/Native/WorkoutMediaView.swift `
  scripts/ios/check-native-workout.py `
  docs/dev/IOS_WORKOUT_REFINEMENT_R2_2026-10-26.md
```

结果：

- 15 个 Swift 源/测试/Package 文件语法树无错误或缺失节点；Xcode 源/资源引用、6554 个动作目录和媒体引用检查通过。
- 全部 `Workout*.swift` 的显式 `glass`、`glassProminent`、`glassEffect`、`GlassEffectContainer` 使用为 0；`rg` 无匹配（退出码 1 表示无匹配）。
- 限定路径的 diff 空白检查通过。出现 LF/CRLF 转换提示，仅是 Windows 换行提示。
- before 快照对比确认只改动了表中的 4 个 Swift 文件和 1 个检查脚本；另新增 R2 文档与报告。
- 11 项原有 XCTest 未执行；Windows 端未提供 Swift/Xcode。语法和 API 文本扫描不是类型检查、运行、可视材质检查或触摸验证。

## 未验证项 / 总控后续验收

1. 在统一交付版本进行 Swift 类型检查、XCTest、Xcode 26+ 构建；合并其他页面后重跑此静态检查，报告记录的是本轮检查时的共享文件哈希。
2. iPhone 明暗模式、大字号、小屏及横屏：所有普通按钮背景、主次层级、文字对比度、禁用态、按下态和点击范围；导航区域保持系统默认而无重复玻璃层。
3. 媒体的深灰按钮是否遮挡关键演示内容、按钮文字能否完整显示，以及播放/暂停/缩小仍正常。未运行 AVPlayer 实测。
4. 回归 R1 的顶部间距、动作选择、数值输入、完成按钮对齐；检查新按钮默认边距是否影响布局。
5. 在专门的测试会话中检查结束卡片、继续训练、关闭 sheet 后的放弃确认和取消；不要用用户真实训练执行破坏性验收。本轮没有以模拟截图或静态报告替代这一步。

没有要求其他页面配合的代码变更，也没有给其他对话发消息。R2 不包含 Git 远程交付结论。
