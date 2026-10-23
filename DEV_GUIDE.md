# openGym 开发说明（给 AI 编程助手）

> 本文是根据 2026-10-23 时的实际源码和部署情况写的。Windows 上的副本和 H3 上的部署副本里，`docker-compose.yml`、`api/server.js`、`api/body-hook.js`、`frontend/src/lib/exercises-data.js` 四个文件的 MD5 完全一致。
> 上游项目 README 和 `CLAUDE.md` 讲得更细，动手前请先读仓库根目录的 `CLAUDE.md` 和 `CONTRIBUTING.md`。

## 1. 项目概况
- openGym 是一个自托管的健身和体重记录 PWA，基于开源项目 DuarteSantos8/openGym（AGPL-3.0），版本 1.4.1。
- 本实例在上游基础上加了本地功能：身体数据 Webhook（`api/body-hook.js`）、器械库（`api/equipment.js`）、训练事件 Webhook 和邮件（`api/workout-webhook.js`、`api/workout-email.js`）。
- 访问地址是 https://h3.lin0.org/gym ，服务挂在子路径 `/gym` 下。
- 部署走 Cloudflare Tunnel（systemd 服务 `cloudflared-h3`），转发到 H3 本机的 `127.0.0.1:9133`。

## 2. 代码位置与工作流
| 位置 | 用途 |
|---|---|
| Windows `D:\其他项目\openGym` | **主副本，在这里改代码** |
| H3（h3-dashboard）`/srv/ai/opengym` | 部署副本，docker compose 在这里运行 |
| H3 `/srv/ai/opengym/data/` | **线上用户数据（不在源码里）** |

工作流：在 Windows 上改代码，同步到 H3 的 `/srv/ai/opengym`，再到 H3 上 build 和重启。Windows 上没有 Docker。

H3 上的命令可以从 Windows 机器执行：先写一个 Linux 脚本（必须用 LF 换行），再运行
`C:\Users\win11\agent-tools\h3sudo.ps1 <script.sh>`。
脚本里可以直接用 `S <命令>` 以 sudo 执行，这个 `S` 函数由 h3sudo 注入，**不要自己重新定义 S**。写脚本时建议用 `[IO.File]::WriteAllText(path, text.Replace("`r",""))`。

## 3. 技术栈
- **前端** `frontend/`：React 19、Vite 8、react-router-dom 7、Zustand 5，测试用 vitest。`android/` 和 `ios/` 是 Capacitor 壳，本部署用不到。
- **后端** `api/`：Node 22，单文件 `server.js`，直接用 `node:http`，不依赖任何框架。依赖包有 @simplewebauthn/server、web-push、undici。
- **web** `web/`：多阶段 Dockerfile，先 build 前端，再交给 nginx 托管静态文件，并把 `/api` 反代到 api 容器。nginx 配置 `nginx.conf.template` 在容器启动时按环境变量渲染。
- **mcp/**：只读的 MCP 服务器（stdio），不参与 Docker 构建。
- 仓库没有配置 ESLint、Prettier 或 TypeScript，请手动保持现有代码风格。
- 上游有一条硬约束：**尽量不加新依赖**。

## 4. 目录速览
```
api/            server.js（所有路由）、body-hook.js、equipment.js、workout-webhook.js、workout-email.js、
                coach/（可选 AI 教练）、openapi.yaml（路由文档）、test/（node --test）
frontend/src/
  App.jsx       路由入口
  views/        每个页面一个文件（Home、Workout、Plan、Library、Stats、History、Settings、Admin、Login、RoutineEdit…）
  components/   共享 UI；instr/ 存各语言的动作说明；locales/ 是 i18n 文案
  store/        useStore.js 是唯一的 Zustand 全局状态（localStorage 键 gym_state_v1，登录后防抖推送到服务器）；useUI.js 存临时 UI 状态
  lib/          纯逻辑函数，每个文件旁边都有 *.test.js
                progression.js（加重规则）、onerm.js（1RM 估算）、finish-workout.js（训练结束后写回状态）、
                exercises.js / exercises-data.js（动作库 EXDB，内置 1324 个动作）、api.js（唯一和后端通信的模块）
web/            Dockerfile、nginx.conf.template
docs/           SELF_HOSTING.md、API 等文档
docker-compose.yml
```
常用动作 id（来自 exercises-data.js）：0585 坐姿腿屈伸、0599 坐姿腿弯举、0770 史密斯深蹲、10671 坐姿推胸、2291 高位下拉、2259 跑步机。

## 5. 后端 API
`server.js` 用一个 `routes` 对象登记路由，键名格式是 `'METHOD /api/path'`，加新接口就往这个对象里加键。nginx 在 `/gym` 前缀下把请求转给 API，所以外部访问地址是 `https://h3.lin0.org/gym/api/...`。

主要路由：
- 认证：`/api/register/*`、`/api/login/*`（passkey）、`/api/login/password`、`/api/register/password`（本实例设置了 `PASSWORD_LOGIN=1` 和 `INVITE_ONLY=1`）、`/api/logout`、`/api/me`、`/api/config`、`/api/health`
- 数据同步：`GET /api/data`、`GET /api/data/rev`、`PUT /api/data`
- 器械：`GET/POST/DELETE /api/equipment`、`/api/equipment/photo`、`GET/POST /api/hook/equipment`（用 Bearer token 访问）
- 事件：`POST /api/events`、`POST /api/events/test`
- 推送：`/api/push/*`；媒体：`/api/media/*`；管理：`/api/admin/*`

### 身体数据 Hook：`POST /gym/api/hook/body`
- iPhone 快捷指令用它上传体重和健康数据。
- 认证方式是 `Authorization: Bearer <WEIGHT_HOOK_TOKEN>`。数据只写入 `WEIGHT_HOOK_UID` 对应的用户，这两个值都放在 `.env` 里。
- 如果没配置 token，接口返回 404；token 不对返回 401。
- 请求体字段：
  - `date`：可省略，默认取今天，时区是 `WEIGHT_HOOK_TZ=Asia/Shanghai`
  - `weight_kg` 或 `weight`
  - `lean_mass_kg` 或 `lean_mass`
  - `body_fat_pct` 或 `body_fat`：可以写成 0–1 的小数，也可以写成百分数
  - 睡眠和健康字段：`sleep_hours` 或 `sleep`、`sleep_stages`，以及 resting_hr、hrv_ms、steps 等
  - `delete: true`：删除当天由 hook 写入的数据
- 写入位置：
  - 体重写进 state 的 `bodyweight`
  - 体脂写进 `measurements[].bodyFat`
  - 去脂体重写进 `measurements[].other`，条目 id 是 `hook-lean-mass-kg`，名称是“去脂体重 (kg)”
  - 当天时间戳固定为 09:00（UTC+8）
  - 健康数据单独写进 `data/health-<uid>.json`
- 写入成功后，如果配置了 webhook 或邮件，会发出一个 `health.daily` 事件。

## 6. 数据文件与 state 结构
`/srv/ai/opengym/data/` 下有这些文件：
- `db.json`：用户、凭据、订阅、邀请码
- `state-<uid>.json`：每个用户的全部训练数据，本实例是 `state-i06scweA1KIIzEE0.json`
- `health-<uid>.json`
- `secret`：会话签名密钥
- `vapid.json`
- `audit.log`

文件写入用的是“先写临时文件再 rename”的原子方式。

state 是一个 JSON 对象，主要字段如下：
- `routines`：训练计划列表，每项为 `{id, name, emoji, ex:[...]}`。`ex` 里每项为 `{id: 动作id, sets, reps?, w?, min?, speed?, note}`。目前有 lf-strength-a（全身力量 A）、lf-elliptical、lf-strength-b。
- `workouts`：训练记录列表，每项为 `{id, d:'YYYY-MM-DD', start, end, routineId, routineIds, name, bw, entries, prs, vol}`。`entries` 里每项为 `{id, sets:[{w, r, done, at, ...}], target, planned, rid, topW}`。
- `bodyweight`：`[{d, w, t}]`
- `measurements`：`[{d, t, neck…ankleRight, bodyFat, other:[{id, name, value}]}]`
- `exWeights`：`{动作id: {w, d}}`，记录每个动作当前用的重量
- `gymEquipment`：`[{id, name, primary, secondary, exIds, exNames, note, location, photo, _ts, created}]`
- 其他字段：week、dayPlan、customEx、equipProfiles、各种设置项，以及同步元数据 `_rev`、`_ts`、`_wid`、`_wids`、`edited`、`deleted`、`_prior`

## 7. 构建与部署（在 H3 上执行）
`docker-compose.yml` 定义了三个服务：
- api：build 上下文是 `./api`，挂载 `./data:/data` 和 `./coach-auth`
- web：build 上下文是 `.`，使用 `web/Dockerfile`，端口映射为 `${WEB_PORT}:80`
- media：一次性下载动作素材的服务

关键配置在 H3 的 `/srv/ai/opengym/.env` 里（**包含密钥，不要提交，也不要贴出来**），主要有：
- `RP_ID=h3.lin0.org`
- `ORIGIN=https://h3.lin0.org`
- `BASE_PATH=/gym`
- `WEB_PORT=127.0.0.1:9133`
- `WEIGHT_HOOK_*`、`WORKOUT_WEBHOOK_*`、SMTP 相关配置

当前运行的两个容器是 `opengym-api-1` 和 `opengym-web-1`。镜像虽然标着 `ghcr.io/duartesantos8/opengym-*:latest`，但其实是本机从源码 build 的，build 时间是 2026-10-16 13:03（UTC+8）。

部署步骤：
1. 先备份源码。以前的做法是 `/srv/ai/opengym-src.bak-<时间>.tgz`。
2. 再备份数据，以前的做法是 `data.bak-<时间>/`，例如：
   `S cp -a /srv/ai/opengym/data /srv/ai/opengym/data.bak-$(date +%Y%m%d%H%M%S)`
3. 把 Windows 上改过的文件同步到 `/srv/ai/opengym`。仓库里没有现成的同步脚本，可以打包后传过去，或者用 scp/rsync。**同步时排除 `data/`、`.env`、`coach-auth/`、`node_modules`、`.git`，不要用 Windows 的版本覆盖它们。**
4. 构建并启动：
   `cd /srv/ai/opengym && S docker compose up -d --build`
   **必须带 `--build`**。compose 文件里同时写了 `image:`，不带 `--build` 可能会拉上游镜像，把本地改动冲掉。
5. 验证：
   - `S docker compose ps` 显示容器 healthy
   - 打开 https://h3.lin0.org/gym 能正常访问
   - `/gym/api/health` 正常返回

构建时出现 `http_cf_connecting_ip variable is not set` 警告是正常的，可以忽略。

测试命令：
- 前端：`cd frontend && npm test`
- 后端：`cd api && npm test`

## 8. 注意事项
1. **不要覆盖 `data/` 下的 state 文件。** 手动改数据前必须先备份，例如 `cp state-xxx.json state-xxx.json.bak-<说明>-<时间>`。改完以后要把 `_rev` 加 1，否则客户端可能会用旧数据覆盖回来。最稳妥的做法是通过 API 改，或者参考 hook 路由里的写法。
2. 改训练逻辑（加重规则、1RM、训练结束写回）时，要在 `src/lib` 里对应文件旁边加单元测试。
3. 认证用的 passkey 绑定了域名 `h3.lin0.org`，而且必须走 HTTPS。不要改 `RP_ID`、`ORIGIN`、`BASE_PATH`，否则会登录不了，或者资源路径出错。
4. 前端是 PWA，有缓存。部署后如果看不到改动，先强制刷新，或者重新打开 App。
5. 改动尽量写在本地新增的文件里（比如 body-hook.js、equipment.js），少改上游核心文件，方便以后合并上游更新。
6. `.env`、token、SMTP 密码这些都不要写进代码、日志或文档。
