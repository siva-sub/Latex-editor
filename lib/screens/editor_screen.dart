import 'dart:io'; // For File operations if needed directly, though provider handles it
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latex_editor/models/project_model.dart';
import 'package:latex_editor/providers/project_provider.dart';

// No longer need a separate currentTexContentProvider if controller directly updates on save
// final currentTexContentProvider = StateProvider<String>((ref) => '');

class EditorScreen extends ConsumerStatefulWidget {
  final String projectId;

  const EditorScreen({super.key, required this.projectId});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late TextEditingController _texContentController;
  bool _isLoading = true;
  // Store the project details locally in the state
  Project? _currentProjectDetails;

  @override
  void initState() {
    super.initState();
    _texContentController = TextEditingController();
    _loadProjectData();
  }

  Future<void> _loadProjectData() async {
    setState(() {
      _isLoading = true;
    });

    // Fetch the project details once
    _currentProjectDetails = ref.read(projectByIdProvider(widget.projectId));

    if (_currentProjectDetails != null) {
      final content = await ref.read(projectListProvider.notifier).getTexFileContent(_currentProjectDetails!);
      if (mounted) {
        if (content != null) {
          _texContentController.text = content;
        } else {
          _texContentController.text = '% Error: Could not load TeX file.\n';
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error loading TeX file content.')),
          );
        }
      }
    } else {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Project with ID ${widget.projectId} not found.')),
        );
        // Consider popping the screen if project is not found
        // Navigator.of(context).pop();
      }
    }

    if(mounted){
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _texContentController.dispose();
    super.dispose();
  }

  Future<void> _saveContent() async {
    if (_currentProjectDetails == null) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot save: Project details not loaded.')),
      );
      return;
    }

    final success = await ref.read(projectListProvider.notifier).saveTexFileContent(
          _currentProjectDetails!, // Use the locally stored project details
          _texContentController.text,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Document saved!' : 'Failed to save document.')),
      );
      if (success) {
        // Optionally, refresh project details if lastModified is important to display immediately
        // _loadProjectData(); // Or just update the local _currentProjectDetails.lastModified
        setState(() {
          _currentProjectDetails?.lastModified = DateTime.now();
        });

      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the project provider to get the most up-to-date project name for the AppBar
    // This handles cases where the project might be renamed elsewhere.
    final projectForAppBar = ref.watch(projectByIdProvider(widget.projectId));

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(projectForAppBar?.name ?? 'Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentProjectDetails == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Project not found. It might have been deleted.'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Editing: ${projectForAppBar?.name ?? _currentProjectDetails!.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt_outlined),
            onPressed: _saveContent,
            tooltip: 'Save Document',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: TextField(
          controller: _texContentController,
          expands: true,
          maxLines: null,
          minLines: null,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter your LaTeX code here...',
          ),
          keyboardType: TextInputType.multiline,
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            TextButton.icon(
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Compile'),
              onPressed: () async {
                await _saveContent(); // Save before compiling
                if (_currentProjectDetails != null) {
                  // TODO: Implement compile functionality (Step 4)
                  // Pass _currentProjectDetails to the compile function
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Compile for "${_currentProjectDetails!.name}" (Not Implemented)')),
                  );
                }
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('View PDF'),
              onPressed: () {
                if (_currentProjectDetails != null) {
                  // TODO: Implement view PDF functionality (Step 5)
                  // Pass _currentProjectDetails to the view PDF function
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('View PDF for "${_currentProjectDetails!.name}" (Not Implemented)')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
