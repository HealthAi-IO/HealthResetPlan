import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_theme.dart';
import '../../core/content/content_models.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/content_api.dart';

class ContentDetailPage extends StatefulWidget {
  const ContentDetailPage({super.key, required this.id});

  final int id;

  @override
  State<ContentDetailPage> createState() => _ContentDetailPageState();
}

class _ContentDetailPageState extends State<ContentDetailPage> {
  final ContentApi _api = sl<ContentApi>();
  ContentDetail? _detail;
  String? _error;

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
      await _api.markContentRead(widget.id);
    } catch (_) {
      if (mounted) setState(() => _error = '资讯不存在、已下架或网络暂时不可用');
    }
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
      backgroundColor: AppTheme.pageBg,
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
              const Icon(Icons.info_outline, size: 46, color: AppTheme.muted),
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
                        style: const TextStyle(
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
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 13),
                      ),
                      if (detail.summary.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          detail.summary,
                          style: const TextStyle(
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
                          textStyle: const TextStyle(
                            color: AppTheme.ink,
                            fontSize: 16,
                            height: 1.75,
                          ),
                          onTapUrl: _openContentUrl,
                        )
                      else
                        const Text('该内容类型将在后续版本开放。'),
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
