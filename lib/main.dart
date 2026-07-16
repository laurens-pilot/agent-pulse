import 'package:flutter/material.dart';

import 'src/ui/app_theme.dart';
import 'src/ui/dashboard_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CodexDashboardApp());
}

class CodexDashboardApp extends StatelessWidget {
  const CodexDashboardApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codex Pulse',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: home ?? const DashboardPage(),
    );
  }
}
