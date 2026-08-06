import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/storage/report_image_storage.dart';

void main() {
  test('local paths are not sent to the private file endpoint', () {
    expect(reportImageProvider('/data/user/0/cache/report.jpg'), isNull);
    expect(reportImageProvider(r'C:\Temp\report.jpg'), isNull);
    expect(
      reportImageProvider('files/747052151525/report.enc'),
      isA<NetworkImage>(),
    );
  });
}
