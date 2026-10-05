# Compact popup and Now Playing design

## 用户确认的目标

精简 Status Trio 主弹窗，宽度 284pt；外边距及模块内边距 4pt，区域间距 4pt，播放器及二级菜单共用 8pt 水平内容边距以对齐图标视觉边缘；统一复用 CompactPopupLayout.gap；内外描边均 0.7pt，避免描边厚度导致视觉间隔不同。顶端两列两行，每行 40pt：电池/Wi-Fi、蓝牙/Codex。电池副标题为 Source: Power 或 Source: Battery，蓝牙未连接为 Not connected。蓝牙采用 AppKit 自带 BluetoothTemplate；其他图标采用 SF Symbols。顶端电池、Wi-Fi、Codex 图标 14pt，蓝牙模板 16×22pt，固定 22pt 图标栏保持文字位置。

亮度和音量共用一个圆角阴影模块和静态高光描边，无分割线。胶囊与图标均 14pt，图标置于轨道外；音量图标点击静音。滑块中心到轨道两端的距离等于半径，可拖到最低及最高值。获得焦点时不显示蓝框，保留键盘与可访问性调整。最右侧及二级菜单箭头均采用 11pt semibold、secondary 色及 二级菜单横向箭头 12×24pt 视觉栏位、20×28pt 点击区域及 4pt 标题间距；主界面右箭头视觉栏位 12pt、左右对称，点击区域 20×28pt 且不覆盖滑杆，整体宽度保持 284pt，与顶端箭头对齐。底行左 Settings、右 Quit，仅显示图标，保留悬停及可访问性名称。外圆角 12pt、模块圆角 8pt 与 4pt 边距形成同心曲率，均使用 circular 曲线。文字字号保持原样，所有次级文字提高到 primary 78% 不透明度。亮度/音量图标使用同样 22pt 栏位，与电池/Wi-Fi 对齐。

## 二级菜单

音量箭头进入 Sound：滑杆、Output 设备选择、Sound Settings。亮度箭头进入 Display：内建显示器真实参考预设、亮度、Dark Mode/Night Shift/True Tone 及 Display Settings。不支持的能力禁用；读取或设置必须验证实际状态。外接 DDC 不在本次范围。Codex 主界面重置时间英文前缀为 Re:，二级菜单为 Resets；箭头进入额度和 reset 时间详情，底部 Refresh now 主动更新。每次打开弹窗时刷新；无自动刷新定时器及间隔设置，Refresh now 仅可见时执行且不重入。

## Now Playing

系统会话正在播放或暂停时可见，暂停保留卡片和播放按钮；停止、退出或撤销元数据后收起。公开系统文档未规定固定的暂停隐藏期限，不设置额外倒计时。仅单来源正在播放时创建进度 TimelineView；双来源或全部暂停时不创建。无封面，最多两个来源。固定两个 40pt 行及 4pt 中间空间：一个来源首行显示信息，第二行显示可拖进度、时间及上一首/暂停/下一首，无分割线；两个来源各占一行，仅显示信息及播放控制，中间显示分割线，不显示进度条。控制按钮 15pt。点击标题区激活经过 PID 与 bundle 验证的对应运行应用。仅来源支持 seek 且 duration 有限并大于零时可拖动，松开时提交目标位置。拖动开始时捕获来源身份；重排不会改变目标，来源消失、曲目/时长改变或取消时不提交。未知时长显示不可操作进度占位。

## 数据与低功耗

Codex 通过安装的 CLI app-server --stdio，完成 initialize 和 account/rateLimits/read，保留上次数据供刷新期间及失败时显示；不使用私钥、不创建聊天、不调用模型。子进程查询后结束，超时或关闭弹窗立即取消，缓存可标注 stale，不凭 reset 时间推断额度已恢复。

媒体采用第一方 Objective-C MediaRemote 桥接，由系统 Perl 加载动态库以获取多个客户端；只在弹窗可见时监听事件。序列化 player path 路由，通过 MRMediaRemoteGetNowPlayingPlayerForClient 获取客户端实际播放器，查询与发送前调用 MRMediaRemoteNowPlayingResolvePlayerPath，并核对 bundle、PID 和 player identifier；任何系统重定向均拒绝。不能仅使用自行构造的 defaultPlayer 占位符。重复应用身份禁用命令，防止误控。查询串行合并，有超时；正在播放时进度由唯一可见 TimelineView 每秒推算，无元数据轮询、封面读取或常驻动画。隐藏时取消媒体/额度子进程和定时任务。EOF 立即停止读取回调，避免空读 CPU 循环。

亮度、显示能力与音量按打开、设备变化和用户操作读取；拖动写入约 30Hz，最终值必须提交。CoreDisplay/CoreBrightness/MediaRemote 私有接口均动态加载并检测能力，失败时不可用。

## 验收与边界

验证数据过滤、每次打开刷新、手动刷新可见性、取消及 EOF 顺序、滑块端点、来源身份与 seek 校验、本地化、全宽点击区域；使用原生离屏渲染检查首次布局和单/双播放固定高度。隔离模拟播放器验证针对来源的 seek/pause 及歧义拒绝，不能控制用户的真实播放器作为测试。

swift test、swift build -c release 和本地 app 打包必须通过。接受环境仍为 macos-15/Xcode 16.4/Swift 6.1.2；本地新工具链不能代替 CI。合并或发布前按 AGENTS.md 执行 publish=false 预检。未授权 commit/push/PR/merge/release。

真实鼠标拖动、物理显示切换、真实浏览器与 Music 同时播放以及功耗测量仍需真机验证，离屏渲染与构建不能替代。

## 调查依据

- 本地 AppKit NSImage.h：NSImageNameBluetoothTemplate。
- https://developers.openai.com/codex/app-server ：额度窗口及 reset 字段。
- https://github.com/tatarco/glarebar/blob/main/Sources/GlareBar.swift ：CoreDisplay 预设接口，另经本地只读探测验证。
- https://saagarjha.com/blog/2018/12/01/scheduling-dark-mode/ ：Night Shift 状态结构。
- 本地 MediaRemote 运行时与反汇编：六参数 MRMediaRemoteSendCommandToPlayerWithResult、结果错误检查与客户端身份校验。


2026-10-05 后续调整：Codex 仅在每次打开弹窗或点击 Refresh now 时查询，无自动刷新定时器及间隔设置；关闭弹窗取消查询。弹窗顶部限制在菜单栏下沿及状态按钮下沿较低处（上移 1pt 后不再额外留缝），支持多屏坐标。

底栏增加独立天气、日期和时间框，与两侧 Settings/Quit 同为 24pt 高，框间距 4pt，中间三个框共享剩余宽度。日期与时间使用系统时区，时间按分钟更新且仅在主弹窗存在时运行。天气城市在设置中填写，默认不假定城市；天气框点击打开设置。Open-Meteo 地理编码支持 City, ISO-country-code，查询当前温度、天气码及昼夜。仅打开时检查 15 分钟缓存；无后台轮询，关闭立即取消。请求失败清除温度显示，未知天气显示问号；设置含来源链接，悬停及无障碍名称含城市、天气状况、温度及来源。

日期框为 M/d 加星期缩写，中文使用周一至周日；日期和星期共用系统时区。时间格式可在设置切换 12/24 小时制，默认 24 小时；12 小时采用小写 am/pm。底栏天气 52pt、时间 64pt，日期分配剩余宽度，保持 24pt 高度。

### 最新天气与时钟调整

天气改用系统快捷指令 `Status Trio Weather` 调用 Apple 天气（当前位置已授权），仅弹窗可见时按 15 分钟缓存获取，无常驻轮询。设置可编辑快捷指令名称并打开该指令。点击天气进入独立二级菜单，展示温度、原始天气状况、来源和更新时间；底部打开系统 Weather.app。日期为 `5/Oct` 加星期；12 小时制省略 am/pm。上述内容取代此前 Open-Meteo/手动城市方案。

### 详细天气预报按需加载

主天气 `Status Trio Weather` 只获取当前天气。详细预报单独调用 `Status Trio Weather Forecast`（设置天气指令名后追加 ` Forecast`），仅进入天气二级菜单时触发，每次成功获取缓存15分钟；返回或关闭弹窗立即取消请求。二级菜单显示当天 Low/High 和横向滚动的24小时预报，每小时显示时间、动态图标和温度。主弹窗打开与后台不触发预报查询。

## 内置天气快捷指令与详情布局

两份经 Apple 验证的 `.shortcut` 随 SwiftPM 资源一起打包，首次启动打开基础设置提供分别添加入口；仍由 macOS 确认添加和位置授权，不使用安装脚本静默授权。设置和天气不可用页面均能打开内置文件。主指令只取当前天气，Forecast 指令额外输出 LOCATION 城市字段，详情标题右侧显示城市，删除 Source 行。小时预报使用系统原生横向 ScrollView，支持触控板两指左右滑动，仍仅在详情可见时按需获取。

音频设置提供持久化的“滚动调节音量”开关，默认关闭；关闭后音量滚动监视器透传事件并清空滚动会话。天气预报不再使用鼠标按住拖动或将纵向滚动映射为横向。
