# iOS 与 H3 网页共用数据

## 当前根因与线上核对

2026-10-23 核对：原生入口 `SceneDelegate → RootView → GymStore` 只读写设备 `gym-state.json`，没有调用现有网页登录/同步接口。饮水与服用记录独立保存在 `wellness-state.json`。不存在需要把网页数据搬进去的第二套 iOS 后端。

现有服务地址为 `https://h3.lin0.org/gym`，H3 路径 `/srv/ai/opengym`，网页监听 `127.0.0.1:9133`。公开和内网 `/gym/api/health` 均返回 HTTP 200、`writable: true`；未登录 `/gym/api/me` 返回 401。根路径 `/api/health` 在该网页端口返回 404，因此必须保留 `/gym`。

只读检查 rev 214 的账户文档：3 套计划、5 次训练、62 条体重、63 条身体测量、16 件器械。未把个人记录、账户凭据或服务器密钥放进仓库，未向生产账户写入测试数据。个人直连修复已更新 H3 的 API 认证入口，记录见下文。

## 本次源码修改

- `GymCloudSync.swift` 从私有安装包读取个人连接配置，使用现有 `me` 和 `data` 接口；凭据保存在设备 Keychain，保留 HTTPS 部署子路径，拒绝重定向转发凭据。App 无账户选择、登录或配对入口。
- 第一次连接先备份本机训练数据，再下载网页数据，不上传手机空状态。正在进行的训练不跨设备同步；首次采用网页账户时，原来的本地训练会留在备份中。
- 本地缓存将上次下载基线和当前待上传快照放在同一个原子文件中；下载失败、写入失败、401、服务器冲突均保留本机记录。
- 前台进入、前台每 30 秒、修改后的延迟保存触发同步；每次上传携带 `baseRev` / `baseWid`，成功后重新读取服务器文档。同字段并发冲突停止并提示，用户可明确选择备份本机副本后重新下载。
- `GymSyncBridge.js` 在系统 JavaScriptCore 内进行数据转换，没有 WebView。网页原始文档保留，写回只改原生实际编辑的字段，未知字段、进阶规则、组细节、器械照片、日期排程等保留。
- 兼容网页任意字符串 ID、重复动作、周日 0/7、kg/lb、km/h/mph、左右围度、自定义围度、体脂、原计划负重和器械记录。网页日期排程用于原生今日计划。
- 首页显示同步状态，设置提供「数据同步」。器械库显示现有网页器械记录；围度明细显示左右项和自定义项。

## 已执行验证

1. `node --test scripts/ios/gym-sync.test.mjs`：20 项通过。包含实际启动的本地 API 服务、隔离合成账户、浏览器配对码生成及兑换、首次读取、条件上传、回读、409 后合并重试、配对码不可重复使用。其余覆盖无修改完整往返、未知字段保留、独立修改合并、同字段/删除冲突、删除墓碑、单位与日期/ID 转换等。
2. H3 当前账户文档只在进程内读取并做转换：完整往返一致，ID 唯一；单字段候选修改仅改变 `restSec`。没有执行生产 PUT。
3. `scripts/ios/check-native-sync.py`：所有当前 Native Swift 文件语法解析通过、新增 Sources / JS Resource 引用齐全。此项不等同于 Swift 类型检查或 Xcode 编译。
4. 本次拥有的文件 `git diff --check` 通过。Git 交付仅包含本次同步改动，保留已有身体页报告及其他对话的页面、水体与底栏修改。用户明确将喝水和服药后端留待后续处理。

## 实际启用与未验证项

需要在 Mac 上按既有 iOS 工程流程生成依赖、完成 Xcode 26+ 编译并安装更新后的 App。此 Windows 环境未完成 Swift 类型检查、Xcode 构建、签名、手机安装、真实 Keychain / URLSession / JavaScriptCore 联动及双设备验收；不能把上述 Node 验证当作手机同步已完成。

## 个人直连与 Mac 首次配置

用户确认只有一个使用者，因此不再要求 App 配对。仍使用现有用户 ID 作为服务器文件标识，未新建用户或复制一套数据。

- `api/ios-personal.js` 用现有服务器密钥签发个人 iOS 凭据，仅允许 `GET /api/me`、`GET /api/data`、`GET /api/data/rev`、`PUT /api/data`。不会换取通用登录令牌，不能管理账户或创建配对码，不能通过 Cookie 使用。现有 `sv` 撤销机制和禁用账户仍有效，网页认证方式不变，匿名访问仍为 401。
- 签发要求服务器恰好有一个启用用户。凭据只存放在私有配置文件中，不进 Git、日志、公开接口。该配置和由其编出的安装包只供本人使用。
- Xcode 构建阶段把 `frontend/ios/App/Private/GymPersonalConnection.json` 写入 App 资源。缺失配置时构建失败，避免再次产出无法连接的空白 App。`Private/` 已被 Git 忽略。
- 配置通过 SSH 从 H3 的 `~/.config/opengym/GymPersonalConnection.json` 取回。Mac 在仓库根目录运行一次：

```sh
git pull --ff-only origin main
node scripts/ios/setup-personal-connection.mjs
```

默认 SSH 目标为 `lin-server@10.100.5.110`，需在能访问 H3 的网络中运行；可用 `--host h3-dashboard` 使用该 Mac 已有的 SSH 别名，或 `--file /安全路径/GymPersonalConnection.json` 导入本人私有文件。然后在 Xcode 26+ 中重新 Build / Run 安装。以后正常更新源码不需重复配置。App 启动自动连接并下载。

撤销或轮换：网页「退出所有设备」会使个人凭据失效；在 H3 API 容器内重新运行 `node ios-personal.js --provision /data https://h3.lin0.org/gym /data/新的私有输出文件.json`，通过管理员通道替换 SSH 私有配置后，Mac 重新取回并打包。不要把服务器 `secret` 放入安装包。

本轮新增个人凭据、作用域、禁用/撤销、无配对真实本地 API 同步测试，连同既有网页登录、配对、条件写入及桥接测试，共 31 项通过。H3 API 已重新构建并激活：公网 HTTPS 的个人 `/api/me`、`/api/data` 均为 200，匿名数据与个人凭据访问管理接口均为 401。实际数据投影为 3 套计划 / 5 次训练 / 62 条体重 / 63 条测量 / 16 件器械，rev 214；部署前后状态文件 SHA-256 完全一致，生产验证未发送 PUT。SSH 配置取回脚本已执行成功，并确认私有文件被 Git 忽略。手机端仍需实际安装验收，不能把 Node / 静态检查当作 Xcode 或真机通过。

饮水、饮品与服用提醒是新原生模块，当前网页没有对应功能，本次仍为本机持久化，已在连接界面明确显示。网页其他尚无原生编辑界面的字段会随完整原始文档保留，不能把数据保留解释为原生功能已全部对齐。

静态检查所需 Python 包：`tree-sitter==0.26.0`、`tree-sitter-swift==0.7.4`、`openstep-parser==2.0.3`。本机复用了临时目录内已有的 Python 3.12 模块，没有改全局 Python 环境。

## H3 回退记录

部署备份位于 `/srv/ai/opengym/deploy-backups/ios-personal-20261023T110455Z`，含原 API 源文件、Dockerfile、原镜像 ID 和部署前 data 压缩包，目录 0700、数据备份 0600。原镜像保留为 `opengym-api-before-personal:20261023`。只更新了 API 容器，网页容器、原用户、原状态文件和饮水/服药模块未迁移。私有构建配置在 H3 SSH 用户目录权限为 0600。
