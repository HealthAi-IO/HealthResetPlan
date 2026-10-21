import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/features/routine/routine_goal_dialog.dart';

void main() {
  testWidgets('goals and wheels fit a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const Scaffold(
          body: RoutineGoalDialog(settings: {
        'restTargetHours': 8.25,
        'wakeTarget': '07:00',
        'bedTarget': '23:00',
        'wakeReminderMode': 'alarm',
        'bedReminder': true,
        'bedReminderLeadMinutes': 30,
        'wakeReminderDays': [1, 6],
      })),
    ));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('目标休息时长'));
    await tester.tap(find.text('目标休息时长'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
  });

  testWidgets('reminder modes, lead and weekdays stay draft until saved',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
          onPressed: () async {
            saved = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => const RoutineGoalDialog(settings: {
                      'wakeTarget': '07:00',
                      'bedTarget': '23:00',
                    }));
          },
          child: const Text('打开'));
    })));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    Future<void> select(String label, String option, {int index = 0}) async {
      final field = find.text(label).at(index);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.text(option)));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    }

    await select('起床提醒', '手机系统闹钟');
    await select('重复日期', '工作日');
    await select('重复日期', '自选星期');
    await tester.ensureVisible(find.text('周六'));
    await tester.tap(find.text('周六'));
    await tester.pumpAndSettle();
    await select('睡前提醒', '提前 30 分钟');
    await select('重复日期', '工作日', index: 1);
    expect(saved, isNull);
    await tester.tap(find.text('保存并设置闹钟'));
    await tester.pumpAndSettle();
    expect(saved?['wakeReminderMode'], 'alarm');
    expect(saved?['wakeReminder'], false);
    expect(saved?['wakeReminderDays'], [1, 2, 3, 4, 5, 6]);
    expect(saved?['bedReminder'], true);
    expect(saved?['bedReminderLeadMinutes'], 30);
    expect(saved?['bedReminderDays'], [1, 2, 3, 4, 5]);
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel choices stay local until save; clearing disables reminder',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
          onPressed: () async {
            saved = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => const RoutineGoalDialog(settings: {
                      'wakeTarget': '07:00',
                      'bedTarget': '23:00',
                      'restTargetHours': 8.0,
                      'wakeReminder': true,
                    }));
          },
          child: const Text('打开'));
    })));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('起床时间'));
    await tester.pumpAndSettle();
    final wheels = find.byType(ListWheelScrollView);
    tester.widget<ListWheelScrollView>(wheels.at(0)).controller!.jumpTo(9 * 52);
    tester
        .widget<ListWheelScrollView>(wheels.at(1))
        .controller!
        .jumpTo(15 * 52);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(find.text('07:00'), findsOneWidget);
    await tester.tap(find.text('起床时间'));
    await tester.pumpAndSettle();
    tester
        .widget<ListWheelScrollView>(find.byType(ListWheelScrollView).at(0))
        .controller!
        .jumpTo(9 * 52);
    tester
        .widget<ListWheelScrollView>(find.byType(ListWheelScrollView).at(1))
        .controller!
        .jumpTo(15 * 52);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('09:15'), findsOneWidget);
    await tester.ensureVisible(find.text('目标休息时长'));
    await tester.tap(find.text('目标休息时长'));
    await tester.pumpAndSettle();
    final durationWheel =
        tester.widget<ListWheelScrollView>(find.byType(ListWheelScrollView));
    expect(durationWheel.childDelegate.estimatedChildCount, 61);
    durationWheel.controller!.jumpTo(60 * 52);
    await tester.pumpAndSettle();
    expect(find.text('16 小时'), findsOneWidget);
    durationWheel.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('1 小时'), findsOneWidget);
    tester
        .widget<ListWheelScrollView>(find.byType(ListWheelScrollView))
        .controller!
        .jumpTo(29 * 52);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('8 小时 15 分钟'), findsOneWidget);
    expect(saved, isNull);
    await tester.ensureVisible(find.byTooltip('清除起床时间'));
    await tester.tap(find.byTooltip('清除起床时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved?['wakeTarget'], isNull);
    expect(saved?['wakeReminder'], false);
    expect(saved?['bedTarget'], '23:00');
    expect(saved?['restTargetHours'], 8.25);
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
  });
}
