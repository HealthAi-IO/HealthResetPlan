# HealthResetPlan（Flutter 客户端）

> 健康重启计划多端客户端：macOS / iOS / Windows / Android / Web。

## 目录结构

```
HealthResetPlan/
 ├── lib/
 │    ├── main.dart
 │    ├── app/                # 应用壳（路由、主题）
 │    ├── core/
 │    │    ├── crypto/        # AES-256-GCM 加密、UMK 管理、BIP39 备份
 │    │    ├── data/          # 健康档案、指标、计划、打卡领域模型与仓库
 │    │    ├── storage/       # 本地数据库：移动/桌面 SQLite，Web SharedPreferences
 │    │    ├── network/       # Dio API 客户端
 │    │    ├── di/            # GetIt 服务定位器
 │    │    └── platform/      # 平台差异封装（蓝牙、文件、健康 SDK）
 │    ├── features/
 │    │    ├── auth/          # 登录与引导
 │    │    ├── profile/       # 健康档案
 │    │    ├── report/        # 检查报告 OCR
 │    │    ├── plan/          # AI 计划
 │    │    ├── clock/         # 打卡
 │    │    ├── shell/         # 响应式导航壳
 │    │    ├── stats/         # 数据统计
 │    │    ├── sync/          # 加密同步与密钥
 │    │    └── home/          # 首页
 │    └── l10n/               # 国际化
 ├── assets/                  # 静态资源
 ├── ios/ macos/ android/ windows/ web/
 ├── pubspec.yaml
 └── README.md
```

## 核心约束

1. **本地存储优先**：移动端和桌面端使用 SQLite；Web 端使用 `shared_preferences` 持久化，云同步是可选项。
2. **端到端加密**：上传到服务端的敏感字段必须经过 `CryptoService` 用 AES-256-GCM 加密。
3. **私钥本地保存**：UMK 仅写入 `flutter_secure_storage`（macOS/iOS Keychain、Android Keystore、Windows Credential Manager），**不上传任何服务端**。
4. **备份强制**：用户开通云同步前必须确认完成助记词备份。
5. **基础功能闭环**：当前已实现健康档案、报告指标录入、本地 7 天计划、提醒与打卡、统计总览、主密钥备份/恢复。
6. **图标**：优先 SVG / Material Symbols，禁止内嵌大体积位图。

## 本地开发

环境要求：

- Flutter 3.27+（stable）
- Dart 3.6+
- Xcode 16 / Android Studio / Visual Studio（按目标平台）

依赖安装：

```bash
flutter pub get
```

代码检查：

```bash
flutter analyze
dart format --set-exit-if-changed .
```

测试：

```bash
flutter test
```

> 启动调试请使用 IDE（VS Code / Android Studio）的调试模式，本仓库不提供构建脚本。

Web 本地预览：

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

## 隐私 & 安全

- 详见 [`docs/05-安全与加密`](../docs/05-安全与加密)
- 关键模块：`lib/core/crypto/`、`lib/features/sync/`

## 项目文档

完整需求 / 架构 / 设计 / 接口文档：[`/Users/caokun/Productions/HealthAi-IO/docs`](../docs)

## 许可证

Apache License 2.0
