# Lin Gym：GitHub Actions → TestFlight 内部测试

## 首次发布验证（2026-11-05）

- 开发团队、Distribution 证书/P12、两个描述文件、App Store Connect API Key 和个人同步 Secret 均已配置。
- 主应用 `org.lin0.lingym`，小组件 `org.lin0.lingym.widgets`，共享组 `group.org.lin0.lingym`。
- [首次成功发布任务](https://github.com/buyun00/openGym/actions/runs/41958660791)：版本 **1.0.0 (9.1)**，54 项 Swift 核心测试及 6 项签名配置测试通过，签名归档、IPA 导出和 Apple 上传成功。
- 首次上传因缺少 `NSHealthUpdateUsageDescription` 被拒，已补充符合当前只读 HealthKit 行为的说明，重建后上传通过。
- 上传成功不代表处理完成或真机验收通过。需在 TestFlight 确认 Apple 处理/出口合规状态，将构建加入 Personal 内部测试组，再接受邀请安装。

此流程服务于当前个人版 Lin Gym。应用内包含个人数据同步凭据，只把你自己的账号加入内部测试组。导出启用 `testFlightInternalTestingOnly`，不支持外部测试或直接提交正式商店；将来开放给别人前，需要改为每人独立登录。

## 已配置的自动化

- 工作流：`.github/workflows/ios-testflight.yml`，GitHub Actions 中名称为 **iOS TestFlight**。
- `main` 的相关代码提交：直接打包、签名上传并等待内部测试分发，由用户在真机验收。发布工作流不运行核心、签名辅助程序或模拟器自动测试。PR 仅未签名编译，不发布。
- 手动 Run workflow：默认只检查；勾选 `upload` 才签名上传。`version` 可填 `1.0.0`，留空保留工程版本。
- 推送 `ios-v1.0.0` 形式标签：自动签名上传。不要在配置好凭据前创建发布标签。
- 主应用与 Widget 的构建号统一采用 `GitHub run number.attempt`，重跑也会递增。以后重命名/重建工作流时，要保证构建号高于 App Store Connect 已有版本。
- 签名按 target 分别指定，不把描述文件应用到 Pods。检查团队、Bundle ID、有效期、分发类型、HealthKit、App Group。
- 不上传 IPA/Archive 为 GitHub 附件，以免复制个人同步配置；GitHub 日志不打印该配置。临时签名材料在结束时清理。
- 工作流上传后继续通过 Apple API 等待准确版本号和构建号，验证处理通过、出口合规状态和 `Personal` 内部组归属；必要时自动把构建加入现有组。不创建或邀请测试员。最多等待 30 分钟，超时会报出最后状态；此时不能把任务失败等同于上传失败，应先检查 Apple 后台。
- `Info.plist` 已声明 `ITSAppUsesNonExemptEncryption=false`：当前使用系统 HTTPS/钥匙串，不包含非豁免加密功能。若未来引入其他加密实现，需重新核对声明。

## 1. 确认会员

打开 <https://developer.apple.com/account/>，在 Membership details 确认 Apple Developer Program 已激活，接受待签协议，记下 **Team ID**（10 位）。不需要提供 Apple ID 密码或验证码给工作流。

## 2. 创建 App Group 和两个 App ID

进入 **Certificates, Identifiers & Profiles → Identifiers → +**。

1. 选择 **App Groups**，Description 填 `Lin Gym Shared`，Identifier 填 `group.org.lin0.lingym`，注册。
2. 再点 +，选择 **App IDs → App**，Description 填 `Lin Gym`，Explicit Bundle ID 填 `org.lin0.lingym`。
3. 勾选 **HealthKit** 和 **App Groups**，注册后进入该 App ID 的 App Groups 配置，关联刚创建的组并保存。当前只使用普通 HealthKit，不启用 Clinical Health Records。
4. 再创建一个 App ID：Description `Lin Gym Widgets`，Explicit Bundle ID `org.lin0.lingym.widgets`；勾选 App Groups，关联同一组。

若提示标识已占用，先核对是不是当前团队已有条目；不要随意改一个值继续。工程、描述文件、Swift 共享容器和工作流需要一起调整。

## 3. 创建 Apple Distribution 证书

1. 在本地生成私钥和 CSR（证书签名请求）；私钥必须保留且不能提交 Git。CSR 可以上传 Apple。
2. **Certificates → + → Software → Apple Distribution**，Continue，上传 CSR，生成并下载 `.cer`。
3. 使用对应私钥把 `.cer` 合并为带密码的 `.p12`。不要求你拥有 Mac；Windows 的 OpenSSL 也可以完成这两步。
4. 后续交给本机脚本转换成 Base64 并写入 GitHub Secret，不要把私钥、P12 密码或 API 私钥粘贴到聊天中。

注意选择 Apple Distribution，不是 Apple Development、Developer ID Application 或 APNs 证书。

## 4. 创建两份分发描述文件

**Profiles → + → Distribution → App Store Connect**（旧界面可能叫 App Store）。

1. 主应用：选择 `org.lin0.lingym` → 选择刚创建的 Apple Distribution 证书 → 名称 `Lin Gym AppStore` → Generate → Download。
2. 小组件：重复上述流程，App ID 选择 `org.lin0.lingym.widgets` → 同一证书 → 名称 `Lin Gym Widgets AppStore` → Download。

两份都是 `.mobileprovision`。TestFlight 不需要登记手机 UDID。修改能力后必须重新生成描述文件。

## 5. 创建 App Store Connect 应用

打开 <https://appstoreconnect.apple.com/> → **Apps → + → New App**。

- Platforms：iOS。
- Name：`Lin Gym`（如果重名，需要另外选择可用名称）。
- Primary Language：Simplified Chinese。
- Bundle ID：`org.lin0.lingym`。
- SKU：例如 `opengym-ios-001`（自定义内部编号）。
- User Access：按个人账号默认设置。

这里只创建主应用一条记录；Widget 随主应用上传，不单独建立商店应用。

## 6. 创建自动上传 API Key

**Users and Access → Integrations → App Store Connect API → Team Keys**。

1. 若首次使用显示 Request Access，由 Account Holder 申请 API 访问。
2. 创建 `Lin Gym GitHub Upload`，选择 **Developer** 角色（上传所需权限；创建应用、组和邀请在后台手动完成）。
3. 下载 `.p8` 私钥（通常只能下载一次），记下 **Key ID** 和 **Issuer ID**。

API Key 用于上传；它不能代替前面的 Distribution 签名证书。

## 7. 配置 GitHub

仓库 Settings → **Secrets and variables → Actions**。

Variables 页添加：

| 名称 | 内容 |
|---|---|
| `APPLE_TEAM_ID` | 第 1 步的 Team ID |

Secrets 页添加：

| 名称 | 内容 |
|---|---|
| `IOS_DISTRIBUTION_P12_BASE64` | P12 文件字节的 Base64 |
| `IOS_DISTRIBUTION_P12_PASSWORD` | P12 导出密码 |
| `IOS_APP_PROFILE_BASE64` | 主应用描述文件字节的 Base64 |
| `IOS_WIDGET_PROFILE_BASE64` | Widget 描述文件字节的 Base64 |
| `ASC_KEY_ID` | API Key ID |
| `ASC_ISSUER_ID` | API Issuer ID |
| `ASC_PRIVATE_KEY` | `.p8` 完整文本，含 BEGIN/END 行及真实换行 |
| `IOS_PERSONAL_CONNECTION_JSON` | 现有个人同步配置完整 JSON，由本机安全读取写入 |

可用 `gh secret set NAME --repo buyun00/openGym` 从标准输入写入，避免在命令参数或输出中展示秘密。证书、描述文件、会员到期后需要续期/替换配置。

## 8. 首次上传和安装

1. Actions → **iOS TestFlight** → Run workflow → branch `main` → 勾选 upload → version 填 `1.0.0`。
2. 等流程完成。到 App Store Connect → Lin Gym → TestFlight 等 Apple 处理完成。
3. 如显示 Missing Compliance，按真实加密使用情况回答出口合规问题；流程未擅自声明应用不使用非豁免加密。
4. TestFlight → Internal Testing → +，创建 `Personal` 组，打开自动分发，添加你自己的开发者账号，并添加首次构建。
5. iPhone 安装 Apple 的 TestFlight，接受邀请，安装 Lin Gym，按需开启自动更新。当前工程要求 iOS 26 或更高。
6. 真机检查：首次启动、个人数据同步、训练完成、HealthKit 授权及数据读取、小组件和 Live Activity。

若上传构建时还没有测试组，创建组后手动加入该构建；后续自动分发。每个构建有效期 90 天。内部测试不等于 App Store 上架，也不等于业务/真机验收完成。

## 日常更新

修改代码 → 推送 main → 自动打包、签名上传 → 等待 Apple 处理及 Personal 组分发 → TestFlight 更新并真机验收。手机可开启 TestFlight 自动更新，实际下载/安装时机由 iOS 控制，CI 不能保证立即安装。服务端部署不属于此工作流。

## 官方资料

- [GitHub macOS 签名配置](https://docs.github.com/en/enterprise-cloud%40latest/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [Apple 分发描述文件](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/)
- [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
- [上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [添加内部测试员](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)
