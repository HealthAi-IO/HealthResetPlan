import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/chat_repository.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/paywall.dart';
import '../../core/network/ai_api.dart';
import '../../core/privacy/ai_consent_gate.dart';
import '../../core/widgets/ai_content_notice.dart';

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

  String _selectedProvider = 'auto';
  bool _sending = false;
  bool _loadingHistory = true;
  UserProfileData? _profile;

  static const _providers = [
    _ProviderOption('auto', '自动择优', 'AI'),
    _ProviderOption('deepseek', 'DeepSeek', '🤖'),
    _ProviderOption('doubao', '豆包', '🫘'),
    _ProviderOption('glm', '智谱 GLM', 'GLM'),
    _ProviderOption('qwen', '通义千问', '🌟'),
  ];

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
      _selectedProvider = _normalizeProvider(_currentSession!.provider);
    }

    if (!mounted) return;
    setState(() => _loadingHistory = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  String _buildProfileSummary() {
    final p = _profile;
    if (p == null) return '';
    final age = p.birthYear > 0 ? '${DateTime.now().year - p.birthYear}岁' : '';
    final gender = p.gender == 'male'
        ? '男'
        : p.gender == 'female'
            ? '女'
            : '';
    final bmi = p.bmi > 0 ? '，BMI ${p.bmi.toStringAsFixed(1)}' : '';
    return '$gender$age，身高${p.heightCm.toInt()}cm 体重${p.weightKg}kg$bmi';
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
      _selectedProvider = _normalizeProvider(session.provider);
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
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(children: [
                const Expanded(
                  child: Text('对话历史',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _newSession();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新对话'),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: sessions.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('暂无历史对话',
                            style: TextStyle(color: AppTheme.muted)),
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
                        final time = DateFormat('MM-dd HH:mm').format(
                            DateTime.fromMillisecondsSinceEpoch(s.updatedAt));
                        return ListTile(
                          dense: false,
                          tileColor: active
                              ? AppTheme.deepBlue.withValues(alpha: 0.06)
                              : null,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.deepBlue.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.chat_bubble_outline,
                                size: 18, color: AppTheme.deepBlue),
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
                          subtitle: Text('$time · ${s.messageCount} 条消息',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.muted)),
                          trailing: IconButton(
                            tooltip: '删除',
                            icon: Icon(Icons.delete_outline,
                                size: 18, color: Colors.grey.shade500),
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
                                        child: const Text('取消')),
                                    FilledButton(
                                        style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('删除')),
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
          ]),
        ),
      ),
    );
  }

  // ── 发送消息 ──────────────────────────────────────────────────

  Future<void> _sendMessage(String content) async {
    if (!await ensureAiConsent(context)) return;
    if (content.trim().isEmpty || _sending) return;

    // 校验手机号账号
    if (!mounted) return;
    final ok = await requireAccountAndMember(context, PaywallFeature.aiPlan);
    if (!ok) return;

    // 懒创建会话
    _currentSession ??= await _ensureSession();

    final sessionId = _currentSession!.id;
    final trimmed = content.trim();

    // 1) 写入 user 消息到本地
    final userMsgId = await _chatRepo.addMessage(
      sessionId: sessionId,
      role: 'user',
      content: trimmed,
    );

    // 2) 预占 assistant 消息（先空内容，流式累加）
    final assistantMsgId = await _chatRepo.addMessage(
      sessionId: sessionId,
      role: 'assistant',
      content: '',
      provider: _selectedProvider,
    );

    setState(() {
      _messages.add(_UiMessage(
        id: userMsgId,
        role: 'user',
        content: trimmed,
      ));
      _messages.add(_UiMessage(
        id: assistantMsgId,
        role: 'assistant',
        content: '',
        provider: _selectedProvider,
        streaming: true,
      ));
      _sending = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    // 3) 构建发给 API 的历史（排除当前的空 assistant 占位）
    final history = _messages
        .where((m) => m.content.isNotEmpty)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    await _aiApi.streamChat(
      messages: history,
      provider: _apiProvider,
      profileSummary: _buildProfileSummary(),
      onToken: (token) {
        if (!mounted) return;
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
          if (idx >= 0) {
            _messages[idx] = _messages[idx].copyWith(
              content: _messages[idx].content + token,
            );
          }
        });
        _scrollToBottom();
      },
      onDone: () async {
        if (!mounted) return;
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
          );
        } else {
          setState(() => _sending = false);
        }
        _scrollToBottom();
      },
      onError: (error) async {
        if (!mounted) return;
        final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
        if (idx >= 0) {
          setState(() {
            _messages[idx] = _messages[idx].copyWith(
              content: error,
              streaming: false,
              isError: true,
            );
            _sending = false;
          });
          await _chatRepo.updateMessageContent(
            messageId: assistantMsgId,
            content: error,
            isError: true,
          );
        } else {
          setState(() => _sending = false);
        }
      },
    );
  }

  Future<ChatSession> _ensureSession() async {
    final id = await _chatRepo.createSession(provider: _selectedProvider);
    final sessions = await _chatRepo.listSessions();
    return sessions.firstWhere((s) => s.id == id);
  }

  String? get _apiProvider =>
      _selectedProvider == 'auto' ? null : _selectedProvider;

  String _normalizeProvider(String provider) {
    return _providers.any((p) => p.id == provider) ? provider : 'auto';
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
      backgroundColor: AppTheme.pageBg,
      appBar: AppBar(
        title: Text(
          _currentSession?.title.isNotEmpty == true
              ? _currentSession!.title
              : 'AI 健康顾问',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
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
          // 模型选择
          PopupMenuButton<String>(
            tooltip: '切换模型',
            initialValue: _selectedProvider,
            onSelected: (v) => setState(() => _selectedProvider = v),
            itemBuilder: (_) => [
              for (final p in _providers)
                PopupMenuItem(
                  value: p.id,
                  child: Row(children: [
                    Text(p.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(p.name),
                    if (p.id == _selectedProvider) ...[
                      const Spacer(),
                      const Icon(Icons.check,
                          size: 16, color: AppTheme.deepBlue),
                    ],
                  ]),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                Text(
                  _providers
                      .firstWhere((p) => p.id == _selectedProvider,
                          orElse: () => _providers.first)
                      .emoji,
                  style: const TextStyle(fontSize: 14),
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ]),
            ),
          ),
        ],
      ),
      body: _loadingHistory
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                            return _MessageBubble(
                              role: m.role,
                              content: m.content.isEmpty && m.streaming
                                  ? '...'
                                  : m.content,
                              provider: m.provider,
                              isError: m.isError,
                              streaming: m.streaming,
                            );
                          },
                        ),
                ),
                if (_messages.isEmpty) _buildQuickQuestions(),
                _buildInputBar(),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF0277BD).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.psychology_outlined,
                size: 38, color: Color(0xFF0277BD)),
          ),
          const SizedBox(height: 16),
          const Text('AI 健康顾问',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            '有什么健康问题，直接问我吧',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Text(
                _quickQuestions[i],
                style: const TextStyle(fontSize: 12, color: AppTheme.ink),
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
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.cardBorder)),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              focusNode: _focusNode,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '输入健康问题…',
                hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 14),
                filled: true,
                fillColor: AppTheme.pageBg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _sending
              ? const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton.filled(
                  onPressed: () => _sendMessage(_inputCtrl.text),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF0277BD),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send_rounded, size: 20),
                ),
        ]),
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
  });

  final int id;
  final String role;
  String content;
  String provider;
  bool isError;
  bool streaming;

  _UiMessage copyWith({
    String? content,
    bool? streaming,
    bool? isError,
  }) =>
      _UiMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        provider: provider,
        isError: isError ?? this.isError,
        streaming: streaming ?? this.streaming,
      );

  factory _UiMessage.fromDb(ChatMessage m) => _UiMessage(
        id: m.id,
        role: m.role,
        content: m.content,
        provider: m.provider,
        isError: m.isError,
      );
}

// ── 消息气泡 ──────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.role,
    required this.content,
    this.provider = '',
    this.isError = false,
    this.streaming = false,
  });

  final String role;
  final String content;
  final String provider;
  final bool isError;
  final bool streaming;

  bool get isUser => role == 'user';

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
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isError
                    ? Colors.red.shade100
                    : const Color(0xFF0277BD).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isError ? Icons.error_outline : Icons.psychology_outlined,
                size: 18,
                color: isError ? Colors.red.shade700 : const Color(0xFF0277BD),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制')),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? const Color(0xFF0277BD)
                      : isError
                          ? Colors.red.shade50
                          : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                  border: isUser
                      ? null
                      : Border.all(
                          color: isError
                              ? Colors.red.shade200
                              : AppTheme.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser && !isError && !streaming) ...[
                      const AiContentNotice(feature: 'AI健康顾问'),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: isUser
                            ? Colors.white
                            : isError
                                ? Colors.red.shade700
                                : AppTheme.ink,
                      ),
                    ),
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
}

class _ProviderOption {
  const _ProviderOption(this.id, this.name, this.emoji);
  final String id;
  final String name;
  final String emoji;
}
