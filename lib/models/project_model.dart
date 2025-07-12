import 'dart:convert';

class Project {
  final String id;
  String name;
  String mainTexPath; // Relative to project directory
  DateTime lastModified;
  String projectDirPath; // Absolute path to the project directory

  Project({
    required this.id,
    required this.name,
    required this.mainTexPath,
    required this.lastModified,
    required this.projectDirPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mainTexPath': mainTexPath,
      'lastModified': lastModified.toIso8601String(),
      'projectDirPath': projectDirPath,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      mainTexPath: json['mainTexPath'] as String,
      lastModified: DateTime.parse(json['lastModified'] as String),
      projectDirPath: json['projectDirPath'] as String,
    );
  }
}

// Helper functions for encoding/decoding a list of projects for SharedPreferences
String encodeProjects(List<Project> projects) {
  return json.encode(
    projects.map<Map<String, dynamic>>((project) => project.toJson()).toList(),
  );
}

List<Project> decodeProjects(String? projectsJson) {
  if (projectsJson == null || projectsJson.isEmpty) {
    return [];
  }
  final List<dynamic> decodedJson = json.decode(projectsJson) as List<dynamic>;
  return decodedJson.map<Project>((jsonItem) => Project.fromJson(jsonItem as Map<String, dynamic>)).toList();
}
