import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Placeholder for Project List Screen (will be created in the next step)
import 'package:latex_editor/screens/project_list_screen.dart';

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
      theme: ThemeData(
        colorSchemeSeed: Colors.blue, // Recommended for Material 3
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue, // Recommended for Material 3
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system, // Or allow user to choose
      home: const ProjectListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
