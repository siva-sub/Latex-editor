import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latex_editor/screens/project_list_screen.dart';
import 'package:yaru/yaru.dart'; // Import Yaru package

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LaTeX Editor',
      theme: yaruLightTheme, // Apply Yaru light theme
      darkTheme: yaruDarkTheme, // Apply Yaru dark theme
      themeMode: ThemeMode.system,
      home: const ProjectListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
