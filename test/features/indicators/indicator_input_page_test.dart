import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:health_reset_plan/core/data/health_models.dart';
import 'package:health_reset_plan/core/data/health_repository.dart';
import 'package:health_reset_plan/core/network/telemetry_api.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';
import 'package:health_reset_plan/features/indicators/indicator_input_page.dart';

void main() {
  test('血糖历史显示保留已记录精度', () {
    final entry = HealthIndicatorEntry(
      clientId: 'precision', type: 'glucose',
      payload: const {'glucoseMmol': 5.55}, source: 'manual',
      measuredAt: 0, createdAt: 0, updatedAt: 0,
    );
    expect(entry.displayValue, '5.55 mmol/L');
  });
  late _Repository repository;

  setUp(() {
    repository = _Repository();
    GetIt.instance.registerSingleton<HealthRepository>(repository);
    GetIt.instance.registerSingleton<TelemetryApi>(_Telemetry());
  });
  tearDown(() => GetIt.instance.reset());

  Future<void> open(WidgetTester tester, {String? type, HealthIndicatorEntry? existing}) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => IndicatorInputPage(defaultType: type, existing: existing),
        )),
        child: const Text('打开录入'),
      )),
    )));
    await tester.tap(find.text('打开录入'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('确认保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('新增保存留页，重复点击不产生第二条记录，可继续录入另一项', (tester) async {
    await open(tester);
    await save(tester);
    expect(find.text('录入健康指标'), findsOneWidget);
    expect(repository.savedTypes, ['weight']);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repository.savedTypes, ['weight']);
    expect(find.text('确认保存'), findsNothing);
    await tester.tap(find.text('血糖'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(repository.savedTypes, ['weight', 'glucose']);
    expect(find.text('录入健康指标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败保留输入，重试只保存一次', (tester) async {
    repository.failSave = true;
    await open(tester);
    await save(tester);
    expect(find.text('录入健康指标'), findsOneWidget);
    expect(repository.savedTypes, isEmpty);
    repository.failSave = false;
    await save(tester);
    expect(repository.savedTypes, ['weight']);
  });

  testWidgets('空血脂在确认提交前被拦截', (tester) async {
    await open(tester, type: 'lipid');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请至少填写一项血脂检查结果'), findsOneWidget);
    expect(find.text('确认保存'), findsNothing);
    expect(repository.savedTypes, isEmpty);
  });

  testWidgets('取消确认不提交，也不阻止下一次保存', (tester) async {
    await open(tester);
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('返回检查'));
    await tester.pumpAndSettle();
    expect(repository.savedTypes, isEmpty);
    await save(tester);
    expect(repository.savedTypes, ['weight']);
  });

  testWidgets('历史数据加载失败仍可以手动录入', (tester) async {
    repository.failLoad = true;
    await open(tester);
    expect(find.text('未能加载上次记录，可直接填写本次测量值'), findsOneWidget);
    expect(find.text('录入健康指标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选择日期后取消时间保留原测量时间', (tester) async {
    await open(tester);
    final original = find.textContaining('年').evaluate()
        .map((element) => (element.widget as Text).data)
        .whereType<String>().first;
    await tester.tap(find.text(original));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text(original), findsOneWidget);
  });

  testWidgets('历史血糖预填标明来源，保存保留原始精度', (tester) async {
    await open(tester, type: 'glucose');
    expect(find.textContaining('数值预填自'), findsOneWidget);
    await save(tester);
    expect(repository.savedPayloads.single['glucoseMmol'], 5.55);
  });

  testWidgets('血压同测心率与独立心率切换后保持各自数值', (tester) async {
    await open(tester, type: 'bp');
    await tester.tap(find.text('心率'));
    await tester.pumpAndSettle();
    await save(tester);
    await tester.tap(find.text('血压'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(repository.savedPayloads[0]['bpm'], 75);
    expect(repository.savedPayloads[1]['heartRate'], 66);
  });

  testWidgets('未来测量时间禁止保存', (tester) async {
    await open(tester, existing: HealthIndicatorEntry(
      id: 1, clientId: 'test', type: 'weight', payload: const {'weightKg': 59.0},
      source: 'manual', measuredAt: DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      createdAt: 0, updatedAt: 0,
    ));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('测量时间不能晚于现在，请重新选择'), findsOneWidget);
    expect(repository.savedTypes, isEmpty);
  });
}

class _Repository extends HealthRepository {
  _Repository() : super(database: AppDatabase.instance);
  final savedTypes = <String>[];
  final savedPayloads = <Map<String, dynamic>>[];
  bool failSave = false;
  bool failLoad = false;

  @override
  Future<List<HealthIndicatorEntry>> loadIndicators({String? type, int limit = 100}) async {
    if (failLoad) throw Exception('offline');
    final payload = switch (type) {
      'weight' => <String, dynamic>{'weightKg': 59.0},
      'glucose' => <String, dynamic>{'glucoseMmol': 5.55},
      'bp' => <String, dynamic>{'systolic': 120, 'diastolic': 80, 'heartRate': 66},
      'heart_rate' => <String, dynamic>{'bpm': 75},
      _ => null,
    };
    if (payload == null) return [];
    return [HealthIndicatorEntry(
      clientId: 'test', type: type!, payload: payload, source: 'manual',
      measuredAt: DateTime.now().millisecondsSinceEpoch,
      createdAt: 0, updatedAt: 0,
    )];
  }

  @override
  Future<int> addIndicator({required String type, required Map<String, dynamic> payload,
    String source = 'manual', DateTime? measuredAt, String? clockNote}) async {
    if (failSave) throw Exception('offline');
    savedTypes.add(type);
    savedPayloads.add(payload);
    return savedTypes.length;
  }
}

class _Telemetry extends Fake implements TelemetryApi {
  @override
  Future<void> record(String eventType) async {}
}
