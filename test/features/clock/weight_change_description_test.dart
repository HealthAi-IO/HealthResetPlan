import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/features/clock/clock_page.dart';

void main() {
  test('体重变化文案区分持平、下降和上升', () {
    expect(weightChangeDescription(65, null), '今天的体重记录已经保存');
    expect(weightChangeDescription(65, 65), '与上次持平');
    expect(weightChangeDescription(64.5, 65), '较上次下降 0.5 kg');
    expect(weightChangeDescription(65.5, 65), '较上次上升 0.5 kg');
  });
}
