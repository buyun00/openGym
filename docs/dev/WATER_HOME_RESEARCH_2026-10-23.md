# 原生首页水体设计与实施交接

用户已批准实施；2026-10-23 调研。新对话模型要求 gpt-6-astra / max。

## 已确定的设计

参考图：`water-home-approved-2026-10-23.png`，与本文同目录。是用户认可的概念图，非运行证据，数据为示例。

- 整页透明青蓝水体背景，水位表示今天饮水量 / 用户设置目标；不采用局部水景卡片。
- 首页只有：今天练什么、今天饮水目标/进度、今天服用目标。
- 删除首页本周/日期选择、体重卡片和手动称重入口、重复的训练开始按钮。保留其它页面体重功能。训练内容只读，开始训练通过现有底部“开始”。
- 饮水为视觉中心：大字当前 mL、目标/百分比、+250 mL（可配置杯量）与自定义，记录可撤销/修正，数据持久化、跨日正确归档。
- 维生素 B 用户提供频率每天三次，D 每周一次。时点/星期可配置；按服用实例记录，不能重复累计；不得把示例完成状态或剂量写为真实用户数据。首页显示今日待办和完成情况，D 非计划日不伪造今日目标。提醒和饮水记录分别确认。
- 所有交互控件使用苹果原生 SwiftUI：系统 TabView/Tab、导航、按钮、表单、弹窗、系统 Liquid Glass。不得用自绘 Tab 栏或 WebView 仿制。水体是背景渲染内容，可使用苹果 Metal/Core Motion。
- 用户最初还提出饮水/服用本地提醒和桌面快捷记录小组件；保留这项产品需求，优先完成这次明确批准的首页及其真实记录链路，明确汇报提醒/WidgetKit 的完成边界，不把静态卡片算整套功能完成。

## 当前源码事实

`frontend/ios/App/App/Native/TodayView.swift` 是 SwiftUI 首页；`RootView.swift` 已用系统 TabView，五栏 今天/计划/开始/身体/喝水。`GymStore.swift` 是现有状态/持久化入口。`WaterView.swift` 目前占位。
`assets/screenshots/home.png` 是另一套旧 Web 首页，不能当作当前原生截图。根 CLAUDE.md 仍主要描述 PWA，实施时以当前原生入口为准并检查本地适用指令。
本交接建立前 git status --short 无输出。用户另有上传工作正在进行，不能打断上传或擅自发布新包。继续同一 checkout，先复查当前工作区，保护并发修改；无提交、推送、上传、部署授权。

## 开源候选与证据

已查看上游 README / GitHub 元数据，部分源码和许可证。尚未在 iPhone 或 Xcode 运行，以下不是性能验收。

| 项目 | 核实能力与许可证 | 适用结论 |
| --- | --- | --- |
| [Inferno](https://github.com/twostraws/Inferno) | SwiftUI Metal shaders；读过 `Sources/Inferno/Shaders/Transformation/Water.metal`，本质是 sin/cos 像素位移，非流体求解器。LICENSE 正文 MIT（API 标为 NOASSERTION，已读原文澄清）。调研时约 2930 stars，最近 push 2026-05-17。 | 优先复用水纹/折射基础，按需引入文件并保留许可证；单独使用不能实现漂亮的体积水和重力晃动。 |
| [Wave](https://github.com/jtrivedi/Wave) | MIT，可打断弹簧动画、数值驱动，无外部依赖，兼容 SwiftUI/UIKit。约 2402 stars，最近 push 2026-03-25。 | 水位过渡、倾角惯性和阻尼的候选；名字 Wave 不代表它是水模拟器。 |
| [SwiftUIShaders](https://github.com/krispuckett/SwiftUIShaders) | MIT，含 `bcsUnderwaterCaustics`；Package.swift 核实 iOS17+、Metal shader bundle。约 344 stars、8 commits，最近 push 2026-09-30。 | 水下焦散光纹候选，视觉匹配概念图；采用前读具体 shader、核实源头授权及 GPU 成本，成熟度不能与 Inferno 混为一谈。 |
| [Foil Shaders](https://github.com/reidbarber/foil-shaders) | Apache-2.0（含 Paper Shaders attribution），SwiftUI/Metal Water 效果，0.7.0、明确 alpha；有减少动态/离屏暂停、视觉对照测试。Package.swift 要 Swift6，声明 iOS15+。 | 备选，明确 alpha 和构建插件成本，精确锁定版本，保留 THIRD_PARTY_NOTICES；不是默认成熟主方案。 |
| [Liquid](https://github.com/maustinstar/liquid) | MIT，SwiftUI 流动有机形状背景，约 856 stars，最近 push 2024-08-19。 | 不是容器内水位/焦散/重力水体，本次不选。 |
| [WebGL Water](https://github.com/evanw/webgl-water) | WebGL 水体演示，仓库 API 没识别出 license、根目录未见许可证。 | 仅效果参考，不直接复制未知授权代码，不嵌 WebView 代替原生实现。 |

没有发现已经核实的、可直接满足全部需求的成熟一体化 SwiftUI 水体组件。建议组合成熟 shader / 动画基础与薄层 Core Motion 适配，不从零硬写完整流体引擎，也不能把简单正弦平面冒充完成的物理效果。最终选择以实际小样为准，避免为了复用装入多个无用大依赖。

## 官方资料

- [Core Motion processed device motion](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data)：gravity / userAcceleration / attitude；离开页面与进入后台停止采样。
- [Gravity vector](https://developer.apple.com/documentation/coremotion/cmdevicemotion/gravity)：设备参考系的重力向量，需映射界面坐标。
- [SwiftUI Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)：用系统组件和材质，避免把所有内容卡片都做成多层玻璃。
- [Local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [Interactive widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)

## 实施和验收重点

1. 先打开认可效果图，再检查原生工程实际部署目标/构建环境/现有上传工作。读取源文件和可用 Xcode/Mac 构建路径，Windows 不能冒称完成 iOS 编译。
2. 做真实原生水体小样，再集成首页：清透青蓝、可见弯月面高光、轻柔焦散、重力方向正确、停下有衰减回荡、加水有平滑上涨。不是整张背景图平移/旋转，不让文字和控件一起扭曲。
3. 水体背景延伸至原生 Tab 栏背后以产生系统材质透色；检查真实原生材质呈现，不用概念图冒充运行结果。
4. 体积/水位应随进度正确变化；0/25/50/75/100% 与超过目标、倾斜时无漏白/越界、不凭空改变体积；减少动态、降低透明度、低电量、无传感器和后台提供合理降级。控制运动采样和 GPU 动画，仅页面可见时启用。
5. 数据迁移不能破坏已有训练/体重。验证饮水追加/撤销/重启/跨日、服用实例去重及周计划。时间和通知权限按真实状态呈现，不把未授权提醒说成开启。
6. 真实截图/视频验证布局、动态字体、深浅色、原生 Tab、倾斜回荡；在可用真机检查帧率/发热/耗电。没有真机或 Mac 证据必须明确未验证项，不得把静态检查/生成图标为通过。
7. 当前任务已授权制作，不要再次询问是否可以开始。完成可完成的实施并汇报实际验证边界，暂不擅自提交/上传/发布。
