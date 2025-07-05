import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latex_editor/models/project_model.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart'; // For generating unique IDs

const String _projectsPrefsKey = 'latex_editor_projects';
const String _projectsBaseDirName = 'latex_projects';

class ProjectListNotifier extends StateNotifier<List<Project>> {
  ProjectListNotifier() : super([]) {
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final String? projectsJson = prefs.getString(_projectsPrefsKey);
    state = decodeProjects(projectsJson);
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_projectsPrefsKey, encodeProjects(state));
  }

  Future<Project?> createNewProject(String name) async {
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String projectsParentDirPath = '${appDocDir.path}/$_projectsBaseDirName';
      final Directory projectsParentDir = Directory(projectsParentDirPath);

      if (!await projectsParentDir.exists()) {
        await projectsParentDir.create(recursive: true);
      }

      final String projectId = const Uuid().v4();
      final String projectDirPath = '$projectsParentDirPath/$projectId';
      final Directory projectDir = Directory(projectDirPath);
      await projectDir.create();

      final String mainTexFileName = 'main.tex';
      final File mainTexFile = File('${projectDir.path}/$mainTexFileName');

      // Default LaTeX content
      const String defaultTexContent = '''
\\documentclass[12pt]{article}

\\title{${name.replaceAllMapped(RegExp(r'[^\w\s]'), (match) => '')}} % Sanitize title a bit
\\author{Your Name}
\\date{\\today}

\\begin{document}
\\maketitle

Hello, this is your new LaTeX project: $name!

\\end{document}
''';
      await mainTexFile.writeAsString(defaultTexContent);

      final newProject = Project(
        id: projectId,
        name: name,
        mainTexPath: mainTexFileName, // Relative path
        lastModified: DateTime.now(),
        projectDirPath: projectDir.path, // Absolute path
      );

      state = [...state, newProject];
      await _saveProjects();
      return newProject;
    } catch (e) {
      // Handle errors (e.g., log them, show a user-friendly message)
      print('Error creating project: $e');
      return null;
    }
  }

  Future<String?> getTexFileContent(Project project) async {
    try {
      final File texFile = File('${project.projectDirPath}/${project.mainTexPath}');
      if (await texFile.exists()) {
        return await texFile.readAsString();
      }
    } catch (e) {
      print('Error reading TeX file for project ${project.id}: $e');
    }
    return null;
  }

  Future<bool> saveTexFileContent(Project project, String content) async {
    try {
      final File texFile = File('${project.projectDirPath}/${project.mainTexPath}');
      await texFile.writeAsString(content);

      // Update lastModified timestamp
      final updatedProject = project..lastModified = DateTime.now();
      state = [
        for (final p in state)
          if (p.id == updatedProject.id) updatedProject else p,
      ];
      await _saveProjects();
      return true;
    } catch (e) {
      print('Error saving TeX file for project ${project.id}: $e');
      return false;
    }
  }

  Future<void> deleteProject(String projectId) async {
    final projectToDelete = state.firstWhere((p) => p.id == projectId, orElse: () => throw Exception("Project not found"));

    try {
      final projectDir = Directory(projectToDelete.projectDirPath);
      if (await projectDir.exists()) {
        await projectDir.delete(recursive: true);
      }
    } catch (e) {
      print('Error deleting project directory for ${projectToDelete.id}: $e');
      // Decide if we should still remove it from the list or not.
      // For now, we'll remove it from the list even if directory deletion fails.
    }

    state = state.where((project) => project.id != projectId).toList();
    await _saveProjects();
  }

  Future<void> renameProject(String projectId, String newName) async {
    state = state.map((project) {
      if (project.id == projectId) {
        return project..name = newName..lastModified = DateTime.now();
      }
      return project;
    }).toList();
    await _saveProjects();
  }
}

final projectListProvider = StateNotifierProvider<ProjectListNotifier, List<Project>>((ref) {
  return ProjectListNotifier();
});

// Provider to get a single project by ID (useful for EditorScreen)
final projectByIdProvider = Provider.family<Project?, String>((ref, projectId) {
  final projects = ref.watch(projectListProvider);
  try {
    return projects.firstWhere((p) => p.id == projectId);
  } catch (e) {
    return null; // Project not found
  }
});
