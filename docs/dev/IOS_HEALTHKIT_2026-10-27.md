# iOS 训练结束后的 HealthKit 结果

## 本次本地提交边界

本次提交仅含 iOS HealthKit 接入、同步字段、健康指标显示、工程权限、同步往返测试及本文。混合文件按改动拆分，未包含 UI refinement 和个人连接配置。下文 API/邮件验证描述的是完整工作区的实现，不表示这些服务端改动已包含在本提交。

`api/workout-sync-events.js` 和 `api/test/workout-sync-events.test.js` 在提交前均是另一批暂存但尚未提交的新文件，HEAD 中不存在；无法只提交其中 health 几行而不引入整个未提交事件模块。因此这两文件以及依赖它的 `api/test/workout-health.test.js` 保留在原工作区，待事件模块自身提交后再提交 HealthKit API 增量。仅检出本提交尚不包含服务端完成事件扩展。没有 push 或部署。

## 实现

原项目无 HealthKit / Capacitor Health 插件。当前训练入口是原生 SwiftUI，因此新增 `WorkoutHealthReader.swift` 原生 HealthKit 适配层，不安装 npm/Pod 插件，也不经 WebView。只有完成后批量查询，无运动中心率流、无后台 HealthKit 投递、无写入健康数据。

首次在结束训练页打开「读取本次健康数据」（会记住选择），明确提示数据随已连接服务器同步用于邮件/总结。结束按钮先冻结结束时间，申请读取权限并读取，再将结果和训练一起原子保存。重复结束受保护，拒绝/缺失/查询错误仍可保存训练。每个数据查询 10 秒超时；系统授权弹窗由用户决定，不自动取消。

- Workout 匹配：查询重叠时间窗，选与本次训练重叠最多且覆盖双方时长至少 80% 的记录，避免相邻训练串单。
- 心率：在本次起止时间内取平均及最大 bpm；匹配到 Workout 时优先使用其来源，来源无心率或没有匹配时使用时间窗内可读心率（兼容第三方导入训练与独立心率传感器）。平均值是 HealthKit 样本统计，不是时间加权平均。
- 活动能量：只统计匹配 Workout 关联且位于本次时间窗内的活动能量，单位 kcal，不与全天卡路里或基础代谢相加。无匹配/无样本时省略。
- 本地 `WorkoutSession.health` 与云端 `workouts[].health` 双向保留；历史训练卡显示心率及活动能量。
- 同步前对最近 24 小时内最多 5 次已选择读取、但心率或活动能量仍缺失的训练补读，不从同步入口弹授权。补读只在有新增结果时保存，不因查询时间变化反复写云端。
- `PUT /api/data` 的 `workout.completed` payload 附 `health`，邮件和 Webhook 共用该对象。继续按 workout ID 去重，不因晚到健康数据重新发完成邮件。若首次同步时 Watch 数据未到，首次邮件可能没有指标；后续同步补入训练记录。要尽量让首封总结完整，请先在 Watch 结束体能训练并等数据到达手机，再在 openGym 结束。
- 未改 Shortcut → `/gym/api/hook/body` 晨间路径。

字段：`source=apple_health`，`status=available|no_data|unavailable|query_failed`，`window_start/window_end/queried_at`（存储为 epoch ms），可选 `workout_id`、`heart_rate_avg_bpm`、`heart_rate_max_bpm`、`active_energy_kcal`。事件封装沿用现有规则将 `queried_at` 转为 +08:00 ISO 字符串；window 起止仍是 epoch ms。缺失值在事件中为 null，不伪造 0。HealthKit 不向 App 区分拒绝读取与没有样本，`no_data` 不能解释为用户明确拒绝。

## 本机编译与安装（Mac）

当前 Windows 工作区不能执行 Xcode。需要把这批文件连同现有工作区中个人同步链路的相关改动带到 Mac；不能只拷贝新增 Swift 文件。使用 Xcode 26+（工程 App deployment target 为 iOS 26.0），安装 Node 和 CocoaPods。

在 Mac 仓库根目录执行：

```sh
npm --prefix frontend ci
cd frontend
VITE_MOBILE=1 npm run build
npx cap sync ios
cd ..
# 已有 Private/GymPersonalConnection.json 时不必重做。
# 以下脚本读取既有个人连接配置，不部署服务；需要已有 SSH 访问。
node scripts/ios/setup-personal-connection.mjs
open frontend/ios/App/App.xcworkspace
```

Xcode 选择 App target → Signing & Capabilities → Automatically manage signing，Team 选自己的 Personal Team，必要时把 Bundle Identifier 改为自己唯一的标识。不要沿用仓库中的其他 Team ID。确认基础 HealthKit 已启用；Debug/Release 均引用 `App/App.entitlements`。没有 HealthKit Background Delivery、Clinical Health Records 或 App Groups。

Apple 当前支持表的免费 Apple Developer 列也支持基础 HealthKit：<https://developer.apple.com/help/account/reference/supported-capabilities-ios>。因此此功能本身不要求购买会员；免费 provisioning 的有效期/安装限制仍由 Apple 管理，需用实际个人账号在 Xcode 确认签名。连接 iPhone、启用开发者模式并信任开发签名，选择设备后 Run。模拟器构建可检查编译，无法代替真实 Watch 健康样本验收。

可选命令行编译检查（准备好上述个人配置后）：

```sh
xcodebuild -workspace frontend/ios/App/App.xcworkspace -scheme App \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
swift test --package-path frontend/ios
```

仅读取，所以配置 `NSHealthShareUsageDescription`，不请求写入也不添加 `NSHealthUpdateUsageDescription`。无需删除 HealthKit capability 来使用免费签名。

## 用户权限

1. 结束训练页开启「读取本次健康数据」，点结束并保存。
2. 系统健康授权中允许读取 **体能训练、心率、活动能量**。不需要写入权限，也不要求体重、睡眠或晨间数据权限。
3. 以后可在「健康」App → 头像 → 隐私下的 App/应用与服务 → openGym 中调整这三项（名称随系统语言略有差异）。
4. 用 Apple Watch 或其他支持的设备记录运动心率，并确保数据已同步到 iPhone。手机 App 本身不会凭空测量心率。

## 验证与发布边界

- 27 项相关 Node 测试通过，覆盖云端往返/并发合并、实际本地 API 的 PUT → SMTP 邮件与 Webhook、指标传递、晚到更新不重复发信及旧记录兼容。
- 8 项身体 hook 解析/HTTP 请求体回归通过。
- 全部 Native Swift 语法解析通过，新增 Sources 引用、Debug/Release entitlement 与 plist 检查通过。这不是 Swift 类型检查、Xcode 编译或真机验收。
- 既有事件去重测试的 Unix 0600 断言仅在非 Windows 上执行；Windows ACL 不表示相同的 mode 位，其他去重断言照常执行。
- iOS HealthKit 改动单独本地提交，未部署 H3。服务端需要更新 `api/workout-sync-events.js` 的 payload 组装，才会在生产完成邮件中出现 health；现有共享工作区中该模块、`server.js`、Dockerfile 和个人同步授权改动也是前置依赖，不应盲目整仓部署。

真机需检查：首次三项授权、拒绝权限也能保存、真实训练窗的心率/能量与健康 App 对照、无 Workout 但有心率、Watch 晚到补读、离线保存后同步、同一训练不重复邮件。未执行这些验收。
