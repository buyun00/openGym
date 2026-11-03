# 个人 iOS 训练事件（2026-10-27）

## 2026-11-03：首次完成通知等待健康数据

此前 POST 完成事件和 PUT 训练同步各自先认领、后投递；先到的快照缺心率时，后续同步虽保存了健康数据，也会被去重，Lumi 收到的首条通知仍缺指标。

现在两路先进入同一个持久化完成队列，发送前读取最新已保存训练，合并同一手选 HealthKit 运动的部分指标。平均心率、最高心率、活动热量齐全即发送；否则默认等待 60 秒，按秒检查，到期只发送一次已有数据，不伪造零值、不再发送补充完成通知。`WORKOUT_COMPLETION_HEALTH_WAIT_MS` 可调整等待，范围 100–120000 毫秒。重试不延长原截止时间，进程重启恢复待发记录；其他实时事件写入去重文件不会抹掉待发完成事件。旧历史不因启动扫描而重发，账户删除沿用原事件文件清理。

iOS 保存手选运动前每两秒重读同一 HKWorkout，查询与睡眠共用最多 20 秒预算；超时的重试保留此前读到的指标，取消后不保存。列表预览仍只读一次，没有自动匹配或后台补挂；明确跳过仍清空本次 health。网页完成事件也携带已有 health，服务端会保留比同步快照更新、更完整的所选指标，且不混合不同运动 ID。

本轮验证：38 项完成事件、HealthKit、个人凭据及原生同步专项测试通过，包含本地 HTTP → SMTP/Webhook 的首次投递复现、两种到达顺序、重启恢复、部分指标合并、手选记录替换、原截止时间和不重复投递。Swift/Xcode 工程静态检查见 [本轮报告](workout-completion-static-checks-2026-11-03.json)，全部通过；当前 Windows 未执行 Swift 类型检查、XCTest、Xcode 编译或真机 HealthKit 验收。完整 API 与原生桥接回归为 647 项中的 620 项通过，27 项失败均可在未修改的 HEAD 复现，涉及既有日期样例、Windows 文件权限及 API 文档覆盖问题。

交付：修复提交 `d0a62333` 已普通推送 `origin/main`。H3 以原运行镜像为基础仅更新 `server.js` 和 `workout-sync-events.js`，在隔离 Linux 容器中再通过 14 项专项测试后切换 API。部署后的 API 与网页代理健康接口均为 200 且可写，匿名数据请求为 401，API 和网页容器均为 healthy；运行文件 SHA-256 与提交原始字节一致，所有根目录 JSON（含训练状态）部署前后摘要一致，网页容器、环境和挂载未变。生产数据私有备份和原镜像均已保留；没有向生产账户写入测试训练，也没有重发旧完成事件。

HTTP 202 表示已接收（`pending: true` 表示仍在等待），不保证下游成功。已有先认领后投递及 webhook 有限重试语义保持不变。手机需从新源码重新构建安装才能使用所选运动重读；服务端更新可先修复 POST/PUT 的到达竞态。以下为 2026-10-27 的原交付记录。

个人包的训练界面是原生 Swift，未运行网页 workout-events 订阅；GymSyncBridge 是 JavaScriptCore 数据适配器，不是 Capacitor WebView 事件桥。此前个人 Bearer 凭证仅允许数据同步路由，两处共同导致训练中没有事件。此次无需 feature flag。

- `GymCloudSync.persistLocal` 比较保存前后的原生快照，借助 `GymSyncBridge.workoutEvents` 生成 `{type,data,event_id}`。服务端仍生成 `{id,type,occurred_at,user,data}` 信封，身份取自已验证凭证。
- 开练发 `workout.started`；与网页语义一致，某动作的全部组完成后发 `exercise.completed`（不是每勾一组都通知）；成功保存收工发 `workout.completed`。丢弃训练、下载历史、修改历史不会生成原生实时事件。
- 收工使用实际保存的 workout UUID，与 PUT 中 ID 完全一致。已有 HealthKit `health` 随事件发送，包括平均/最高心率和活动能量。收工跳过健康读取则不带；之后补录健康数据只更新记录，不再次推送收工。
- 待发事件和训练快照原子写入同一个账号/服务器绑定的缓存；旧缓存缺少新可选字段时仍能读取。同步 readback 保留队列，网络等待期间的新编辑不会被确认回写覆盖。
- 独立异步 FIFO 发送，单次超时 10 秒，失败最多连续尝试 3 次（间隔 2/4 秒）；失败静默留盘，后续保存或前台同步重试。网络不等待训练 UI，转换异常不阻止训练保存；本地保存失败沿用已有回滚逻辑。
- 客户端保留最近 2000 个事件键；服务端按用户持久化去重键。实时事件使用稳定 `event_id`，重复勾选、请求重试不会重复通知。收工仍按 `workout.completed:<workout_id>` 与 PUT 共用键，两种到达顺序均只发一次。服务端键有既有 2000 条保留上限。

鉴权只新增精确的 `POST /api/events`，现有 HMAC、Bearer-only、用户存在/禁用检查和 `sv` 吊销检查保留。个人凭证不能调用 `/api/events/test`、管理接口或兑换通用会话；事件端点仅接受三个训练类型。HTTPS、Keychain 和禁止携带凭证跟随重定向的行为不变。

验证：`node --test scripts/ios/gym-sync.test.mjs api/test/ios-personal.test.js api/test/workout-sync-events.test.js`，32 项通过；覆盖原生事件转换、health/单位/ID、部分组与动作完成、丢弃/历史隔离、真实本机 API 鉴权与吊销、POST/PUT 双向去重和实时事件重试去重。`git diff --check` 通过。

Mac/Xcode 编译、真机离线/杀进程恢复和 HealthKit 到 Lumi 的真实投递：**pending**。本次仅提交推送源码，没有部署服务端或发布 iOS 包；两端更新后才生效。API 的 202 是接收确认，不保证下游成功；既有 webhook 的有限重试及先认领后投递行为未改，未配置 webhook/email 时按既有协议返回 disabled 并消费事件。未改 H3 部署脚本。
