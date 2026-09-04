<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>



<div align="center">
    <h1> PiliMax </h1>
<div align="center">
    
</div>
    <p> PiliPlus 第三方 Fork 自用版本，大部分修改针对 Android 平台 <p>
    <p> 其他平台构建时也会顺便一起构建，大概率有 BUG ，如有需要请自行 Fork 后修改编译 </p>

<img src="assets/screenshots/510shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/174shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/850shots_so.png" width="32%" alt="home" />
<br/>
<img src="assets/screenshots/main_screen.png" width="96%" alt="home" />
<br/>
</div>


<br/>

## 项目说明
- 本项目 PiliMax 是基于上游项目 PiliPlus 及 PiliNara 的个人自用版本，保留主要功能并进行了一些自用优化和调整。
- 本项目大部分修改针对 Android 平台，其他平台也会顺便一起构建，但是大概率有 BUG ，需自行测试。
- 本项目仅供个人学习和测试使用，如有需要请自行 Fork 后修改编译。
- 本项目会按需同步上游更新，并在此基础上进行修改和优化。

在此致敬原项目作者和上游项目作者的无私奉献。

# 近期改动
## 本项目特性(修改)

- [x] 自动缓存清理：新增自动清理缓存功能，支持周期可选。
- [x] 动态页体验优化：优化 UP 主切换与滑动流畅度；新增动态文本关键词过滤。
- [x] 内容过滤强化：完善过滤豁免规则与屏蔽优先级，调整首页推荐流默认行为。
- [x] 应用内悬浮小窗：新增应用内悬浮小窗播放服务；修复小窗播放状态不一致。
- [x] 新增听视频模式：优化页面切换的播放衔接，修复听视频进度不同步问题。
- [x] 播放体验优化：手动切集自动显示播放控件；优化长按预览弹窗与封面信息展示。
- [x] 交互细节打磨：图片长按菜单新增复制图片；评论、动态发送的风控提示优化。
- [x] 页面恢复机制优化：新增 Android 后台被杀后的单页面恢复能力。
- [x] 多场景返回适配：优化预测性返回手势，覆盖评论区、回复详情、预览弹窗等。
- [x] 本地存储升级：读写更优秀，版本升级自动迁移旧数据，异常时可自动恢复。
- [x] 视频卡片展开动画：统一卡片展开与骨架入场进度，过渡更流畅。
- [x] 直播能力增强：优化直播间仅音频与画面切换体验。
- [x] 崩溃捕获与历史：优化错误日志的报告输出。
- [x] 剪贴板视频链接：优化剪切板视频链接的识别与跳转。
- [x] 图片浏览适配：动态图片网格限宽适配宽屏，操作菜单将“保存图片”置顶。
- [x] 图片卡片展开动画：图片卡片展开入场进度，过渡更流畅。
- [x] 图片手势增强：新增双指缩放旋转、松手回正，优化横向拖动与展开动画。
- [x] 自定义字体：支持导入、移除字体文件并持久保存，界面、弹幕字体可分设并调字重。
- [x] 离线下载优化：扩展下载入口，优化队列调度与异常恢复，菜单可复制缓存路径。
- [x] 关注与搜索：关注搜索支持输入联想并清理空状态；搜索结果按账号区分。
- [x] 网络解码策略：Wi-Fi 与移动网络可分别设置首选解码格式。
- [x] 播放兜底：解码失败自动换方式并保留进度，WebDAV 配置变更后自动重连。
- [x] 动态细节：分享链接改用新版格式，修复游戏动态解析及刷新、红点不同步问题。
- [x] 文章细节：表情可直接复制原始文字，抽奖入口补充图标与结果页跳转。
- [x] 弹幕"+1"：点击弹幕"+1"可以发送该弹幕
- [ ] 其他，等等...


<br/>

## 下载

可以通过右侧 [releases](https://github.com/ekmope/PiliMax/releases) 进行下载或拉取代码到本地进行编译

<br/>

## 声明

此项目（PiliMax）是个人为了兴趣而开发，仅用于学习和测试，请于下载后 24 小时内删除。
所用 API 皆从官方网站收集，不提供任何破解内容。
- 在此致敬原作者：[guozhigq/pilipala](https://github.com/guozhigq/pilipala)
- 在此致敬上游作者：[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)
- 在此致敬上游作者：[bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)
- 在此致敬上游作者：[Starfallan/PiliNara](https://github.com/Starfallan/PiliNara)
- 在此致敬上游作者：[staoran/PiliPlus](https://github.com/staoran/PiliPlus)
- 在此致敬上游作者：[Chloemlla/PiliPlus](https://github.com/Chloemlla/PiliPlus/)
- 本仓库在前作的基础上做了一些自用修改，感谢原作者及其它作者的开源精神。

感谢您的支持及使用。
如有侵权请联系 [ekmope@163.com](mailto:ekmope@163.com) 删除。


<br/>

## 致谢

- [bilibili-API-collect] (https://github.com/SocialSisterYi/bilibili-API-collect)
- [flutter_meedu_videoplayer] (https://github.com/zezo357/flutter_meedu_videoplayer)
- [media-kit] (https://github.com/media-kit/media-kit)
- [dio] (https://pub.dev/packages/dio)
- 等等

<br/>
<br/>
<br/>
