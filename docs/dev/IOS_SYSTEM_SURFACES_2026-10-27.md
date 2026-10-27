# iOS 实时活动、小组件与快捷指令身体同步

实现位置：`frontend/ios/App`，沿用 iOS 26 部署目标。已扩展 `/api/hook/body` 的睡眠分期输入；需要 H3 API redeploy，本次未部署。

## 入口与行为

- 开始计划/自由训练并成功保存后创建 Live Activity；完成、取消训练并成功保存后立即结束。换动作、完成/撤销组和改变组数会更新。显示动作名及**已完成组数/总组数**；空训练显示选择动作。锁屏、灵动岛点击 `opengym://workout` 返回当前训练。
- 本地 ActivityKit 更新串行处理，相同展示内容不重复发送，连续变化最多每秒一次并合并末次状态；没有逐秒计时更新、推送或 Frequent Updates entitlement。每次回到前台会恢复/清理活动。系统禁用、系统时限或用户移除会影响显示；启动错误在训练页显示。
- `GymWidgets` extension 包含「今日喝水」small、「今日锻炼」small 和「体重趋势」medium（最近 30 条记录、折线/面积、单点及空态）。计划显示名称与已练状态，点击进入训练或安排计划。使用系统文字样式/语义背景适配深浅色。
- 喝水写入成功、训练/计划/体重保存成功、云端快照应用和前台日期变化会发布 App Group 摘要，仅内容变化时请求时间线刷新。预先提供午夜条目，避免昨天的喝水/已练状态延续到今天；预存 8 天计划。WidgetKit 最终刷新时机由系统控制。
- `opengym://water`、`opengym://body` 对应页面；UIKit SceneDelegate 处理冷启动与热启动链接，RootView 等前台激活后消费。

## 每天 9:30 的主路径：快捷指令打开 App

1. App「数据同步 → 身体数据快捷指令」填写 HTTPS 根地址（如 `https://h3.lin0.org/gym`）与现有 **WEIGHT_HOOK_TOKEN**，点保存。凭据只在本机 Keychain；URL、小组件共享摘要不包含凭据。该令牌不同于 App 登录的 `ios:` 令牌，按服务端 `WEIGHT_HOOK_UID` 对应账号写入。
2. 在解锁状态点击「立即同步身体数据」，授予体重、体脂率、去脂体重、睡眠、步数、静息心率、心率变异性的健康读取权限。授权只读，不写 Apple Health。
3. 快捷指令新建操作：「URL」=`opengym://sync-body` →「打开 URL」。个人自动化选择每天 **09:30**，运行此快捷指令，选择系统允许的立即运行选项。
4. 每次拉起 App 显示同步状态页，读取 **Asia/Shanghai 当天**身体三项最新样本及当日健康统计，然后 POST `<根地址>/api/hook/body`：

   ```json
   {"date":"2026-10-27","weight_kg":72.4,"body_fat_pct":18.5,"lean_mass_kg":59.0,"sleep_hours":7.5,"deep_min":60,"core_min":300,"rem_min":80,"asleep_min":10,"awake_min":15,"steps":8123,"resting_hr":58,"hrv_ms":42.5}
   ```

   请求头仍为 `Authorization: Bearer <WEIGHT_HOOK_TOKEN>`。缺少的类型省略，不上传空值；不把昨天的样本冒充今天。首次拒绝读取与无数据都可能表现为空样本，UI 提示检查权限。读取超时、网络失败、401/404 等显示错误；只在服务端 `ok: true` 后显示上传成功，可重试同日覆盖更新。
5. 成功后请求现有云同步以刷新 App/小组件；如云同步暂忙或离线，按原有前台同步周期重试拉取。Hook 成功与本地云同步成功是两件事。

锁屏时打开 App 或读取受保护健康数据可能要求解锁，URL 入口不承诺无人值守锁屏上传。弃用旧 Shortcut「读取健康样本 → Bearer POST hook/body」：新版本 App 与 API 部署并验收后即可删除，只保留打开 `opengym://sync-body` 的自动化。服务端继续兼容旧 body-only payload。

**本次没有启用 HealthKit observer/background delivery，也没有注册 BGAppRefresh。**用户选择的主路径是定时快捷指令。未来如果添加 HK 后台投递，只能作可选补充，不能保证定点；BGAppRefresh 同样不能保证每天 09:30。无数据或失败不会后台无限重试，下次快捷指令/手动调用重新读取并上传。

## Xcode 工程与能力边界

- App bundle `org.lin0.opengym`，extension `org.lin0.opengym.widgets`；App target 依赖并通过 Embed App Extensions 嵌入 extension。共享 `Shared/GymWidgetData.swift` 同时参与两个 target 编译。
- 两个 target 都声明 `group.org.lin0.opengym`。在 Mac 的 Signing & Capabilities 中选择同一有效 Team，注册并为两个 App ID 启用该 App Group；主 App 保留 HealthKit，extension 不请求 HealthKit。工程沿用现有 Team ID。
- Live Activity 采用本地更新和 URL Scheme，无 APNs/推送证书、无需服务器改造。**完整小组件数据共享依赖 App Groups 签名能力，不能保证免费 Personal Team 可签。**免费团队能力不够时，不能靠写 entitlement 绕过：需有相应能力的 Team 才能验收完整功能；移除两个 target 的 App Groups entitlement 后只能试本地 Activity/URL 路径，小组件共享不可用。HealthKit 也须以实际 provisioning profile 为准。
- 官方依据：[ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)、[健康数据授权](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)、[能力与团队限制](https://developer.apple.com/help/account/reference/supported-capabilities-ios)。

## 验证与 Mac 交接

Windows 已通过：`scripts/ios/check-system-surfaces.py`（44 个 Swift 文件语法解析、13 项工程/能力接线检查）、`check-native-sync.py`、`check-native-workout.py`；`node --test scripts/ios/gym-sync.test.mjs` 23/23（包含本地 API 同步回归）。语法解析不是 Swift 类型检查。

Mac 使用 Xcode 26+，保留已有 `Private/GymPersonalConnection.json` 构建配置，`pod install` 后打开 `App.xcworkspace`：

```sh
swift test --package-path frontend/ios
xcodebuild -workspace frontend/ios/App/App.xcworkspace -scheme App -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

仍待 Mac 编译/签名与真机验收：

1. 两个 target Debug/Release 编译；真机启动计划与自由训练、换动作/勾组/撤销，核对锁屏和灵动岛，结束/取消后消失；强制关闭后重开不重复活动。
2. 添加三个小组件；修改喝水、目标、体重、训练和今日计划，确认内容刷新、跨午夜/时区、空数据、单点曲线；深浅色、最大动态字体、VoiceOver。
3. 冷/热启动四种 URL；训练页已有弹层时点击链接；9:30 自动化在锁屏与解锁状态分别试，记录系统是否要求解锁。
4. 健康权限拒绝/部分授权、今日无样本、仅体脂/仅去脂、断网/错误令牌、重复调用；确认不写空值、不改昨日数据、原 Shortcut POST 仍可用。成功回读服务器数据与 App 体重曲线。

没有在 Windows 宣称 Xcode 编译、签名或设备验收完成。

## 统一身体与健康同步字段契约（Lumi）

同一个 `POST /api/hook/body`，所有数值字段可选；无样本/未获读取权限省略，不发送 null。没有任何可读指标时不发请求。所有查询窗口是 Asia/Shanghai 当日 00:00 至调用时刻，非完整日终统计。

| JSON 字段 | 单位及统计口径 | 落库 |
| --- | --- | --- |
| date | YYYY-MM-DD，上海日期 | 两种存储的日期键 |
| weight_kg | kg，当日最新 | state bodyweight（按用户单位转换） |
| body_fat_pct | 百分数，例如 18.5，当日最新 | state measurements.bodyFat |
| lean_mass_kg | kg，当日最新 | state measurements.other，id=hook-lean-mass-kg |
| sleep_hours | 小时，睡眠区间总时长，不含清醒/卧床 | health-<uid>.json[date] |
| deep_min | 深睡分钟 | 同上 |
| core_min | 浅睡/Core 分钟 | 同上 |
| rem_min | REM 分钟 | 同上 |
| awake_min | 有记录的清醒分钟 | 同上 |
| asleep_min | 未指定分期的睡眠分钟，不与详细分期重复累计 | 同上 |
| steps | 步，当日 HealthKit cumulativeSum | 同上 |
| resting_hr | 次/分钟，当日样本算术平均 | 同上 |
| hrv_ms | 毫秒，SDNN 当日样本算术平均 | 同上 |

跨午夜睡眠只取当天部分（例如昨晚 23:00 至今天 07:00 计今天 7 小时），不是按起床日计整晚。忽略 inBed；重叠区间只算一次，详细分期优先于未分期，分期冲突选结束时间较晚的样本，仍相同按 UUID 排序。不模拟健康 App 的用户自定义来源排序；多设备冲突与真实健康 App 数值一致性待真机核对。缺失的分期不补零，sleep_hours 可含 asleep_min，所以不应仅以 deep+core+REM 推断总量。

服务端沿用既有精度：身体、睡眠小时、HRV 一位小数；新增分期分钟一位小数；步数和静息心率取整。同日重传只合并已提供指标，缺失不会删除旧值。`health.daily` 事件包含已合并健康字段和本次身体字段；既有事件格式可能把未提供字段置 null，Lumi 应区分事件缺失与实际零值。body-only 请求仍只写身体存储。

实现使用 Apple [统计查询](https://developer.apple.com/documentation/healthkit/hkstatisticsquery)累计步数与计算日均值。权限只读；系统不会向 App 区分读取拒绝和没有样本。

新增验证：`node --test api/test/body-hook-native.test.js api/test/body-hook-sleep.test.js` 9/9，通过本地临时 API 进程验证一次 POST 双存储、旧 payload、部分重传和缺失保留。Mac/Xcode 类型检查、签名、真机 HealthKit 查询、真实 H3 当日双存储验收仍 **pending**。先 redeploy H3 API，再安装新包授权并运行一次 sync-body，核对当日两类存储后删除旧 Shortcut；未修改部署脚本，未自动部署。
