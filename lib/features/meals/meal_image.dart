import 'package:flutter/material.dart';

import '../../core/auth/user_session.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';

class MealImage extends StatelessWidget {
  const MealImage({
    super.key,
    required this.path,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  final String path;
  final double width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final base =
        sl<ApiClient>().dio.options.baseUrl.replaceFirst(RegExp(r'/$'), '');
    final token = UserSession.instance.accessToken;
    return Image.network(
      '$base/files/content?objectKey=${Uri.encodeQueryComponent(path)}',
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
      width: width,
      height: height,
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 180),
          child: child,
        );
      },
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.restaurant_outlined),
      ),
    );
  }
}
