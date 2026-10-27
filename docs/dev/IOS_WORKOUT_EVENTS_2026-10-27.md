# 个人 iOS 训练事件（2026-10-27）

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
