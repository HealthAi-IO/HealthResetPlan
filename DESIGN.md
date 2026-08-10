---
name: 健康重启计划
description: 以生命轨迹连接每日健康行动的清晰、温和 Material 3 系统
colors:
  primary-blue: "#0B91E5"
  deep-blue: "#102844"
  accent-cyan: "#4ED8CF"
  leaf-green: "#62D873"
  ink: "#10243E"
  muted: "#65788B"
  page-bg: "#F4F8FB"
  surface: "#FFFFFF"
  border: "#DDE7EF"
  soft-blue: "#EAF7FE"
  soft-green: "#ECF9F0"
typography:
  headline-large:
    fontFamily: "Noto Sans SC, sans-serif"
    fontSize: "30sp"
    fontWeight: 800
    lineHeight: 1.25
  headline-medium:
    fontFamily: "Noto Sans SC, sans-serif"
    fontSize: "26sp"
    fontWeight: 800
    lineHeight: 1.3
  title:
    fontFamily: "Noto Sans SC, sans-serif"
    fontSize: "20sp"
    fontWeight: 700
    lineHeight: 1.4
  body:
    fontFamily: "Noto Sans SC, sans-serif"
    fontSize: "16sp"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "Noto Sans SC, sans-serif"
    fontSize: "14sp"
    fontWeight: 600
    lineHeight: 1.5
rounded:
  control: "14dp"
  card: "16dp"
  dialog: "24dp"
  sheet: "28dp"
spacing:
  xs: "8dp"
  sm: "12dp"
  md: "16dp"
  lg: "20dp"
  xl: "24dp"
  xxl: "32dp"
components:
  button-primary:
    backgroundColor: "{colors.primary-blue}"
    textColor: "{colors.surface}"
    typography: "{typography.body}"
    rounded: "{rounded.card}"
    height: "52dp"
  input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "17dp 16dp"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "20dp"
  navigation:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    height: "72dp"
---

# Design System: 健康重启计划

## Overview

**Creative North Star: "柔和的生命轨迹"**

界面以专业、温和、可执行为基调。大面积柔和白色空间降低健康信息的压力感，蓝、青、绿沿生命轨迹逐步出现，把记录、趋势和下一步行动连接成连续体验。Material 3 负责结构与交互，品牌只通过色彩、轨迹线和 Logo 精确表达。

长辈模式属于同一视觉系统：放大字号与触控区域、减少同屏决策并强化主操作，不另起一套风格。所有数据必须来自真实业务状态，不以演示数据填充版面。

**Key Characteristics:**

- 清晰的单一主操作和至少 48dp 的触控目标
- 蓝、青、绿生命轨迹贯穿开屏、认证、首页与趋势表达
- 低噪声白色表面、深蓝文字和克制的色调分层
- 标准模式与长辈模式共享组件、色彩和导航语义

## Colors

主蓝承担操作和选中状态，青色连接信息，叶绿只强调改善与完成；深蓝文字在柔和白底上保持可信度和对比度。

**The Trajectory Rule.** 蓝、青、绿按行动、连接、改善的顺序使用，不用它们制造无业务含义的装饰色块。

**The Fixed Brand Rule.** Android 浅色版使用固定品牌色，不被旧的个性化配色设置覆盖。

## Typography

Noto Sans SC 覆盖全部中文层级。页面标题使用 800 字重建立扫描锚点，正文保持舒展行高，标签通过字重而非缩小字号建立层级。

**The Role Scale Rule.** 页面只使用 Material 字体角色；长辈模式按角色整体增强，禁止逐组件随意指定字号。

## Layout

手机页面使用 20–24dp 水平留白和 8dp 基础间距节奏。认证内容最大宽度为 420dp；紧凑宽度使用五项底部导航，扩大宽度时应切换为 Material 导航栏或侧栏。系统状态栏、导航栏、键盘和返回手势必须保持可用。

## Elevation & Depth

系统以色调分层为主，卡片默认无阴影。页面背景、白色表面和浅蓝或浅绿容器建立深度；弹窗、菜单和 Snackbar 使用 Material 组件自身的层级语义。

**The Flat-by-Default Rule.** 静止内容不依赖投影区分层级，只有系统浮层可以获得临时高度。

## Shapes

输入框和次级控件使用 14dp 圆角，卡片与主按钮使用 16dp，弹窗使用 24dp，底部弹层顶部使用 28dp。圆角表达温和但保持操作界面的紧凑感，不使用胶囊化容器包裹普通文字。

## Components

### Buttons

主按钮为品牌蓝底白字、高 52dp、16dp 圆角；描边与文字按钮至少 48dp 高。每个页面只突出一个当前主操作，加载和禁用状态沿用 Material 3 行为。

### Cards / Containers

卡片使用白色或有语义的浅色容器、16dp 圆角和 20dp 左右内边距。卡片不嵌套卡片，信息组通过留白、分隔线或色调层级组织。

### Inputs / Fields

输入框为白底、14dp 圆角、默认浅灰蓝描边；聚焦时切换为 1.6dp 主蓝描边。错误信息最多两行，验证码、密码和手机号逻辑保持原业务行为。

### Navigation

底部导航高 72dp，选中项使用浅蓝指示背景和主蓝文字，未选中项使用灰蓝色。长辈模式入口在认证页、顶层应用栏和个人中心持续可发现。

### Life Trajectory

轨迹线由深蓝向青色和叶绿平滑过渡，末端圆点代表当前状态。它用于开屏、真实趋势与照护时间线，不作为无关页面的背景噪声。

### Logo

保留原有 H、叶片和心电轨迹图形。开屏 Logo 使用透明外部背景，四周不得出现白边；内部白色心电线和圆点必须保留。

## Do's and Don'ts

### Do:

- **Do** 让每个页面首先回答用户现在最应该做什么。
- **Do** 让计划、饮食、记录、指标、个人中心和次级页面从全局主题继承组件样式。
- **Do** 使用图标、工具提示、清晰状态和至少 48dp 的触控区域。
- **Do** 保留真实业务数据、认证流程和系统返回行为。

### Don't:

- **Don't** 在 Logo 外缘添加白色底、白色描边或重新绘制 Logo。
- **Don't** 为报告、AI、内容或隐私页面建立不同视觉风格。
- **Don't** 使用虚构健康数据、过度阴影、装饰性渐变色块或卡片嵌套。
- **Don't** 仅靠颜色传达健康状态或操作结果。
