# iOS 喝水页固定布局整改交接 · 2026-10-26

已实际修改独立喝水页，移除页面级纵向 ScrollView。**仅完成源码和静态检查，未完成 Swift 类型检查、Xcode 构建或真机“不滚动且完整可见”验收。** 本轮不执行任何 Git 写操作，交由总控统一整合和提交。

## 精确交付范围

1. 修改：`frontend/ios/App/App/Native/WaterView.swift`。
2. 新增：`docs/dev/IOS_WATER_REFINEMENT_2026-10-26.md`（本文）。

起始 HEAD：`ac83d8bb16eec39d1cf87bdad9519557e0997c7c`；开始时 WaterView.swift 没有 staged/unstaged diff。未发现仓库内、D:/、D:/其他项目/ 或工作区根目录适用的 AGENTS.md。

共享 checkout 已有其他 staged/unstaged 修改。本轮未写 TodayView.swift、RootView.swift、BodyView、PlanView、数据模型、Store、同步、Xcode 工程或 Package.swift；未修改旧的 2026-10-23 检查报告。开始和检查后，真实索引中均为以下五个 API 路径，本轮没有 add、commit、push、pull、reset、stash、clean 或切换分支：

- `api/Dockerfile`
- `api/server.js`
- `api/test/server-admin-delete.test.js`
- `api/test/workout-sync-events.test.js`
- `api/workout-sync-events.js`

## 原因与修复

此前已移除“最近记录”卡片，但 WaterView 中仍有外层默认纵向 ScrollView；内容 VStack 还有 `minHeight: geometry.size.height`，普通字号的快捷操作又放在本页额外的底部 safeAreaInset 内。大字号时则把快捷操作移回纵向 ScrollView。因此页面仍拥有纵向滚动和回弹容器。

现在 GeometryReader 直接承载固定布局；前景遵循 NavigationStack 和父级 Tab 提供的可用安全区域。本页没有前景 ignoresSafeArea、固定设备高度或裁切；只有复用的 WaterBackground 负责原有的全屏水面。移除本页第二层快捷操作 safeAreaInset，让摘要、服用提醒和快捷操作共同参与当前安全区内的布局选择。

### 自适应与保留的操作

| 场景 | 实现 |
| --- | --- |
| 普通竖屏 | 完整摘要、服用提醒与快捷操作放在一个固定 VStack 中；Spacer 只分配剩余空间。饮品和杯量仍横向选择 |
| 较短的竖屏 / 字号导致内容变高 | ViewThatFits 按完整内容高度选择紧凑布局；摘要数字缩为 44 pt 上限，减少重复标题与空白。目标、完成率、剩余量或未设目标刻度仍显示 |
| 紧凑快捷区 | 饮品改成图标与名称同排的横向条；杯量改用系统 Menu + Picker，全部原有预设和设置杯量仍可选。保留记录、自定义、成功反馈及撤销 |
| 操作按钮横向不足 | ViewThatFits 把操作区分成两行，避免把主记录按钮挤到不可用宽度 |
| 矮而宽的安全区域 | 宽高比超过 1.35 时使用左右两栏，左侧摘要/服用，右侧快捷操作，避免把整个页面堆成一列 |
| 记录、自定义和撤销 | 原来的 addWater / removeWater 及成功触感机制保留；紧凑图标按钮有完整 VoiceOver 名称，记录按钮读出所选饮品与毫升数 |

没有使用 scrollDisabled、拖拽手势拦截、全局 UIScrollView appearance、负 padding、裁切或强制前景越过安全区。页面中剩余的两个 ScrollView 均显式为 horizontal；只在它们各自设置横向 basedOnSize 回弹。没有重新加入任何信息卡片背景或最近记录卡片。

历史、补记/编辑、自定义和服用面板的原生 List / Form 与内部必要滚动继续保留。通过与起始 HEAD 逐字比较（仅统一换行），从 `private extension DrinkKind` 到文件末尾的饮品图标映射、WaterRecordRow、WaterHistorySheet、WaterEntrySheet、DoseSheet 均未修改。

## 已执行验证

1. 通过现有 Python 与临时 tree-sitter / openstep-parser 依赖，对实际 WaterView.swift 解析所有 ERROR / missing 节点，读取当前 Xcode Sources Build Phase，并只读比较起始 HEAD 的弹窗代码。结果：

   ```json
   {
     "scope": "Swift syntax, build membership and source comparison only; no Swift typecheck or iOS runtime",
     "syntax_errors": [],
     "WaterView_in_build_sources": true,
     "history_entry_and_dose_sheets_unchanged": true,
     "scroll_axes_found_in_WaterView": [".horizontal", ".horizontal"],
     "page_has_default_vertical_ScrollView": false,
     "page_has_gesture_or_scroll_disabling_override": false,
     "page_has_clipping_or_safe_area_bypass": false,
     "sha256": "8e9e0180864f81975caa249a9ae69a66c9be63397f2aea36d4777ed36468cdbd"
   }
   ```

2. `git -c core.autocrlf=false diff --check -- frontend/ios/App/App/Native/WaterView.swift`：退出码 0。
3. 只读核对 `git diff --cached --name-only`：仍是上述五个原有 API 暂存路径。
4. 当前 Windows PATH 中未找到 swift / xcodebuild。未新增用于模拟 SwiftUI 像素布局的替代测试，未运行 XCTest。

以上是源码结构与语法证据，**不能当作修复后真机无纵向回弹、布局不遮挡、横滑和点击已通过**。

## 总控整合后的待验收项

必须与首页对话当前 RootView / 底部 Tab 改动一起，在 Mac/Xcode 完成类型检查、模拟器构建并运行。重点覆盖：

- 小屏竖屏（例如 320×568、375×667）、常用全面屏、横屏和 iPad 窗口；分别看空记录、无目标、有目标、超目标、有/无服用计划，以及刚记录后新增反馈/撤销的高度变化。
- 页面空白、水面、摘要及提醒区域上下拖动：页面不纵向移动或回弹。
- 饮品横滑、普通布局的杯量横滑、紧凑布局杯量菜单、记录、自定义、撤销均可用；核对当前选择、真实存储、水位和返回后的状态。
- 顶部导航栏、刘海/灵动岛及总控新 Tab 栏与本页内容没有重叠；记录按钮和最末操作完整可见。
- 常规及各级无障碍字体、长金额/饮水量文本、VoiceOver、明暗模式。ViewThatFits 的最终回退项仍需实际测量，**未宣称任意极端窗口与最大字号组合都已验收通过**；若出现内容高度仍超出安全区，继续改用完整控件重排，不能恢复页面滚动或用裁切掩盖。
- 历史日期选择、历史列表滚动、编辑/删除、补记时间选择、服用列表确认/撤销等弹窗内部交互保持正常。

没有生成修复后 iOS 截图，没有打包、安装或发布。总控可直接审查上述两个文件并统一 Git 交付。
