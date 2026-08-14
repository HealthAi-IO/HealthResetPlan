import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';

void main() {
  test('今日完成率按实际任务数量计算', () {
    final now = DateTime.now();
    final data = HealthDashboardData(
      profile: null,
      indicators: const [],
      plans: [
        PlanRecordData(
          type: 'exercise',
          planDate: now.millisecondsSinceEpoch,
          payload: const {},
          aiProvider: 'local',
          aiModel: 'rules',
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
      ],
      clockRecords: [
        ClockRecordData(
          type: 'meal',
          status: 'done',
          clockAt: now.millisecondsSinceEpoch,
          note: '',
          photoPath: '',
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
      ],
      reminders: const [],
    );

    expect(data.todayTaskTypes(), {'meal', 'weight', 'exercise'});
    expect(data.todayCompletion, closeTo(1 / 3, 0.001));
  });

  test('跳过任务不会增加完成率', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final data = HealthDashboardData(
      profile: null,
      indicators: const [],
      plans: const [],
      clockRecords: [
        ClockRecordData(
          type: 'weight',
          status: 'skip',
          clockAt: now,
          note: '',
          photoPath: '',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      reminders: const [],
    );

    expect(data.todayTaskTypes(), {'meal', 'weight'});
    expect(data.todayCompletion, 0);
  });

  test('首页任务显示三餐、多次用药和当天计划的真实进度', () {
    final day = DateTime(2026, 8, 14);
    final createdAt = day.millisecondsSinceEpoch;
    final tasks = buildHomeTodayTasks(
      date: day,
      plans: [
        PlanRecordData(
          type: 'exercise',
          planDate: createdAt,
          payload: const {'summary': '快走 · 30 分钟 · 中等强度'},
          aiProvider: 'local',
          aiModel: 'rules',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      reminders: [
        ReminderData(
          id: 8,
          type: 'medicine',
          remindAt: DateTime(2026, 8, 14, 8).millisecondsSinceEpoch,
          payload: {
            'medicineName': '测试药物',
            'dailyTimes': const [
              {'hour': 8, 'minute': 0},
              {'hour': 20, 'minute': 0},
            ],
            'actionHistory': const {'2026-08-14 08:00': 'taken'},
          },
          channel: 'local',
          status: 'pending',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      clockRecords: const [],
      mealRecords: [_meal(day, 'breakfast')],
      indicators: const [],
    );

    expect(tasks.map((task) => task.type),
        ['meal', 'exercise', 'medicine', 'weight']);
    expect(tasks[0].progressText, '已完成 1/3');
    expect(tasks[0].nextMealType, 'lunch');
    expect(tasks[1].description, '快走 · 30 分钟 · 中等强度');
    expect(tasks[2].progressText, '已处理 1/2');
    expect(tasks[2].reminderId, 8);
    expect(tasks[3].requiredToday, isFalse);
    expect(homeTodayTaskCompletion(tasks), closeTo(2 / 6, 0.001));
  });

  test('用药跳过后计入已处理并且不会继续作为下一次任务', () {
    final day = DateTime(2026, 8, 14);
    final createdAt = day.millisecondsSinceEpoch;
    final tasks = buildHomeTodayTasks(
      date: day,
      plans: const [],
      reminders: [
        ReminderData(
          id: 9,
          type: 'medicine',
          remindAt: DateTime(2026, 8, 14, 8).millisecondsSinceEpoch,
          payload: {
            'medicineName': '测试药物',
            'dailyTimes': const [
              {'hour': 8, 'minute': 0},
              {'hour': 20, 'minute': 0},
            ],
            'actionHistory': const {'2026-08-14 08:00': 'skipped'},
          },
          channel: 'local',
          status: 'pending',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      clockRecords: const [],
      mealRecords: const [],
      indicators: const [],
    );

    final medicine = tasks.firstWhere((task) => task.type == 'medicine');
    expect(medicine.progressText, '已处理 1/2');
    expect(medicine.description, contains('20:00'));
    expect(medicine.description, contains('跳过 1'));
  });

  test('称重只在当天计划明确要求体重时计入完成率', () {
    final day = DateTime(2026, 8, 14);
    final createdAt = day.millisecondsSinceEpoch;
    List<HomeTodayTaskData> tasksFor(String item) => buildHomeTodayTasks(
          date: day,
          plans: [
            PlanRecordData(
              type: 'measurement',
              planDate: createdAt,
              payload: {
                'summary': '每日测量',
                'items': [item],
              },
              aiProvider: 'local',
              aiModel: 'rules',
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
          ],
          reminders: const [],
          clockRecords: const [],
          mealRecords: const [],
          indicators: const [],
        );

    expect(tasksFor('晚间测量血压')[3].requiredToday, isFalse);
    expect(tasksFor('晨起、早餐前记录体重')[3].requiredToday, isTrue);
  });
}

MealRecordData _meal(DateTime day, String type) => MealRecordData(
      clientId: 'meal-$type',
      name: '测试餐食',
      mealType: type,
      eatenAt: DateTime(day.year, day.month, day.day, 8).millisecondsSinceEpoch,
      imagePath: '',
      totalCalories: 300,
      proteinG: 10,
      carbsG: 30,
      fatG: 8,
      healthScore: 8,
      glycemicLoad: 10,
      foods: const [],
      nutrition: const {},
      createdAt: day.millisecondsSinceEpoch,
      updatedAt: day.millisecondsSinceEpoch,
    );
