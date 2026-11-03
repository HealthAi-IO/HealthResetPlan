import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:health_reset_plan/app/app_settings_controller.dart';
import 'package:health_reset_plan/features/shell/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final entry in ['提醒设置', '趋势统计']) {
    testWidgets('侧栏$entry进入记录分支后可返回首页', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'senior_mode_v1': false});
      await appSettingsController.load();
      final router = GoRouter(initialLocation: '/home', routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(
            location: state.uri.path,
            navigationShell: shell,
            child: shell,
          ),
          branches: [
            for (final path in ['/home', '/plan', '/meals', '/records'])
              StatefulShellBranch(routes: [
                GoRoute(
                    path: path,
                    builder: (_, __) => Center(child: Text('page:$path')))
              ]),
          ],
        ),
        GoRoute(
            path: '/clock',
            redirect: (_, state) => Uri(
                    path: '/records',
                    queryParameters: state.uri.queryParameters)
                .toString()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(entry), 250,
          scrollable: find
              .descendant(
                  of: find.byType(Drawer), matching: find.byType(Scrollable))
              .first);
      await tester.tap(find.text(entry));
      await tester.pumpAndSettle();
      expect(find.text('page:/records'), findsOneWidget);
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          3);
      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      expect(find.text('page:/home'), findsOneWidget);
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0);
    });
  }

  testWidgets('普通模式与长辈模式使用独立导航', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'senior_mode_v1': false});
    await appSettingsController.load();
    addTearDown(() => appSettingsController.setSeniorMode(false));

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: appSettingsController,
        builder: (context, _) => const MaterialApp(
          home: AppShell(
            location: '/home',
            child: SizedBox(),
          ),
        ),
      ),
    );

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('饮食'), findsOneWidget);
    expect(find.text('今日'), findsNothing);
    expect(find.text('提醒'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).key,
      const ValueKey('regular-navigation'),
    );

    await appSettingsController.setSeniorMode(true);
    await tester.pumpAndSettle();

    expect(find.text('今日'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(find.text('计划'), findsNothing);
    expect(find.text('饮食'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).key,
      const ValueKey('senior-navigation'),
    );
  });

  testWidgets('平板宽度使用侧边导航而不是拉伸手机底栏', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'senior_mode_v1': false});
    await appSettingsController.load();

    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(location: '/home', child: SizedBox()),
      ),
    );

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('健康重启计划'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
  });
}
