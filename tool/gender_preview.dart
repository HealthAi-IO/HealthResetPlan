import 'package:flutter/material.dart';
import 'package:health_reset_plan/app/app_theme.dart';
import 'package:health_reset_plan/features/profile/gender_selector.dart';

void main() => runApp(const GenderPreviewApp());

class GenderPreviewApp extends StatefulWidget {
  const GenderPreviewApp({super.key});

  @override
  State<GenderPreviewApp> createState() => _GenderPreviewAppState();
}

class _GenderPreviewAppState extends State<GenderPreviewApp> {
  String gender = 'female';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 72, 20, 32),
            children: [
              const Text(
                '基础档案',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text('完善后可用于计划计算'),
              const SizedBox(height: 24),
              const TextField(
                decoration: InputDecoration(labelText: '昵称'),
              ),
              const SizedBox(height: 12),
              GenderSelector(
                value: gender,
                onChanged: (value) => setState(() => gender = value),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(labelText: '出生年份'),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(labelText: '身高（cm）'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const TextField(
                decoration: InputDecoration(labelText: '体重（kg）'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
