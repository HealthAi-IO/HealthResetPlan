import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/auth/user_session.dart';
import 'routine_service.dart';
import 'routine_landscape.dart';
import 'package:dio/dio.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';

class RoutinePoster extends StatefulWidget {
  const RoutinePoster({super.key, required this.event});
  final Map event;
  @override
  State<RoutinePoster> createState() => _RoutinePosterState();
}

class _RoutinePosterState extends State<RoutinePoster> {
  final boundary = GlobalKey();
  bool nickname = false;
  bool saving = false;
  bool avatar = false;
  bool loadingAvatar = false;
  Uint8List? avatarBytes;
  final account = UserSession.instance.userId;

  Future<void> toggleAvatar(bool value) async {
    if (!value) {
      setState(() => avatar = false);
      return;
    }
    final key = Uri.tryParse(UserSession.instance.avatarUrl)
        ?.queryParameters['objectKey'];
    if (key == null || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在个人资料中设置头像，再开启海报头像')));
      return;
    }
    setState(() => loadingAvatar = true);
    try {
      final response = await sl<ApiClient>().dio.get<List<int>>('/files/avatar',
          queryParameters: {'objectKey': key},
          options: Options(responseType: ResponseType.bytes));
      if (!mounted || account != UserSession.instance.userId) return;
      final bytes = Uint8List.fromList(response.data!);
      var imageValid = true;
      await precacheImage(MemoryImage(bytes), context,
          onError: (error, stack) => imageValid = false);
      if (!imageValid) throw const FormatException('Invalid avatar image');
      if (!mounted || account != UserSession.instance.userId) return;
      setState(() {
        avatarBytes = bytes;
        avatar = true;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('头像暂时不可用，可继续保存海报')));
      }
    } finally {
      if (mounted) setState(() => loadingAvatar = false);
    }
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final surface =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await surface.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await const MethodChannel('health_reset_plan/gallery')
          .invokeMethod<void>('save', bytes!.buffer.asUint8List());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存到相册')));
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message ?? '图片未保存，打卡记录已保留')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片未保存，请稍后重试；打卡记录已保留')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final morning = event['eventType'] == 'wake';
    final date = beijingTime(DateTime.parse(event['occurredAt']));
    final variant = (event['backgroundVersion'] as num?)?.toInt() ?? 1;
    final colors = morning
        ? [
            const Color(0xffedf7eb),
            Color.lerp(const Color(0xffffdf9e), const Color(0xff9edbd5),
                (variant - 1) / 2)!
          ]
        : [
            const Color(0xff162a46),
            Color.lerp(const Color(0xff384b70), const Color(0xff304f55),
                (variant - 1) / 2)!
          ];
    final ink = morning ? const Color(0xff183b39) : const Color(0xfff1f4f9);
    return Scaffold(
        appBar: AppBar(title: Text(morning ? '早安海报' : '晚安海报')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          RepaintBoundary(
              key: boundary,
              child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: colors)),
                  child: DefaultTextStyle(
                      style: TextStyle(
                          color: ink,
                          fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
                          fontSize: 16,
                          height: 1.6),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('健康重启计划  /  作息重启'),
                            const SizedBox(height: 24),
                            ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                    width: double.infinity,
                                    height: 164,
                                    child: CustomPaint(
                                        painter: RoutineLandscape(morning: morning)))),
                            const SizedBox(height: 32),
                            Text(morning ? '早安，\n新的一天。' : '晚安，\n安心休息。',
                                style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3)),
                            const SizedBox(height: 24),
                            Text(event['quote'] ?? ''),
                            const SizedBox(height: 40),
                            Text(DateFormat('yyyy.MM.dd  HH:mm').format(date),
                                style: const TextStyle(fontSize: 24)),
                            Text(morning ? '起床打卡 · 北京时间' : '准备休息 · 北京时间'),
                            if (nickname &&
                                UserSession.instance.name.isNotEmpty)
                              Text(UserSession.instance.name),
                            if (avatar && avatarBytes != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: ClipOval(
                                      child: Image.memory(avatarBytes!,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, error, stack) =>
                                              const SizedBox.shrink()))),
                            if (morning && event['earlierThan'] != null) ...[
                              const SizedBox(height: 16),
                              Text('对照昨日，你比 ${event['earlierThan']} 人更早起床'),
                              Text(
                                  '对照 ${event['comparisonDate']} 的 ${event['sampleCount']} 位有效打卡用户',
                                  style: const TextStyle(fontSize: 12)),
                            ] else if (morning)
                              const Text('每一次规律的开始，都值得记录。'),
                            if (event['source'] != 'live')
                              const Text('补录 / 修改记录 · 不参与早起比较',
                                  style: TextStyle(fontSize: 12)),
                          ])))),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('海报显示头像'),
              subtitle: loadingAvatar ? const Text('正在加载头像…') : null,
              value: avatar,
              onChanged: saving || loadingAvatar ? null : toggleAvatar),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('海报显示昵称'),
              value: nickname,
              onChanged:
                  saving ? null : (value) => setState(() => nickname = value)),
          FilledButton.icon(
              onPressed: saving ||
                      loadingAvatar ||
                      kIsWeb ||
                      defaultTargetPlatform != TargetPlatform.android
                  ? null
                  : save,
              icon: const Icon(Icons.download_outlined),
              label: Text(saving ? '正在保存…' : '保存到相册')),
          const SizedBox(height: 12),
          const Text('记录已保存。早起比较仅供趣味参考，充足、规律的休息更重要。'),
        ]));
  }
}
