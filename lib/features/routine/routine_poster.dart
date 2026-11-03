import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/auth/user_session.dart';
import 'routine_service.dart';
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
  int posterOffset = 0;
  Uint8List? themeBytes;
  bool loadingTheme = false;
  bool themeFailed = false;
  CancelToken? themeRequest;
  final Map<int, Future<Uint8List>> themeCache = {};
  final prefetchRequest = CancelToken();

  int get themeId {
    final date = beijingTime(DateTime.parse(widget.event['occurredAt']));
    return (DateTime.utc(date.year, date.month, date.day)
                    .difference(DateTime.utc(2026))
                    .inDays +
                posterOffset) %
            100 +
        1;
  }

  Future<Uint8List> fetchTheme(int id) => themeCache.putIfAbsent(id, () async {
        try {
          final bytes = await RoutineService(sl<ApiClient>()).themeImage(
              widget.event['eventType'] == 'wake' ? 'morning' : 'night',
              id,
              prefetchRequest);
          if (!mounted ||
              prefetchRequest.isCancelled ||
              account != UserSession.instance.userId) {
            throw const FormatException('Theme request cancelled');
          }
          var valid = true;
          await precacheImage(MemoryImage(bytes), context,
              onError: (_, stack) => valid = false);
          if (!valid) throw const FormatException('Invalid theme image');
          return bytes;
        } catch (_) {
          themeCache.remove(id);
          rethrow;
        }
      });

  @override
  void initState() {
    super.initState();
    UserSession.instance.addListener(sessionChanged);
    loadTheme();
  }

  void sessionChanged() {
    if (account == UserSession.instance.userId &&
        UserSession.instance.isAccountLogin) {
      return;
    }
    themeRequest?.cancel();
    prefetchRequest.cancel();
    themeCache.clear();
    if (mounted) {
      setState(() {
        themeBytes = null;
        avatarBytes = null;
        avatar = false;
        nickname = false;
        loadingTheme = false;
      });
    }
  }

  @override
  void dispose() {
    themeRequest?.cancel();
    prefetchRequest.cancel();
    themeCache.clear();
    UserSession.instance.removeListener(sessionChanged);
    super.dispose();
  }

  Future<void> loadTheme({bool advance = false}) async {
    if (!UserSession.instance.isAccountLogin ||
        account != UserSession.instance.userId) {
      return;
    }
    themeRequest?.cancel();
    final request = CancelToken();
    themeRequest = request;
    setState(() {
      loadingTheme = true;
      themeFailed = false;
    });
    try {
      final id = advance ? themeId % 100 + 1 : themeId;
      final bytes = await fetchTheme(id);
      if (!mounted ||
          request.isCancelled ||
          account != UserSession.instance.userId) {
        return;
      }
      setState(() {
        themeBytes = bytes;
        if (advance) posterOffset++;
      });
      final upcoming = [
        for (var offset = 1; offset <= 3; offset++) (id - 1 + offset) % 100 + 1
      ];
      themeCache.removeWhere((key, _) => key != id && !upcoming.contains(key));
      for (final next in upcoming) {
        fetchTheme(next).then<void>((_) {}, onError: (_) {});
      }
    } catch (_) {
      if (mounted &&
          !request.isCancelled &&
          account == UserSession.instance.userId) {
        setState(() => themeFailed = true);
      }
    } finally {
      if (mounted && identical(themeRequest, request) && !request.isCancelled) {
        setState(() => loadingTheme = false);
      }
    }
  }

  String get posterQuote {
    if (posterOffset == 0) return widget.event['quote'] ?? '';
    final quotes = widget.event['eventType'] == 'wake'
        ? const [
            '从一杯温水开始，温柔照顾自己。',
            '迎着晨光舒展身体，让今天多一点活力。',
            '好好吃早餐，认真开启新的一天。',
            '循序渐进地行动，每一天都值得记录。',
            '给身体一点时间，让健康慢慢积累。',
            '规律起居，把照顾自己放在心上。'
          ]
        : const [
            '放下今天的忙碌，给身体一段安静的休息。',
            '让屏幕歇一歇，也让自己慢下来。',
            '轻轻呼吸，今晚安心休息。',
            '今天已经认真生活，此刻好好照顾自己。',
            '把未完成的事留给明天，让身心放松。',
            '规律休息，是送给明天的温柔。'
          ];
    final original = widget.event['quote'] ?? '';
    final alternatives = quotes.where((quote) => quote != original).toList();
    return alternatives[(posterOffset - 1) % alternatives.length];
  }

  Future<void> toggleAvatar(bool value) async {
    if (!value) {
      setState(() => avatar = false);
      return;
    }
    final key = Uri.tryParse(UserSession.instance.avatarUrl)
        ?.queryParameters['objectKey'];
    if (key == null || key.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在个人资料中设置头像，再开启海报头像')));
      return;
    }
    setState(() => loadingAvatar = true);
    try {
      final response = await sl<ApiClient>().dio.get<List<int>>('/files/avatar',
          queryParameters: {'objectKey': key},
          options: Options(responseType: ResponseType.bytes));
      if (!mounted || account != UserSession.instance.userId) {
        return;
      }
      final bytes = Uint8List.fromList(response.data!);
      var imageValid = true;
      await precacheImage(MemoryImage(bytes), context,
          onError: (error, stack) => imageValid = false);
      if (!imageValid) throw const FormatException('Invalid avatar image');
      if (!mounted || account != UserSession.instance.userId) {
        return;
      }
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
    if (themeBytes == null ||
        loadingTheme ||
        !UserSession.instance.isAccountLogin ||
        account != UserSession.instance.userId) {
      return;
    }
    setState(() => saving = true);
    try {
      if (!mounted ||
          account != UserSession.instance.userId ||
          !UserSession.instance.isAccountLogin) {
        return;
      }
      await precacheImage(
          const AssetImage('assets/images/app_download_qr.png'), context);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          account != UserSession.instance.userId ||
          !UserSession.instance.isAccountLogin) {
        return;
      }
      final surface =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image =
          await surface.toImage(pixelRatio: 1080 / surface.size.width);
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
    const ink = Color(0xff183b39);
    return Scaffold(
        appBar: AppBar(title: Text(morning ? '早安海报' : '晚安海报')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          RepaintBoundary(
              key: boundary,
              child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                          width: 360,
                          height: 480,
                          // 固定分享画布；页面操作仍跟随系统字体大小。
                          child: MediaQuery.withNoTextScaling(
                              child: DefaultTextStyle(
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.fontFamily,
                                      fontSize: 14,
                                      height: 1.5),
                                  child: Column(children: [
                                    Expanded(
                                        child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                          if (themeBytes != null)
                                            Image.memory(themeBytes!,
                                                fit: BoxFit.cover,
                                                semanticLabel: morning
                                                    ? '生机晨光'
                                                    : '温馨安静的夜晚')
                                          else
                                            const ColoredBox(
                                                color: Color(0xff52625c)),
                                          DecoratedBox(
                                              decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                      begin:
                                                          Alignment.topCenter,
                                                      end: Alignment
                                                          .bottomCenter,
                                                      colors: morning
                                                          ? const [
                                                              Color(0x8a18352a),
                                                              Color(0x0018352a),
                                                              Color(0xe618352a)
                                                            ]
                                                          : const [
                                                              Color(0x801b1720),
                                                              Color(0x001b1720),
                                                              Color(0xd91b1720)
                                                            ],
                                                      stops: [0, 0.4, 1]))),
                                          Padding(
                                              padding: const EdgeInsets.all(26),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(morning ? '早安' : '晚安',
                                                        style: const TextStyle(
                                                            fontSize: 46,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            height: 1.2,
                                                            letterSpacing: 4)),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                        morning
                                                            ? '新的一天。'
                                                            : '安心休息。',
                                                        style: const TextStyle(
                                                            fontSize: 16,
                                                            letterSpacing: 2)),
                                                    const Spacer(),
                                                    Text(posterQuote,
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 16,
                                                            height: 1.7)),
                                                    const SizedBox(height: 20),
                                                    const Divider(
                                                        color:
                                                            Color(0x66ffffff),
                                                        height: 1),
                                                    const SizedBox(height: 12),
                                                    Row(children: [
                                                      Text(
                                                          DateFormat('HH:mm')
                                                              .format(date),
                                                          style: const TextStyle(
                                                              fontSize: 36,
                                                              height: 1.2,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w300)),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                          child: Text(
                                                              '${DateFormat('yyyy.MM.dd').format(date)}\n${morning ? '起床打卡' : '准备休息'} · 北京时间',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      height:
                                                                          1.7))),
                                                    ]),
                                                    if (event['source'] !=
                                                        'live') ...[
                                                      const SizedBox(height: 8),
                                                      const Text(
                                                          '补录 / 修改记录 · 不参与早起比较',
                                                          style: TextStyle(
                                                              fontSize: 11)),
                                                    ] else if (morning &&
                                                        event['earlierThan'] !=
                                                            null) ...[
                                                      const SizedBox(height: 8),
                                                      Text(
                                                          '对照昨日，你比 ${event['earlierThan']} 人更早起床',
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      12)),
                                                    ],
                                                  ])),
                                        ])),
                                    Container(
                                        height: 86,
                                        color: const Color(0xfff5f5ef),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 22, vertical: 8),
                                        child: Row(children: [
                                          if (avatar &&
                                              avatarBytes != null) ...[
                                            ClipOval(
                                                child: Image.memory(
                                                    avatarBytes!,
                                                    width: 32,
                                                    height: 32,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (_, error, stack) =>
                                                            const SizedBox
                                                                .shrink())),
                                            const SizedBox(width: 10),
                                          ],
                                          Expanded(
                                              child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                if (nickname &&
                                                    UserSession.instance.name
                                                        .isNotEmpty)
                                                  Text(
                                                      UserSession.instance.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          color: ink,
                                                          fontSize: 12)),
                                                const Text('健康重启计划',
                                                    style: TextStyle(
                                                        color: ink,
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const Text('作息重启 · 记录每一天',
                                                    style: TextStyle(
                                                        color:
                                                            Color(0xff52625c),
                                                        fontSize: 10)),
                                              ])),
                                          const SizedBox(width: 10),
                                          Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Image.asset(
                                                    'assets/images/app_download_qr.png',
                                                    width: 56,
                                                    height: 56,
                                                    filterQuality:
                                                        FilterQuality.none,
                                                    semanticLabel:
                                                        '扫码下载健康重启计划，https://jkcqplan.com'),
                                                const Text('扫码下载',
                                                    style: TextStyle(
                                                        color: ink,
                                                        fontSize: 9,
                                                        height: 1.2)),
                                              ]),
                                        ])),
                                  ]))))))),
          const SizedBox(height: 16),
          if (loadingTheme)
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('正在加载新图片…')
                ])),
          if (themeFailed)
            Row(children: [
              const Expanded(child: Text('图片加载失败，请重试。')),
              TextButton(onPressed: loadTheme, child: const Text('重试'))
            ]),
          OutlinedButton.icon(
              onPressed: saving || loadingAvatar || loadingTheme
                  ? null
                  : () {
                      loadTheme(advance: true);
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('换一张')),
          const SizedBox(height: 8),
          if (morning && event['earlierThan'] != null)
            Text(
                '早起比较：对照 ${event['comparisonDate']} 的 ${event['sampleCount']} 位有效打卡用户，仅供趣味参考。'),
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
                      themeBytes == null ||
                      loadingTheme ||
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
