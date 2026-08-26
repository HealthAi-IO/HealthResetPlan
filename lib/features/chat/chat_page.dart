import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../app/app_theme.dart';
import '../../core/data/chat_repository.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/paywall.dart';
import '../../core/network/ai_api.dart';
import '../../core/network/telemetry_api.dart';
import '../../core/privacy/ai_consent_gate.dart';
import '../../core/widgets/ai_content_notice.dart';
import '../../core/widgets/health_ui.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final AiApi _aiApi = sl<AiApi>();
  final HealthRepository _repo = sl<HealthRepository>();
  final ChatRepository _chatRepo = sl<ChatRepository>();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // 当前会话与消息（内存中编辑、定期写库）
  ChatSession? _currentSession;
  List<_UiMessage> _messages = [];

  static const String _selectedProvider = 'qwen';
  bool _sending = false;
  bool _loadingHistory = true;
  UserProfileData? _profile;
  bool _personalized = true;
  CancelToken? _streamCancelToken;
  Timer? _tokenFlushTimer;
  String _pendingTokens = '';
  int? _streamingMessageId;
  List<String> _streamContextSources = const [];
  int _lastPartialPersistAt = 0;

  static const _quickQuestions = [
    '我的血压今天偏高，有什么需要注意的？',
    '帮我分析一下本周健康数据',
    '今天适合做什么强度的运动？',
    '推荐一个低盐低脂的午餐方案',
    '如何提高睡眠质量？',
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _streamCancelToken?.cancel('page_disposed');
    _tokenFlushTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── 初始化：校验账号 + 加载档案 + 加载最近会话 ───────────────────

  Future<void> _bootstrap() async {
    // 等待首帧渲染完成，确保 showDialog 有可用的 InheritedWidget
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    await requireAccountAndMember(context, PaywallFeature.aiPlan);
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getBool('ai_chat_personalized');
    if (savedMode == null && mounted) {
      _personalized = await _choosePersonalizationMode();
      await prefs.setBool('ai_chat_personalized', _personalized);
    } else {
      _personalized = savedMode ?? true;
    }
    _profile = await _repo.loadProfile();
    final sessions = await _chatRepo.listSessions();

    if (sessions.isEmpty) {
      // 无历史：暂不创建空会话，等发第一条消息时再建
      _currentSession = null;
      _messages = [];
    } else {
      // 默认打开最近的会话
      _currentSession = sessions.first;
      final history = await _chatRepo.loadMessages(_currentSession!.id);
      _messages = history.map(_UiMessage.fromDb).toList();
    }

    if (!mounted) return;
    setState(() => _loadingHistory = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<bool> _choosePersonalizationMode() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('选择健康管家模式'),
            content: const Text(
              '个性化模式会按需参考你的档案、近期指标、近 7 天饮食、今日计划和你确认保存的管家记忆；通用模式不会读取这些个人记录。之后可随时切换。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('使用通用模式'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('使用个性化模式'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String> _buildProfileSummary() async {
    final p = _profile;
    final profileText = p == null
        ? ''
        : () {
            final age =
                p.birthYear > 0 ? '${DateTime.now().year - p.birthYear}岁' : '';
            final gender = p.gender == 'male'
                ? '男'
                : p.gender == 'female'
                    ? '女'
                    : '';
            final bmi = p.bmi > 0 ? '，BMI ${p.bmi.toStringAsFixed(1)}' : '';
            return '$gender$age，身高${p.heightCm.toInt()}cm 体重${p.weightKg}kg$bmi';
          }();
    try {
      final now = DateTime.now();
      final meals = await _repo.loadMealsBetween(
        now.subtract(const Duration(days: 30)),
        now.add(const Duration(days: 1)),
      );
      final indicators = await _repo.loadIndicatorsSince(
        now.subtract(const Duration(days: 30)),
      );
      final mealText = meals
          .take(12)
          .map((meal) =>
              '${DateFormat('MM-dd').format(meal.eatenTime)} ${meal.mealLabel}${meal.name.isEmpty ? '' : ' ${meal.name}'} ${meal.totalCalories.round()}kcal')
          .join('；');
      final indicatorText = indicators
          .take(8)
          .map((item) =>
              '${item.label} ${DateFormat('MM-dd').format(item.measuredTime)} ${item.payload}')
          .join('；');
      final summary = [
        profileText,
        if (mealText.isNotEmpty) '近30天饮食：$mealText',
        if (indicatorText.isNotEmpty) '近30天指标：$indicatorText',
      ].where((item) => item.isNotEmpty).join('\n');
      return summary.length <= 1000 ? summary : summary.substring(0, 1000);
    } catch (_) {
      return profileText;
    }
  }

  // ── 新建会话 ──────────────────────────────────────────────────

  Future<void> _newSession() async {
    setState(() {
      _currentSession = null;
      _messages = [];
      _inputCtrl.clear();
    });
  }

  // ── 切换到指定会话 ────────────────────────────────────────────

  Future<void> _openSession(ChatSession session) async {
    setState(() => _loadingHistory = true);
    final history = await _chatRepo.loadMessages(session.id);
    if (!mounted) return;
    setState(() {
      _currentSession = session;
      _messages = history.map(_UiMessage.fromDb).toList();
      _loadingHistory = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // ── 历史会话弹窗 ──────────────────────────────────────────────

  Future<void> _showHistorySheet() async {
    final sessions = await _chatRepo.listSessions();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '对话历史',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _newSession();
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('新对话'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: sessions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            '暂无历史对话',
                            style: TextStyle(color: AppTheme.muted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        itemCount: sessions.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (_, i) {
                          final s = sessions[i];
                          final active = s.id == _currentSession?.id;
                          final primary = Theme.of(context).colorScheme.primary;
                          final time = DateFormat('MM-dd HH:mm').format(
                            DateTime.fromMillisecondsSinceEpoch(s.updatedAt),
                          );
                          return ListTile(
                            dense: false,
                            tileColor:
                                active ? primary.withValues(alpha: 0.06) : null,
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                                color: primary,
                              ),
                            ),
                            title: Text(
                              s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    active ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '$time · ${s.messageCount} 条消息',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.muted,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: '删除',
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('删除对话'),
                                    content: Text('「${s.title}」将被永久删除'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                await _chatRepo.deleteSession(s.id);
                                if (!mounted || !sheetCtx.mounted) return;
                                Navigator.pop(sheetCtx);
                                if (_currentSession?.id == s.id) {
                                  await _newSession();
                                }
                              },
                            ),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              _openSession(s);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 发送消息 ──────────────────────────────────────────────────

  Future<void> _sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || _sending) return;
    final localIntent = _resolveLocalIntent(trimmed);
    if (localIntent != null) {
      await _sendLocalIntentResponse(trimmed, localIntent);
      return;
    }
    setState(() => _sending = true);

    try {
      if (!await ensureAiConsent(context)) {
        if (mounted) setState(() => _sending = false);
        return;
      }

      // 校验手机号账号
      if (!mounted) return;
      final ok = await requireAccountAndMember(context, PaywallFeature.aiPlan);
      if (!ok) {
        if (mounted) setState(() => _sending = false);
        return;
      }
      if (!mounted) return;
      if (_messages.isEmpty &&
          !await confirmAiCreditUseIfNeeded(context, 'ai_chat')) {
        if (mounted) setState(() => _sending = false);
        return;
      }

      // 懒创建会话
      _currentSession ??= await _ensureSession();

      final sessionId = _currentSession!.id;

      // 一次事务写入用户消息和流式占位，减少发送前同步等待。
      final messageIds = await _chatRepo.addMessagePair(
        sessionId: sessionId,
        userContent: trimmed,
        provider: _selectedProvider,
      );
      final userMsgId = messageIds.userMessageId;
      final assistantMsgId = messageIds.assistantMessageId;
      final requestId = const Uuid().v4();
      _streamCancelToken = CancelToken();
      _streamingMessageId = assistantMsgId;
      _streamContextSources = const [];
      _pendingTokens = '';
      _lastPartialPersistAt = 0;

      if (!mounted) return;
      setState(() {
        _messages.add(
          _UiMessage(id: userMsgId, role: 'user', content: trimmed),
        );
        _messages.add(
          _UiMessage(
            id: assistantMsgId,
            role: 'assistant',
            content: '',
            provider: _selectedProvider,
            streaming: true,
          ),
        );
      });
      _inputCtrl.clear();
      _scrollToBottom();

      // 3) 构建发给 API 的历史（排除当前的空 assistant 占位）
      final history = _messages
          .where((m) => m.content.isNotEmpty && !m.isError)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      unawaited(sl<TelemetryApi>().record('ai_chat_stream_started'));
      await _aiApi.streamChat(
        messages: history,
        provider: _apiProvider,
        profileSummary: await _buildProfileSummary(),
        sessionId: _currentSession!.sessionUuid,
        requestId: requestId,
        personalized: _personalized,
        cancelToken: _streamCancelToken,
        onMetadata: (sources) {
          if (_streamingMessageId != assistantMsgId) return;
          _streamContextSources = List.unmodifiable(sources);
          if (!mounted) return;
          final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
          if (idx >= 0) {
            setState(() {
              _messages[idx] = _messages[idx].copyWith(
                contextSources: _streamContextSources,
              );
            });
          }
        },
        onToken: (token) {
          _queueStreamToken(assistantMsgId, token);
        },
        onDone: () async {
          if (!mounted || _streamingMessageId != assistantMsgId) return;
          _flushStreamTokens(assistantMsgId);
          final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
          if (idx >= 0) {
            final finalContent = _messages[idx].content.trim();
            // 流结束，标记非 streaming，并把最终内容写库
            setState(() {
              _messages[idx] = _messages[idx].copyWith(
                content: finalContent,
                streaming: false,
              );
              _sending = false;
            });
            await _chatRepo.updateMessageContent(
              messageId: assistantMsgId,
              content: finalContent,
              contextSources: _streamContextSources,
            );
            _clearStreamState();
            unawaited(sl<TelemetryApi>().record('ai_chat_stream_completed'));
          } else {
            setState(() => _sending = false);
          }
          _scrollToBottom();
        },
        onError: (error) async {
          if (!mounted || _streamingMessageId != assistantMsgId) return;
          _flushStreamTokens(assistantMsgId);
          final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
          if (idx >= 0) {
            final existing = _messages[idx].content.trim();
            final displayContent =
                existing.isEmpty ? error : '$existing\n\n（回答传输中断：$error）';
            setState(() {
              _messages[idx] = _messages[idx].copyWith(
                content: displayContent,
                streaming: false,
                isError: true,
              );
              _sending = false;
            });
            await _chatRepo.updateMessageContent(
              messageId: assistantMsgId,
              content: displayContent,
              isError: true,
              contextSources: _streamContextSources,
            );
            _clearStreamState();
            unawaited(sl<TelemetryApi>().record('ai_chat_stream_failed'));
          } else {
            setState(() => _sending = false);
          }
          if (error.contains('AI 健康权益已用完') && mounted) {
            await showAiCreditRequiredDialog(context);
          }
        },
      );
    } catch (_) {
      if (mounted) {
        _clearStreamState();
        setState(() => _sending = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('消息发送失败，请重试')));
      }
    }
  }

  _LocalChatIntent? _resolveLocalIntent(String content) {
    final text = content.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final mentionsProduct = text.contains('vip') ||
        text.contains('会员') ||
        text.contains('次数包') ||
        text.contains('ai次数');
    final wantsPurchase = text.contains('充值') ||
        text.contains('购买') ||
        text.contains('开通') ||
        text.contains('续费') ||
        text.contains('怎么买') ||
        text.contains('我要买');
    if (mentionsProduct && wantsPurchase) {
      return const _LocalChatIntent(
        response: '可以，点击下方“查看 VIP 套餐”即可查看当前套餐、价格和可用权益。支付前请确认套餐期限和退款条件。',
      );
    }
    return null;
  }

  Future<void> _sendLocalIntentResponse(
    String content,
    _LocalChatIntent intent,
  ) async {
    setState(() => _sending = true);
    try {
      _currentSession ??= await _ensureSession();
      final sessionId = _currentSession!.id;
      final userMessageId = await _chatRepo.addMessage(
        sessionId: sessionId,
        role: 'user',
        content: content,
      );
      final assistantMessageId = await _chatRepo.addMessage(
        sessionId: sessionId,
        role: 'assistant',
        content: intent.response,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_UiMessage(
          id: userMessageId,
          role: 'user',
          content: content,
        ));
        _messages.add(_UiMessage(
          id: assistantMessageId,
          role: 'assistant',
          content: intent.response,
        ));
        _sending = false;
      });
      _inputCtrl.clear();
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂时无法打开购买入口，请稍后重试')),
      );
    }
  }

  void _queueStreamToken(int messageId, String token) {
    if (token.isEmpty || _streamingMessageId != messageId) return;
    _pendingTokens += token;
    _tokenFlushTimer ??= Timer(const Duration(milliseconds: 50), () {
      _tokenFlushTimer = null;
      _flushStreamTokens(messageId);
    });
  }

  void _flushStreamTokens(int messageId) {
    final token = _pendingTokens;
    _pendingTokens = '';
    if (!mounted || token.isEmpty) return;
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    setState(() {
      _messages[idx] = _messages[idx].copyWith(
        content: _messages[idx].content + token,
      );
    });
    _scrollToBottom();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPartialPersistAt >= 2000) {
      _lastPartialPersistAt = now;
      unawaited(_chatRepo.updateMessageContent(
        messageId: messageId,
        content: _messages[idx].content,
        contextSources: _streamContextSources,
      ));
    }
  }

  Future<void> _stopGeneration() async {
    final messageId = _streamingMessageId;
    if (messageId == null) return;
    _streamCancelToken?.cancel('user_stopped');
    unawaited(sl<TelemetryApi>().record('ai_chat_stream_stopped'));
    _flushStreamTokens(messageId);
    final idx = _messages.indexWhere((message) => message.id == messageId);
    if (idx >= 0) {
      final content = _messages[idx].content.trim();
      final savedContent = content.isEmpty ? '已停止生成' : content;
      setState(() {
        _messages[idx] = _messages[idx].copyWith(
          content: savedContent,
          streaming: false,
        );
        _sending = false;
      });
      await _chatRepo.updateMessageContent(
        messageId: messageId,
        content: savedContent,
        contextSources: _streamContextSources,
      );
    }
    _clearStreamState();
  }

  Future<void> _retryStreamingResponse() async {
    final content = _messages
        .lastWhere(
          (message) => message.role == 'user',
          orElse: () => _UiMessage(id: 0, role: 'user', content: ''),
        )
        .content;
    if (content.isEmpty) return;
    await _stopGeneration();
    await _sendMessage(content);
  }

  void _clearStreamState() {
    _tokenFlushTimer?.cancel();
    _tokenFlushTimer = null;
    _pendingTokens = '';
    _streamCancelToken = null;
    _streamingMessageId = null;
    _streamContextSources = const [];
  }

  Future<ChatSession> _ensureSession() async {
    final id = await _chatRepo.createSession(provider: _selectedProvider);
    final sessions = await _chatRepo.listSessions();
    return sessions.firstWhere((s) => s.id == id);
  }

  String get _apiProvider => _selectedProvider;

  Future<void> _showCoachSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CoachSettingsSheet(
        repository: _chatRepo,
        personalized: _personalized,
        onPersonalizedChanged: (value) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('ai_chat_personalized', value);
          if (mounted) setState(() => _personalized = value);
        },
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 注意：Scaffold 默认 resizeToAvoidBottomInset=true，
    // 会自动把整个 body 上推让出键盘空间，
    // 因此输入栏不再需要手动加 viewInsets.bottom。
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _currentSession?.title.isNotEmpty == true
              ? _currentSession!.title
              : '健康管家',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(22),
          child: Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              _personalized ? '● 个性化模式 · 结合你的记录回答' : '● 通用模式 · 不读取个人健康数据',
              style: TextStyle(color: AppTheme.aiPurple, fontSize: 11),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '个性化与管家记忆',
            icon: const Icon(Icons.psychology_alt_outlined),
            onPressed: _showCoachSettings,
          ),
          // 历史
          IconButton(
            tooltip: '历史对话',
            icon: const Icon(Icons.history),
            onPressed: _showHistorySheet,
          ),
          // 新对话
          IconButton(
            tooltip: '新对话',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newSession,
          ),
          const Tooltip(
            message: 'AI 健康管家',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('AI', style: TextStyle(fontSize: 12))),
            ),
          ),
        ],
      ),
      body: _loadingHistory
          ? const Center(child: CircularProgressIndicator())
          : HealthResponsiveContent(
              maxWidth: 960,
              child: Column(
                children: [
                  Expanded(
                    child: _messages.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final prompt =
                                  i > 0 && _messages[i - 1].role == 'user'
                                      ? _messages[i - 1].content
                                      : '';
                              return _MessageBubble(
                                role: m.role,
                                content: m.content,
                                prompt: prompt,
                                provider: m.provider,
                                isError: m.isError,
                                streaming: m.streaming,
                                contextSources: m.contextSources,
                                onRetry: m.streaming && m.content.isEmpty
                                    ? _retryStreamingResponse
                                    : null,
                              );
                            },
                          ),
                  ),
                  if (_messages.isEmpty) _buildQuickQuestions(),
                  _buildInputBar(),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/ai_robot_avatar.png',
            width: 92,
            height: 92,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          const Text(
            '健康管家',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '有什么健康问题，直接问我吧',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            '首次成功回复扣 1 次，30 分钟内最多 10 轮追问不重复扣费',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickQuestions() {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _quickQuestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          return GestureDetector(
            onTap: () => _sendMessage(_quickQuestions[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Text(
                _quickQuestions[i],
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    // 键盘弹出时输入栏紧贴键盘上沿；无键盘时贴底部安全区
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                focusNode: _focusNode,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '输入健康问题…',
                  hintStyle: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? IconButton.filled(
                    tooltip: '停止生成',
                    onPressed: _stopGeneration,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.stop_rounded, size: 20),
                  )
                : IconButton.filled(
                    onPressed: () => _sendMessage(_inputCtrl.text),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.aiPurple,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 20),
                  ),
          ],
        ),
      ),
    );
  }
}

// ── 内部数据类 ────────────────────────────────────────────────

class _UiMessage {
  _UiMessage({
    required this.id,
    required this.role,
    required this.content,
    this.provider = '',
    this.isError = false,
    this.streaming = false,
    this.contextSources = const [],
  });

  final int id;
  final String role;
  String content;
  String provider;
  bool isError;
  bool streaming;
  final List<String> contextSources;

  _UiMessage copyWith({
    String? content,
    bool? streaming,
    bool? isError,
    List<String>? contextSources,
  }) =>
      _UiMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        provider: provider,
        isError: isError ?? this.isError,
        streaming: streaming ?? this.streaming,
        contextSources: contextSources ?? this.contextSources,
      );

  factory _UiMessage.fromDb(ChatMessage m) => _UiMessage(
        id: m.id,
        role: m.role,
        content: m.content,
        provider: m.provider,
        isError: m.isError,
        contextSources: m.contextSources,
      );
}

class _LocalChatIntent {
  const _LocalChatIntent({required this.response});

  final String response;
}

// ── 消息气泡 ──────────────────────────────────────────────────

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.role,
    required this.content,
    this.prompt = '',
    this.provider = '',
    this.isError = false,
    this.streaming = false,
    this.contextSources = const [],
    this.onRetry,
  });

  final String role;
  final String content;
  final String prompt;
  final String provider;
  final bool isError;
  final bool streaming;
  final List<String> contextSources;
  final Future<void> Function()? onRetry;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waitingController;
  Timer? _slowTimer;
  Timer? _retryTimer;
  bool _slow = false;
  bool _canRetry = false;

  bool get _waiting =>
      widget.role != 'user' && widget.streaming && widget.content.isEmpty;

  @override
  void initState() {
    super.initState();
    _waitingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _syncWaitingState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_waiting && !MediaQuery.disableAnimationsOf(context)) {
      _waitingController.repeat();
    } else {
      _waitingController.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_waiting !=
        (oldWidget.role != 'user' &&
            oldWidget.streaming &&
            oldWidget.content.isEmpty)) {
      _syncWaitingState();
    }
  }

  void _syncWaitingState() {
    _slowTimer?.cancel();
    _retryTimer?.cancel();
    _slow = false;
    _canRetry = false;
    if (!_waiting) {
      _waitingController.stop();
      return;
    }
    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _waiting) setState(() => _slow = true);
    });
    _retryTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _waiting) setState(() => _canRetry = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _retryTimer?.cancel();
    _waitingController.dispose();
    super.dispose();
  }

  bool get isUser => widget.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            SizedBox(
              width: 32,
              height: 32,
              child: widget.isError
                  ? Icon(Icons.error_outline, color: Colors.red.shade700)
                  : AnimatedBuilder(
                      animation: _waitingController,
                      builder: (context, child) {
                        final scale = _waiting
                            ? 1 +
                                0.04 *
                                    (1 -
                                        (2 * _waitingController.value - 1)
                                            .abs())
                            : 1.0;
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Image.asset(
                        'assets/images/ai_robot_avatar.png',
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                if (widget.content.isEmpty) return;
                Clipboard.setData(ClipboardData(text: widget.content));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已复制')));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? AppTheme.deepBlue
                      : widget.isError
                          ? Colors.red.shade50
                          : Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                  border: isUser
                      ? null
                      : Border.all(
                          color: widget.isError
                              ? Colors.red.shade200
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser && !widget.isError && !widget.streaming) ...[
                      const AiContentNotice(feature: '健康管家'),
                      const SizedBox(height: 8),
                    ],
                    if (_waiting)
                      _AiWaitingIndicator(
                        controller: _waitingController,
                        slow: _slow,
                        canRetry: _canRetry,
                        onRetry: widget.onRetry,
                      )
                    else
                      Text(
                        widget.content,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: isUser
                              ? Colors.white
                              : widget.isError
                                  ? Colors.red.shade700
                                  : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    if (!isUser && widget.contextSources.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '参考：${widget.contextSources.join(' · ')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                    if (!isUser && !widget.isError && !widget.streaming) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _buildActions(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final text = '${widget.prompt} ${widget.content}'.toLowerCase();
    if (_containsAny(text, const ['vip', '会员', '充值', '次数包'])) {
      return [
        _ChatAction(
          label: '查看 VIP 套餐',
          icon: Icons.workspace_premium_outlined,
          onTap: () => context.push('/ai-credits'),
        ),
      ];
    }
    if (_containsAny(text, const ['血压', '收缩压', '舒张压'])) {
      return [
        _ChatAction(
          label: '记录血压',
          icon: Icons.favorite_outline,
          onTap: () => context.push('/indicators/input', extra: 'bp'),
        ),
        _ChatAction(
          label: '查看趋势',
          icon: Icons.show_chart_rounded,
          onTap: () => context.push('/indicators'),
        ),
      ];
    }
    if (_containsAny(text, const ['血糖', '空腹血糖', '餐后血糖'])) {
      return [
        _ChatAction(
          label: '记录血糖',
          icon: Icons.water_drop_outlined,
          onTap: () => context.push('/indicators/input', extra: 'glucose'),
        ),
        _ChatAction(
          label: '查看趋势',
          icon: Icons.show_chart_rounded,
          onTap: () => context.push('/indicators'),
        ),
      ];
    }
    if (_containsAny(text, const ['体重', '减重', '增重', 'bmi'])) {
      return [
        _ChatAction(
          label: '记录体重',
          icon: Icons.scale_outlined,
          onTap: () => context.push('/indicators/input', extra: 'weight'),
        ),
        _ChatAction(
          label: '查看趋势',
          icon: Icons.show_chart_rounded,
          onTap: () => context.push('/indicators'),
        ),
      ];
    }
    if (_containsAny(text, const ['睡眠', '失眠', '入睡', '睡不着'])) {
      return [
        _ChatAction(
          label: '记录睡眠',
          icon: Icons.bedtime_outlined,
          onTap: () => context.push('/indicators/input', extra: 'sleep'),
        ),
        _ChatAction(
          label: '查看趋势',
          icon: Icons.show_chart_rounded,
          onTap: () => context.push('/indicators'),
        ),
      ];
    }
    if (_containsAny(text, const ['饮食', '早餐', '午餐', '晚餐', '热量', '食谱'])) {
      return [
        _ChatAction(
          label: '记录饮食',
          icon: Icons.restaurant_outlined,
          onTap: () => context.push('/meals/input'),
        ),
        _ChatAction(
          label: '查看饮食',
          icon: Icons.history_rounded,
          onTap: () => context.push('/meals'),
        ),
      ];
    }
    if (_containsAny(text, const ['运动', '锻炼', '训练', '打卡'])) {
      return [
        _ChatAction(
          label: '今日计划',
          icon: Icons.event_note_outlined,
          onTap: () => context.push('/plan'),
        ),
        _ChatAction(
          label: '完成打卡',
          icon: Icons.check_circle_outline,
          onTap: () => context.push('/clock'),
        ),
      ];
    }
    if (_containsAny(text, const ['戒烟', '吸烟', '烟瘾'])) {
      return [
        _ChatAction(
          label: '戒烟记录',
          icon: Icons.smoke_free_outlined,
          onTap: () => context.push('/quit-smoking'),
        ),
      ];
    }
    if (_containsAny(text, const ['周报', '每周报告', '健康报告'])) {
      return [
        _ChatAction(
          label: '查看健康周报',
          icon: Icons.summarize_outlined,
          onTap: () => context.push('/record-history/weekly'),
        ),
      ];
    }
    return [
      _ChatAction(
        label: '今日计划',
        icon: Icons.event_note_outlined,
        onTap: () => context.push('/plan'),
      ),
      _ChatAction(
        label: '记录饮食',
        icon: Icons.restaurant_outlined,
        onTap: () => context.push('/meals/input'),
      ),
      _ChatAction(
        label: '指标趋势',
        icon: Icons.show_chart_rounded,
        onTap: () => context.push('/indicators'),
      ),
    ];
  }

  bool _containsAny(String text, List<String> values) =>
      values.any(text.contains);
}

class _AiWaitingIndicator extends StatelessWidget {
  const _AiWaitingIndicator({
    required this.controller,
    required this.slow,
    required this.canRetry,
    required this.onRetry,
  });

  final AnimationController controller;
  final bool slow;
  final bool canRetry;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      liveRegion: true,
      label: slow ? 'AI 分析时间稍长，请稍候' : 'AI 正在分析健康记录',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                slow ? '分析时间稍长，请稍候' : '正在结合你的健康记录分析',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) => Row(
                  children: List.generate(3, (index) {
                    final phase = (controller.value * 3 - index) % 3;
                    final active = phase >= 0 && phase < 1;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: active ? 1 : 0.28),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          if (canRetry) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('停止并重试'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatAction extends StatelessWidget {
  const _ChatAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
    );
  }
}

class _CoachSettingsSheet extends StatefulWidget {
  const _CoachSettingsSheet({
    required this.repository,
    required this.personalized,
    required this.onPersonalizedChanged,
  });

  final ChatRepository repository;
  final bool personalized;
  final Future<void> Function(bool value) onPersonalizedChanged;

  @override
  State<_CoachSettingsSheet> createState() => _CoachSettingsSheetState();
}

class _CoachSettingsSheetState extends State<_CoachSettingsSheet> {
  late bool _personalized;
  List<AiCoachMemory> _memories = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _personalized = widget.personalized;
    _reload();
  }

  Future<void> _reload() async {
    final memories = await widget.repository.listMemories();
    if (!mounted) return;
    setState(() {
      _memories = memories;
      _loading = false;
    });
  }

  Future<void> _editMemory([AiCoachMemory? memory]) async {
    final controller = TextEditingController(text: memory?.content ?? '');
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(memory == null ? '添加管家记忆' : '修改管家记忆'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '例如：不吃海鲜，工作日只能晚上运动',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.trim().isEmpty) return;
    await widget.repository.saveMemory(id: memory?.id, content: content);
    await _reload();
  }

  Future<void> _deleteMemory(AiCoachMemory memory) async {
    await widget.repository.deleteMemory(memory.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '个性化与管家记忆',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('结合我的健康数据'),
                subtitle: Text(
                  _personalized
                      ? '读取档案、近期指标、饮食、今日计划和下方记忆'
                      : '仅提供通用健康知识，不读取个人记录',
                ),
                value: _personalized,
                onChanged: (value) async {
                  setState(() => _personalized = value);
                  await widget.onPersonalizedChanged(value);
                },
              ),
              const Divider(),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '我希望管家记住',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _editMemory,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加'),
                  ),
                ],
              ),
              Text(
                '只保存你确认的目标、偏好和生活安排，可随时修改或删除。',
                style: TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _memories.isEmpty
                        ? Center(
                            child: Text(
                              '尚未添加长期记忆',
                              style: TextStyle(color: AppTheme.muted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _memories.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (_, index) {
                              final memory = _memories[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.psychology_outlined),
                                title: Text(memory.content),
                                onTap: () => _editMemory(memory),
                                trailing: IconButton(
                                  tooltip: '删除记忆',
                                  onPressed: () => _deleteMemory(memory),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
