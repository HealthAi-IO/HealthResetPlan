import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const _sections = [
    (
      '一、我们是谁以及如何联系',
      [
        '“健康重启计划”由北京微零记科技有限公司运营。公司地址：北京市大兴区荣华街道亦庄经济开发区宏达南路 5 号宏达利德 A 座 303。涉及个人信息保护、账号注销或投诉建议，可通过 caokun@weilingji.com 或 13436574850 联系我们。',
      ],
    ),
    (
      '二、我们处理的信息',
      [
        '账号使用：昵称、健康档案（如年龄、身高、体重、病史和用药信息）、健康指标、饮食运动计划、餐食营养与消费记录、自建菜谱和收藏、戒烟计划和戒烟记录、打卡记录、提醒、备注和用户主动选择的图片，与登录账号绑定并在线保存。',
        '注册或登录账号：手机号、验证码或密码、账号标识、登录会话，以及与账号绑定的上述健康数据。我们用这些信息完成账号认证、数据保存和在线健康管理功能。',
        '报告识别：仅在你主动选择图片并确认上传后，上传检查报告图片至我们的服务端进行识别；识别结果须经你确认后才会写入健康记录。',
        '云端 AI：仅在你单独同意后使用。健康管家个性化模式会按需读取健康档案、近期指标、近 7 天饮食、今日计划和你主动保存的管家记忆；你可以切换为不读取个人数据的通用模式，并随时管理管家记忆。主动提交的图片会先加密存入账号对应的私有对象存储，再用于本次 AI 分析；不用于训练、广告或运营画像。',
        '付费与权益：购买 AI 次数包或 VIP 会员时，我们会处理商品、订单号、支付渠道、支付金额、支付状态、退款记录和权益消耗记录，用于完成交易、开通权益、退款、对账、客服和安全风控。',
        '短信与 Web 推送：发送验证码时，京东云短信会按指令处理手机号和验证码发送所需信息；你授权 Web 提醒后，我们会保存浏览器推送 endpoint、公钥、auth 密钥、设备标识和时区，用于发送你创建的提醒。',
        '必要运行信息：网络连接状态、通知授权状态和崩溃所需的基础运行信息，用于保障服务和排查故障。我们不收集定位信息。',
      ],
    ),
    (
      '三、权限与敏感信息说明',
      [
        '健康、病史、用药、体征指标和报告图片属于敏感个人信息。我们仅在你录入、上传、注册登录或开启相关功能时处理。相机和相册仅用于你主动选择的报告、饮食或药品图片；通知、精确闹钟和开机恢复仅在你主动创建提醒后用于今天和明天的健康或用药提醒；“同步到手机闹钟”会打开系统时钟，需你在系统界面自行确认。',
        '使用皮肤图片分析时，用户可主动选择包含面部的图片。我们不进行身份识别、人脸比对或生物识别模板提取；图片会加密存入账号对应的私有对象存储，仅用于用户选择的 AI 分析，不用于训练、广告、用户画像或运营统计。',
      ],
    ),
    (
      '四、存储、同步与安全',
      [
        '健康业务功能需要登录账号，业务数据自动保存到服务器；退出后本机不保留健康业务数据。',
        '敏感健康字段由服务器使用 AES-256-GCM 加密后写入数据库，加密密钥仅由服务器安全环境配置提供；传输使用 HTTPS。',
        '账号存续期间，我们保存提供服务所必需的数据。注销账号后，账号会进入 30 天恢复期，期间可以通过绑定手机号和短信验证恢复；恢复期结束后，账号、健康业务数据及关联文件会永久删除且无法恢复。',
        '支付订单、退款和账务记录会按照交易、税务、审计和争议处理所需期限保存；超过必要期限后删除或匿名化。',
        '我们采取访问控制、加密传输和最小权限等措施保护信息，请妥善保管设备、账号、密码和验证码。',
        '数据库敏感数据由服务器使用 AES-256-GCM 加密存储，报告图片等文件加密后存入私有对象存储。使用云端 AI 时，必要内容会在受控服务端内存中短暂处理并经 HTTPS 转发。',
      ],
    ),
    (
      '五、对外提供与第三方',
      [
        '我们不会出售个人信息，也不会向第三方共享、转让或公开披露你的个人信息，法律法规另有规定、履行合同所必需或取得你单独同意的情形除外。你单独同意云端 AI 后，我们会将完成该次请求所必需的信息提供给你在授权页面确认的 AI 服务商（千问、豆包、智谱 GLM 或 DeepSeek）。购买付费权益时，支付渠道会按其规则处理完成支付和退款所必需的信息；发送短信验证码时，京东云短信会按我们的指令处理必要发送信息。我们要求服务提供方仅按约定目的处理，不用于广告、用户画像或模型训练。不接入广告、统计或社交类第三方数据服务；Web 推送仅在用户授权提醒后使用浏览器/系统推送能力。',
      ],
    ),
    (
      '六、跨境处理说明',
      [
        '我们主要在中国境内处理和存储个人信息。你选择的 AI 服务商、应用商店、支付渠道、浏览器或系统推送服务可能在境外处理部分必要信息；发生跨境处理时，我们会按照适用法律采取合同约束、安全评估、最小必要传输等措施。',
      ],
    ),
    (
      '七、AI 单独同意与撤回',
      [
        '首次使用云端 AI 前，我们会单独说明处理目的、数据类型、服务商及风险并取得你的同意。涉及皮肤、舌象、头皮等图片时，用户确认后才会发送图片。你可在“我的 - AI 数据处理授权”中撤回同意；撤回后 AI 功能停止，账号中的健康记录不受影响。',
      ],
    ),
    (
      '八、你的权利',
      [
        '你可以在应用内查看、修改、删除账号健康记录，管理提醒，退出登录，或在“我的 - 账号与数据安全”中注销账号。涉及访问、更正、删除、撤回同意、获取副本、限制或拒绝部分处理、解释说明、注销账号或投诉的请求，可按本政策第一部分的联系方式提出。撤回通知、相机、AI 或 Web 推送授权不会影响此前已完成的处理，但相关功能将无法继续使用。',
      ],
    ),
    (
      '九、未成年人和政策更新',
      [
        '本服务主要面向成年人。未满 14 周岁的用户应由监护人阅读本政策并在取得监护人同意后使用。我们更新本政策时会在应用内或官网提示；涉及处理目的、方式或范围的重大变化，将在重新取得必要同意后实施。',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '健康重启计划隐私政策',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '生效日期：2026 年 9 月 6 日',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 24),
                    for (final section in _sections)
                      _PolicySection(
                        title: section.$1,
                        paragraphs: section.$2,
                      ),
                    const Divider(height: 40),
                    Text(
                      '北京微零记科技有限公司\n'
                      '联系邮箱：caokun@weilingji.com\n'
                      '联系电话：13436574850',
                      style: TextStyle(height: 1.7, color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({
    required this.title,
    required this.paragraphs,
  });

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < paragraphs.length; index++) ...[
            Text(
              paragraphs.length == 1
                  ? paragraphs[index]
                  : '• ${paragraphs[index]}',
              style: const TextStyle(height: 1.75),
            ),
            if (index < paragraphs.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
