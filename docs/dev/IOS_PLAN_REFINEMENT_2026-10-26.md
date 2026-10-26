# iOS 计划页整改交接 · 2026-10-26

本轮已实际修改计划页源码，处理动作之间的空白行，并按最新要求改为默认收起。**尚未进行 Swift 类型检查、Xcode 构建或修复后的 iPhone 视觉/交互验证，不标记为真机验收通过。** Git 交付由总控统一处理，本轮没有执行 add、commit、push、pull、reset、stash、clean 或切换分支。

## 交付范围与现场

- 修改：`frontend/ios/App/App/Native/PlanView.swift`。
- 新增：本交接文档 `docs/dev/IOS_PLAN_REFINEMENT_2026-10-26.md`。
- 起始 HEAD：`ac83d8bb16eec39d1cf87bdad9519557e0997c7c`；开始时计划页没有本地 diff。
- 未发现仓库内或 `D:/`、`D:/其他项目/`、工作区根目录适用的 `AGENTS.md`。
- 共享 checkout 已有其他 staged/unstaged 工作。本轮仅写上述两个文件，没有修改 TodayView、RootView、Store、同步、模型或 Xcode 工程。
- 开始及修改后只读核对的已有暂存路径均为：`api/Dockerfile`、`api/server.js`、`api/test/server-admin-delete.test.js`、`api/test/workout-sync-events.test.js`、`api/workout-sync-events.js`。未操作这些路径或真实索引。

## 已查看的截图与原因

本轮已通过图像工具实际查看以下两张用户截图，均为修复前证据：

1. `C:/Users/win11/AppData/Local/Temp/codex-clipboard-0dfcaa0e-c49b-461b-9eb4-641ff745d72c.png`：周历下的“全身力量 A”展开，跑步机步行与下一动作之间有异常空白块。
2. `C:/Users/win11/AppData/Local/Temp/codex-clipboard-389c4d8a-5fd1-46a0-ba01-ee8e58f1d53d.png`：滚动后的多个相邻动作之间均出现两道线夹着空白行的重复结构。

原因在 `DisclosureGroup` 内的动作 `ForEach`：每次循环同时输出 `PlanExerciseDetail(...)` 和一个独立的 `Divider()`。它们直接处于 SwiftUI `List` 的行内容中，分隔器因此也占据一个列表行，获得系统列表行的最小高度及行分隔；截图中的空白块对应这条额外行，并非缺失动作。

修复移除作为独立行的 `Divider()`，在真实动作行上使用 `.listRowSeparator(.visible, edges: .bottom)`。每个动作只生成一行，正常分隔由系统列表提供。动作行原有上下各 8 点的 padding 与详情内部 6 点间距保留；未使用负间距、固定高度裁切、隐藏空字符串或删减动作/备注来掩盖问题。`PlanExerciseDetail` 整段代码与起始版本逐字比较（仅统一换行）一致。

## 默认收起与状态行为

旧逻辑使用“已收起 ID 集合”，空集合配合取反判断会让全部计划默认展开，新同步的 ID 也会展开。现改为“用户已展开 ID 集合” `expandedRoutines`，初始为空，只有 DisclosureGroup 的用户交互能添加 ID。

| 场景 | 当前实现的状态规则（源码核对，尚非真机测试） |
| --- | --- |
| 首次打开 / 页面重新创建 | 空集合，所有计划收起 |
| 从其他 Tab 或训练入口切回计划页 | 监听 `store.tab` 变为 `.plan`，清空集合，所有计划收起 |
| 手动展开一个计划 | 仅把该 ID 加入集合，其他计划不展开 |
| 手动收起 | 移除该 ID，可继续反复展开和收起 |
| 原有计划名称、动作或备注刷新 | 不添加展开 ID，保留该次访问内的用户选择 |
| 新增、同步新增、重排计划 | 对展开集合与现有 ID 做交集；新 ID 默认收起，幸存计划保留手动状态 |
| 删除后重新出现的 ID | 删除时从集合清除，重新出现不会自动展开 |
| 从计划编辑器返回，未切换 Tab | 不重置该次访问内的手动选择 |

本次新要求覆盖 2026-10-23 的“默认展开”要求，没有更改数据模型或持久化格式，也没有保存新的用户设置。

## 已执行验证

1. `git diff --check -- frontend/ios/App/App/Native/PlanView.swift`
   - 退出码 0，无 whitespace 错误。Git 的 LF/CRLF 提示不代表构建结果。
2. `uv run --no-project --with tree-sitter==0.26.0 --with tree-sitter-swift==0.7.4 --with openstep-parser==2.0.3 python -`
   - 通过临时标准输入脚本解析实际修改后的 Swift 文件，遍历 ERROR/missing 节点；读取当前 pbxproj 的 Sources Build Phase；只读取得起始提交中的计划页，比较动作详情整段代码。
   - 退出码 0，实际输出：

   ```json
   {
     "scope": "Swift syntax, Xcode source registration, and unchanged exercise-detail source ONLY; no Swift typecheck or iOS runtime",
     "syntax_errors": [],
     "PlanView_in_build_sources": true,
     "exercise_detail_source_unchanged": true,
     "sha256": "39811e8ff790452677cc5ccb88392113c62643f57054f9d7fadf117cf6d452d9"
   }
   ```

3. `git diff -- frontend/ios/App/App/Native/PlanView.swift`：核对修改仅涉及行分隔与展开状态；所有真实动作仍由完整 `routine.exercises` 遍历，编辑入口与动作详情保留。
4. `git diff --cached --name-only`：已有五个 API 暂存路径不变，本轮文件未暂存。
5. `Get-Command swift,xcodebuild,uv -ErrorAction SilentlyContinue`：仅找到 `uv`，当前 Windows PATH 中没有 Swift 或 Xcode。

未新增模拟 SwiftUI 布局的替代测试；上述语法/结构检查不能证明列表的实际像素高度和原生生命周期行为。

## 总控后续验证

在总控整合本轮与首页/Tab 修改后，使用 Mac/Xcode 构建并安装到 iPhone，至少检查：

1. 首次进入、切到其他 Tab 再回来、从训练入口回来，所有计划默认收起。
2. 分别手动展开/收起多个计划；进入编辑器再返回，交互可用。
3. 展开截图中的“全身力量 A”，确认跑步机步行、杠杆腿屈伸、杠杆上斜胸推等动作之间只有正常分隔，无额外空行或竖线。
4. 对照真实数据核对动作数量、顺序、名称、参数、起始参考重量和完整备注；长备注、大字体、明暗模式下不截断。
5. 计划页停留时触发真实数据刷新/新增计划，新计划保持收起，已手动展开的现存计划不被自动全部展开或折叠。
6. 保留无动作计划提示、编辑计划入口和删除确认；与总控本次底部 Tab 修复一起核对滚动及底部可见区域。

本轮没有生成修复后运行截图，没有打包、安装、部署或发布；由总控统一审查和 Git 交付。
