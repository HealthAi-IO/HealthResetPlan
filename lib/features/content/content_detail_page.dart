import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_theme.dart';
import '../../core/content/content_models.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/content_api.dart';
import '../../core/network/api_response.dart';

class ContentDetailPage extends StatefulWidget {
  const ContentDetailPage({super.key, required this.id});

  final int id;

  @override
  State<ContentDetailPage> createState() => _ContentDetailPageState();
}

class _ContentDetailPageState extends State<ContentDetailPage> {
  final ContentApi _api = sl<ContentApi>();
  final TextEditingController _commentController = TextEditingController();
  ContentDetail? _detail;
  ContentInteraction? _interaction;
  String? _error;
  String? _interactionError;
  bool _submittingInteraction = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await _api.contentDetail(widget.id);
      if (!mounted) return;
      setState(() => _detail = detail);
      try {
        await _api.markContentRead(widget.id);
      } catch (_) {
        // Reading the article must not fail because read-state sync failed.
      }
      await _loadInteraction();
    } catch (_) {
      if (mounted) setState(() => _error = '资讯不存在、已下架或网络暂时不可用');
    }
  }

  Future<void> _loadInteraction() async {
    try {
      final interaction = await _api.contentInteraction(widget.id);
      if (mounted) {
        setState(() {
          _interaction = interaction;
          _interactionError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _interactionError = _interactionFailure(
              error,
              '互动内容加载失败，请检查网络后重试',
            ));
      }
    }
  }

  Future<void> _react(String reaction) async {
    final current = _interaction;
    if (current == null || _submittingInteraction) return;
    final nextReaction = current.userReaction == reaction ? '' : reaction;
    setState(() => _submittingInteraction = true);
    try {
      final result = await _api.reactToContent(widget.id, nextReaction);
      if (mounted) setState(() => _interaction = result);
    } catch (error) {
      if (mounted) {
        _showInteractionError(_interactionFailure(error, '操作失败，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _submittingInteraction = false);
    }
  }

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _submittingInteraction) return;
    if (content.length > 500) {
      _showInteractionError('评论不能超过 500 字');
      return;
    }
    setState(() => _submittingInteraction = true);
    try {
      final result = await _api.addComment(widget.id, content);
      if (!mounted) return;
      _commentController.clear();
      FocusScope.of(context).unfocus();
      setState(() => _interaction = result);
    } catch (error) {
      if (mounted) {
        _showInteractionError(
          _interactionFailure(error, '评论发布失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _submittingInteraction = false);
    }
  }

  Future<void> _deleteComment(ContentComment comment) async {
    if (!comment.isMine || _submittingInteraction) return;
    setState(() => _submittingInteraction = true);
    try {
      final result = await _api.deleteComment(widget.id, comment.id);
      if (mounted) setState(() => _interaction = result);
    } catch (error) {
      if (mounted) {
        _showInteractionError(_interactionFailure(error, '删除失败，请稍后重试'));
      }
    } finally {
      if (mounted) setState(() => _submittingInteraction = false);
    }
  }

  void _showInteractionError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _interactionFailure(Object error, String fallback) {
    if (error is DioException && error.error is ApiResponseException) {
      final message = (error.error as ApiResponseException).message.trim();
      if (message.isNotEmpty) return message;
    }
    if (error is DioException &&
        (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout)) {
      return '网络连接异常，请检查网络后重试';
    }
    return fallback;
  }

  Future<bool> _openContentUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return false;
    }
    final official =
        uri.host == 'jkcqplan.com' || uri.host.endsWith('.jkcqplan.com');
    if (!official) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('打开外部链接？'),
          content: Text(uri.host),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (confirmed != true) return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('健康资讯')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               Icon(Icons.info_outline, size: 46, color: AppTheme.muted),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final detail = _detail;
    if (detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width >= 900 ? 32 : 16,
        18,
        MediaQuery.sizeOf(context).width >= 900 ? 32 : 16,
        44,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (detail.coverUrl.isNotEmpty)
                  AspectRatio(
                    aspectRatio: 16 / 8,
                    child: Image.network(
                      _api.assetUrl(detail.coverUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (detail.sourceType == 'ai')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xffecfeff),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'AI生成健康科普 · 仅供生活健康参考',
                            style: TextStyle(
                              color: Color(0xff0e7490),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (detail.sourceType == 'ai') const SizedBox(height: 16),
                      Text(
                        detail.title,
                        style:  TextStyle(
                          color: AppTheme.ink,
                          fontSize: 28,
                          height: 1.35,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        detail.publishedAt == null
                            ? ''
                            : DateFormat('yyyy年MM月dd日 HH:mm')
                                .format(detail.publishedAt!),
                        style:  TextStyle(
                            color: AppTheme.muted, fontSize: 13),
                      ),
                      if (detail.summary.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          detail.summary,
                          style:  TextStyle(
                            color: AppTheme.muted,
                            fontSize: 16,
                            height: 1.7,
                          ),
                        ),
                      ],
                      const Divider(height: 38),
                      if (detail.type == 'card')
                        _CardContent(detail: detail)
                      else if (detail.type == 'article')
                        HtmlWidget(
                          detail.bodyHtml,
                          baseUrl: _api.apiBaseUri,
                          textStyle:  TextStyle(
                            color: AppTheme.ink,
                            fontSize: 16,
                            height: 1.75,
                          ),
                          onTapUrl: _openContentUrl,
                        )
                      else
                        const Text('该内容类型将在后续版本开放。'),
                      const Divider(height: 40),
                      _ContentInteractionSection(
                        interaction: _interaction,
                        error: _interactionError,
                        controller: _commentController,
                        submitting: _submittingInteraction,
                        onRetry: _loadInteraction,
                        onReact: _react,
                        onSubmit: _submitComment,
                        onDelete: _deleteComment,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentInteractionSection extends StatelessWidget {
  const _ContentInteractionSection({
    required this.interaction,
    required this.error,
    required this.controller,
    required this.submitting,
    required this.onRetry,
    required this.onReact,
    required this.onSubmit,
    required this.onDelete,
  });

  final ContentInteraction? interaction;
  final String? error;
  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onRetry;
  final ValueChanged<String> onReact;
  final VoidCallback onSubmit;
  final ValueChanged<ContentComment> onDelete;

  @override
  Widget build(BuildContext context) {
    if (error != null && interaction == null) {
      return Row(children: [
         Icon(Icons.info_outline, color: AppTheme.muted),
        const SizedBox(width: 8),
        Expanded(
            child: Text(error!, style:  TextStyle(color: AppTheme.muted))),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ]);
    }
    final data = interaction;
    if (data == null) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: submitting ? null : () => onReact('like'),
              icon: Icon(data.userReaction == 'like'
                  ? Icons.thumb_up
                  : Icons.thumb_up_outlined),
              label: Text('有帮助 ${data.likeCount}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: data.userReaction == 'like'
                    ? AppTheme.primaryBlue
                    : AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: submitting ? null : () => onReact('dislike'),
              icon: Icon(data.userReaction == 'dislike'
                  ? Icons.thumb_down
                  : Icons.thumb_down_outlined),
              label: Text('没帮助 ${data.dislikeCount}'),
            ),
          ),
        ]),
        const SizedBox(height: 26),
        Text('评论 ${data.comments.length}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(hintText: '说说你的看法…'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: submitting ? null : onSubmit,
            child: const Text('发表评论'),
          ),
        ),
        const SizedBox(height: 16),
        if (data.comments.isEmpty)
           Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: Text('还没有评论', style: TextStyle(color: AppTheme.muted))),
          )
        else
          for (final comment in data.comments)
            _CommentRow(comment: comment, onDelete: onDelete),
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.onDelete});
  final ContentComment comment;
  final ValueChanged<ContentComment> onDelete;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 18, child: Text(comment.authorName.characters.first)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                      child: Text(comment.authorName,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  if (comment.isMine)
                    IconButton(
                      tooltip: '删除评论',
                      onPressed: () => onDelete(comment),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                ]),
                Text(comment.content, style: const TextStyle(height: 1.5)),
                if (comment.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(DateFormat('MM-dd HH:mm').format(comment.createdAt!),
                      style:
                           TextStyle(color: AppTheme.muted, fontSize: 12)),
                ],
              ])),
        ]),
      );
}

class _CardContent extends StatelessWidget {
  const _CardContent({required this.detail});

  final ContentDetail detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail.lead.isNotEmpty)
          Text(
            detail.lead,
            style: const TextStyle(
                fontSize: 17, height: 1.7, fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 18),
        for (var i = 0; i < detail.points.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xff0ea5a8),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail.points[i],
                      style: const TextStyle(fontSize: 16, height: 1.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (detail.tip.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: const Color(0xfffffbeb),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xfffde68a)),
            ),
            child: Text(
              '小贴士\n${detail.tip}',
              style: const TextStyle(height: 1.6, color: Color(0xff854d0e)),
            ),
          ),
        ],
      ],
    );
  }
}
