import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'move_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF080B0A),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MoveApp());
}
