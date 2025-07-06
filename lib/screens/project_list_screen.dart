import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latex_editor/models/project_model.dart';
import 'package:latex_editor/providers/project_provider.dart';
import 'package:latex_editor/screens/editor_screen.dart';

class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  void _showCreateProjectDialog(BuildContext context, WidgetRef ref) {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Create New Project'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Project Name'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Create'),
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  Navigator.of(dialogContext).pop(); // Close dialog first
                  final newProject = await ref
                      .read(projectListProvider.notifier)
                      .createNewProject(nameController.text);
                  if (newProject != null && context.mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Project "${newProject.name}" created!')),
                    );
                    // Optionally navigate to the editor screen for the new project
                    // Navigator.push(
                    //   context,
                    //   MaterialPageRoute(
                    //     builder: (context) => EditorScreen(projectId: newProject.id),
                    //   ),
                    // );
                  } else if (context.mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to create project.')),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showRenameProjectDialog(BuildContext context, WidgetRef ref, Project project) {
    final TextEditingController nameController = TextEditingController(text: project.name);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Rename Project'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New Project Name'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Rename'),
              onPressed: () async {
                if (nameController.text.isNotEmpty && nameController.text != project.name) {
                  await ref.read(projectListProvider.notifier).renameProject(project.id, nameController.text);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Project renamed to "${nameController.text}"')),
                    );
                  }
                }
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, WidgetRef ref, Project project) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Project?'),
          content: Text('Are you sure you want to delete "${project.name}"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () async {
                await ref.read(projectListProvider.notifier).deleteProject(project.id);
                 Navigator.of(dialogContext).pop(); // Close dialog
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Project "${project.name}" deleted.')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Project> projects = ref.watch(projectListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LaTeX Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Show app info or settings
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('LaTeX Editor'),
                  content: const Text('Version 1.0.0\nCreated with Flutter.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: projects.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_open, size: 60, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No projects yet.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Create New Project'),
                    onPressed: () => _showCreateProjectDialog(context, ref),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index];
                return Card(
                  elevation: 1.0, // Reduce elevation for a flatter look with Yaru
                  margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: ListTile(
                    leading: const Icon(Icons.article_outlined), // Consider a more specific LaTeX icon
                    title: Text(project.name),
                    subtitle: Text('Last modified: ${project.lastModified.toLocal().toString().substring(0, 16)}'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditorScreen(projectId: project.id),
                        ),
                      );
                    },
                    onLongPress: () {
                      // Show context menu (delete, rename)
                      showModalBottomSheet(
                        context: context,
                        builder: (sheetContext) {
                          return Wrap(
                            children: <Widget>[
                              ListTile(
                                leading: const Icon(Icons.edit_outlined),
                                title: const Text('Rename'),
                                onTap: () {
                                  Navigator.pop(sheetContext); // Close bottom sheet
                                  _showRenameProjectDialog(context, ref, project);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.delete_outline, color: Colors.red),
                                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                                onTap: () {
                                  Navigator.pop(sheetContext); // Close bottom sheet
                                  _showDeleteConfirmDialog(context, ref, project);
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateProjectDialog(context, ref),
        label: const Text('New Project'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}
