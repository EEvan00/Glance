# Glance 产品身份实施计划

目标：将现有定制版整理为独立的 Glance 本地产品，保留 Apache 2.0 和第三方声明。

- [x] 更新 Info.plist、所有语言的应用名称、菜单栏辅助功能名称和默认名称。
- [x] 使用作者确认的独立 Bundle ID、项目地址和维护者署名；保持内部 SwiftPM 模块名以减小风险。
- [x] 按用户要求沿用原项目图标，关于页明确说明基于 Status Trio，分发 App 包含 LICENSE 和 NOTICE。
- [x] 更新打包/发布配置与 README；未配置自己的 Sparkle 密钥和地址前关闭自动更新。
- [x] 使用 Glance Weather / Glance Weather Forecast 固定内置名称，隐藏设置输入框，确保两份签名资源均在源码和 App 中。
- [x] 测试元数据、独立实例标识和全部回归；release 构建、App 包元数据及资源检查、只重启本地实例。

限制：不提交、推送、创建仓库或发布 Release，除非用户明确授权；本地新工具链不能替代 Swift 6.1 CI。改动的源文件注明 Glance 修改，原版权保留。

验证：365 XCTest + 14 Swift Testing 通过；release 本地构建通过，Info.plist、原图标、LICENSE/NOTICE 和双天气资源已检查；独立 Glance 已启动。原有内部 SwiftPM 名称和天气指令按用户后续要求统一改为 Glance。原图标按用户最新要求保留，不宣称为 Glance 原创。CUA 设置界面检查超时，未将其当作真实界面验证。未创建仓库、提交、推送或发布；CI 仍待发布前执行。

2026-10-06：用户授权创建私有 EEvan00/Glance 仓库并提交、推送。仓库已创建且确认私有，About 的仓库入口已启用。后续通过 publish=false 工作流验证 Swift 6.1；不发布 Release。
