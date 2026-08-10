# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

核心用户为 35–65 岁、希望持续记录和改善健康状态的人群。产品同时提供老年模式，以更大的字号、清晰的操作目标、足够的触控面积和更低的认知负担服务高龄用户。

## Product Purpose

“健康重启计划”帮助用户记录体重、血压、饮食、运动和用药等日常健康信息，理解真实趋势，并把下一步健康行动变得清楚、可执行。成功意味着用户能快速完成当天最重要的记录或照护任务，并持续看见身体变化。

## Positioning

产品以真实健康记录形成个人生命轨迹，并将趋势、计划、提醒和下一步行动连接在同一条持续照护路径中，不使用虚构演示数据制造进展。

## Operating Context

用户主要在 Android 手机上使用产品，常见场景包括晨起测量、餐后记录、服药提醒和查看一周趋势。首页承担每日入口，登录与注册流程使用中国大陆手机号、验证码或密码。

## Capabilities and Constraints

- Android 版本优先完成，遵循 Material 3、系统返回手势、动态字体和至少 48dp 触控目标。
- 第一轮设计仅覆盖浅色模式的 APP 图标配套表达、开屏、登录、注册和首页。
- 保留现有 APP 图标，不重新绘制；视觉系统应延续其 H、叶片、生命轨迹以及蓝绿配色。
- 保留现有业务功能、真实文案与认证逻辑，不在视觉重设计中增加未经确认的功能。
- 老年模式是明确产品能力，不是简单整体放大；应减少并列信息、强化主操作并保持高对比度。

## Brand Commitments

- 产品名称为“健康重启计划”。
- 现有 `assets/images/health_reset_logo.png` 是正式 APP 图标，不重新绘制。
- 品牌表达应可信、清晰、温和，避免医疗恐吓、幼稚化和过度科技感。

## Evidence on Hand

- 现有 APP 图标：`assets/images/health_reset_logo.png`。
- 现有开屏轨迹背景：`assets/images/splash_trajectory_background.png`。
- 当前真机首页截图：`build/health-ui-current.png`。
- 当前 Flutter 页面与主题代码位于 `lib/features/auth/`、`lib/features/home/` 和 `lib/app/app_theme.dart`。

## Product Principles

- 每个页面首先回答“用户现在最应该做什么”。
- 健康数据必须真实、可解释，不用虚构趋势填充界面。
- 让中年用户觉得专业，让高龄用户不用学习也能操作。
- 品牌图标、开屏、认证流程和首页使用同一种视觉语言。
- Android 原生可用性优先于跨平台外观一致性。

## Accessibility & Inclusion

支持系统字体缩放、清晰的色彩对比、至少 48dp 触控目标和语义化辅助功能。老年模式需要更大的字号与操作区域、更少的同屏决策，以及不依赖颜色单独传达状态。
