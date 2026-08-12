import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

const Duration appActionSnackBarDuration = Duration(seconds: 5);

void showAppSnackBar(SnackBar snackBar) {
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(snackBar);
}
