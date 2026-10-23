# iOS 开始锻炼与训练页

本轮完成了四张参考截图对应的原生源码实现。**尚未经过 Xcode 编译或 iPhone 运行，不能视作页面与功能已验收。** 当前 Windows 没有 Swift/Xcode，WSL 也未安装；未打包、签名或发布安装包。用户随后授权将本次源码提交并推送至远端。

## 对照范围

| 参考状态 | 实现 |
| --- | --- |
| IMG_1311，缩略图训练页 | 全屏训练、收起继续、名称/实时用时/组数、进度条、动作编号、缩略图、双语动作名称、分类/目标/器械标签、动作备注、上次真实记录、有氧时长/速度/适用动作坡度、加组、完成勾选、上一个/下一个、添加动作、训练备注、提前结束 |
| IMG_1312，大图动画 | AVQueuePlayer + AVPlayerLooper 播放仓库原有 MP4；缩小/放大、暂停/播放；离开页面/后台暂停，减少动态效果下默认暂停 |
| IMG_1313，训练菜单 | 训练设置、添加动作、添加训练日、重命名、卡片/列表/紧凑布局、训练备注、全次进阶排除、放弃确认 |
| IMG_1314，未记录就结束 | 根据零完成/部分完成/全部完成显示结束提示，保存或放弃；只保留有实际勾选组的动作，空训练不会伪造完成记录 |

按钮、输入、导航、菜单、选择器与弹层由 SwiftUI/UIKit 提供。交互表面使用 `.glass`、`.glassProminent`、`glassEffect` 和 `GlassEffectContainer`；数据内容使用系统 Material 和分组列表。采用系统明暗适配，不用 CSS、WebView、模糊截图或仿玻璃背景。原生 API 依据：[Apple Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)、[safeAreaBar](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:))。

额外接通：动作说明、真实历史、动作替换/排序/移除、动作备注下次显示、单动作休息、单动作进阶排除、计时模式、RIR/RPE、组复制/删除、休息增减/跳过、提示音/触觉/闪屏/常亮、用户开启权限后的锁屏休息提醒。计划编辑器增加有氧目标和备注输入，使开始训练时能携带实际计划数据。未生成截图中的示例计划、上次记录或完成数据。

## 数据与资源

- `GymModels.swift` 的新增记录字段均可缺省，兼容原来的 `gym-state.json`；原先的身体指标和 RIR 改动保留。
- `WorkoutLogic.swift` 保存时长/速度/坡度/计时秒数、备注、来源训练日、选择位置、布局、进阶排除和休息结束时间。复制组清除完成状态、完成时间及强度，保留训练参数。保存/放弃/编辑失败会回到最后成功持久化的训练状态，并显示错误。
- 全次进阶排除会传递给后来加入的动作；单动作可以独立取消。实际历史保留全部训练，但数值沿用跳过排除记录以及不同记录模式。
- `workout-catalogue.json` 由 `scripts/ios/generate-workout-catalogue.mjs` 从网页端目录、中文翻译和同一坡度适用规则生成，覆盖 6554 个既有原生 ID。中文说明缺失时沿用目录提供的英文说明，不编造动作指导。
- Xcode 直接打包仓库 `catalogue/media` 文件夹和原有 NOTICE。文件总量约 189.9 MiB，未新增另一份媒体副本。原生播放器无需网络；打包后文件名/路径及循环播放仍待实际验证。若外部打包流程另外把媒体复制进 `public/exercise-media`，需避免在原生包里重复携带这一份资源。
- 未更改网页端数据协议，也未新增网页账户与原生 `gym-state.json` 的同步或迁移。截图对应的交互接入原生存储。

这次对齐的是四张图展示的训练流程。网页端额外的专注布局、超级组、递减组/休息暂停组、左右侧独立记录、杠铃配片与完整进阶算法，尚未移植为原生等价能力；不能宣称整个 `Workout.jsx` 已全量对齐。

## 检查与待验收

已运行 `scripts/ios/check-native-workout.py`：Swift 语法树、Xcode 注册、所有目录 ID 和媒体文件引用、原生 API 使用检查通过；`git diff --check` 对本轮已有文件改动通过。详情及文件 SHA-256 见 `workout-page-static-checks-2026-10-23.json`。这些都是静态检查，不是 Swift 类型检查或 UI 测试。

新增 11 项 XCTest：旧数据解码、有氧完整往返、非法数值/空坡度、复制语义、进阶排除与可见历史、后加动作继承、删除选择/休息状态、完成过滤及备注、空训练、跨模式隔离、混合排除。**尚未执行**。

Mac 上执行（已存在的身体/喝水测试也会运行）：

```sh
swift test --package-path frontend/ios
node scripts/ios/generate-workout-catalogue.mjs
cd frontend
npm ci
VITE_MOBILE=1 npx vite build
npx cap sync ios
cd ios/App
xcodebuild -workspace App.xcworkspace -scheme App -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/opengym-workout-derived CODE_SIGNING_ALLOWED=NO build
```

后续验收必须实测：

1. iOS 26 的四种参考状态，包括小屏幕、大字体、明暗模式、键盘、VoiceOver 和横屏；确认数字列不会挤压，系统玻璃不影响可读性。
2. 从计划及自由训练进入，添加/替换/移动/删除动作、追加训练日、输入/勾选/取消/复制/删除组，收起后继续以及杀进程后恢复。
3. 5 min / 4.5 km/h / 坡度的持久化与历史回读；力量和计时使用独立单位。
4. 动画真实循环、暂停/放大/缩小及离屏停止；目录缺图时显示缺失状态。
5. 未记录、部分完成、全部完成三类结束分支，以及放弃取消/确认；模拟磁盘写入失败确认不会丢失活跃训练。
6. 进阶排除后保留历史、下次沿用跳过该记录，追加动作与单动作取消排除。
7. 休息关闭、增减、跳过、跨后台/锁屏提醒、提醒权限拒绝、减少动态效果和常亮恢复。

同一 checkout 中其他身体、喝水及底栏改动保持各自所有权；此文只记录训练页工作。共享的 Xcode 工程、Package.swift、模型与 Store 均在读取当前内容后增量修改。

推送准备以远端最新 `main` 为父提交，保留其身体页与签名配置；工程和 Package.swift 仅加入训练页相关条目。隔离导出待提交文件树后重新执行本页检查，证据文件记录这棵交付树的内容。原工作目录、真实索引和本地分支位置保留，避免改动其他页面的工作现场。
