import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/paywall.dart';
import '../../core/network/ai_api.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final AiApi _aiApi = sl<AiApi>();
  final HealthRepository _repo = sl<HealthRepository>();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // 消息列表：{'role': 'user'/'assistant', 'content': '...', 'provider': '...'}
  final List<Map<String, String>> _messages = [];

  String _selectedProvider = 'deepseek';
  bool _sending = false;
  UserProfileData? _profile;
  bool _memberChecked = false; // ignore: unused_field

  static const _providers = [
    _ProviderOption('deepseek', 'DeepSeek', '🤖'),
    _ProviderOption('doubao', '豆包', '🫘'),
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
    _checkMemberAndLoad();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _checkMemberAndLoad() async {
    if (mounted) {
      // 进入页面时校验登录 + 会员（未满足会弹窗引导，不阻断页面展示）
      await requireAccountAndMember(context, PaywallFeature.aiPlan);
    }
    if (!mounted) return;
    setState(() => _memberChecked = true);
    _profile = await _repo.loadProfile();
    if (mounted) setState(() {});
  }

  String _buildProfileSummary() {
    final p = _profile;
    if (p == null) return '';
    final age = p.birthYear > 0 ? '${DateTime.now().year - p.birthYear}岁' : '';
    final gender = p.gender == 'male' ? '男' : p.gender == 'female' ? '女' : '';
    final bmi = p.bmi > 0 ? '，BMI ${p.bmi.toStringAsFixed(1)}' : '';
    return '$gender$age，身高${p.heightCm.toInt()}cm 体重${p.weightKg}kg$bmi';
  }

  Future<void> _sendMessage(String content) async {
    if (content.trim().isEmpty || _sending) return;

    // 必须先登录账号 + 已开通会员才能用 AI
    if (!mounted) return;
    final ok = await requireAccountAndMember(context, PaywallFeature.aiPlan);
    if (!ok) return;

    final userMsg = {'role': 'user', 'content': content.trim()};
    setState(() {
      _messages.add(userMsg);
      _sending = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    // 预先插入一条空白 assistant 消息，流式追加 token 到这里
    setState(() {
      _messages.add({
        'role': 'assistant',
        'content': '',
        'provider': _selectedProvider,
        'streaming': 'true',
      });
    });

    final history = _messages
        .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
        .where((m) => m['content']!.isNotEmpty) // 排除刚刚插入的空消息
        .map((m) => {'role': m['role']!, 'content': m['content']!})
        .toList();

    // 加回不含空消息的 user 消息
    final historyWithUser = [...history.where((m) => m['role'] != 'assistant' || m['content']!.isNotEmpty)];

    await _aiApi.streamChat(
      messages: historyWithUser,
      profileSummary: _buildProfileSummary(),
      onToken: (token) {
        if (!mounted) return;
        setState(() {
          final last = _messages.last;
          _messages[_messages.length - 1] = {
            ...last,
            'content': (last['content'] ?? '') + token,
          };
        });
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          final last = _messages.last;
          _messages[_messages.length - 1] = {
            ...last,
            'streaming': 'false',
          };
          _sending = false;
        });
        _scrollToBottom();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _messages[_messages.length - 1] = {
            'role': 'assistant',
            'content': error,
            'provider': _selectedProvider,
            'isError': 'true',
            'streaming': 'false',
          };
          _sending = false;
        });
      },
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

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppTheme.pageBg,
      appBar: AppBar(
        title: const Text('AI 健康顾问'),
        actions: [
          // 提供方选择
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
                      const Icon(Icons.check, size: 16, color: AppTheme.deepBlue),
                    ],
                  ]),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Text(
                  _providers.firstWhere((p) => p.id == _selectedProvider,
                          orElse: () => _providers.first)
                      .emoji,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 4),
                Text(
                  _providers.firstWhere((p) => p.id == _selectedProvider,
                          orElse: () => _providers.first)
                      .name,
                  style: const TextStyle(fontSize: 13),
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ]),
            ),
          ),
          // 清空对话
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: '清空对话',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () {
                setState(() => _messages.clear());
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length && _sending) {
                        return const _TypingBubble();
                      }
                      final msg = _messages[i];
                      return _MessageBubble(
                        role: msg['role']!,
                        content: msg['content']!,
                        provider: msg['provider'],
                        isError: msg['isError'] == 'true',
                      );
                    },
                  ),
          ),

          // 快捷问题（仅无消息时）
          if (_messages.isEmpty) _buildQuickQuestions(),

          // 输入区
          _buildInputBar(bottomPad),
        ],
      ),
    );
  }

  // ── 空状态 ────────────────────────────────────────────────

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

  // ── 快捷问题 ──────────────────────────────────────────────

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

  // ── 输入框 ────────────────────────────────────────────────

  Widget _buildInputBar(double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomPad),
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
            onSubmitted: (_) {},
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
    );
  }
}

// ── 消息气泡 ──────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.role,
    required this.content,
    this.provider,
    this.isError = false,
  });

  final String role;
  final String content;
  final String? provider;
  final bool isError;

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
            // AI 头像
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
                    if (!isUser && provider != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        provider!,
                        style: TextStyle(
                          fontSize: 10,
                          color: isError
                              ? Colors.red.shade300
                              : AppTheme.muted,
                        ),
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
}

// ── 打字中动画 ────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF0277BD).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.psychology_outlined,
                size: 18, color: Color(0xFF0277BD)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      _Dot(delay: i * 0.3, value: _ctrl.value),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.delay, required this.value});
  final double delay;
  final double value;

  @override
  Widget build(BuildContext context) {
    final t = ((value + delay) % 1.0);
    final scale = t < 0.5 ? 1.0 + t * 0.6 : 1.6 - (t - 0.5) * 0.6;
    return Transform.scale(
      scale: scale.clamp(1.0, 1.6),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: AppTheme.muted,
          shape: BoxShape.circle,
        ),
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
