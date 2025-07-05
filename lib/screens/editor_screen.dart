import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latex_editor/models/project_model.dart';
import 'package:latex_editor/providers/project_provider.dart';
import 'package:process_run/process_run.dart';
import 'package:latex_editor/screens/pdf_view_screen.dart';
import 'package:latex_editor/utils/tectonic_installer.dart'; // Added TectonicInstaller

class EditorScreen extends ConsumerStatefulWidget {
  final String projectId;

  const EditorScreen({super.key, required this.projectId});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late TextEditingController _texContentController;
  bool _isLoading = true;
  Project? _currentProjectDetails;
  bool _isCompiling = false;
  String _compilationLogs = '';
  bool _pdfGeneratedSuccessfully = false;

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
      }
    }

    if(mounted){
      _checkInitialPdfAvailability();
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkInitialPdfAvailability() async {
    if (_currentProjectDetails == null) return;
    final pdfFileName = _currentProjectDetails!.mainTexPath.replaceAll(RegExp(r'\.tex$'), '.pdf');
    final pdfPath = '${_currentProjectDetails!.projectDirPath}/$pdfFileName';
    final pdfFile = File(pdfPath);
    final exists = await pdfFile.exists();
    if (mounted) {
      setState(() {
        _pdfGeneratedSuccessfully = exists;
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
          _currentProjectDetails!,
          _texContentController.text,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Document saved!' : 'Failed to save document.')),
      );
      if (success) {
        setState(() {
          _currentProjectDetails?.lastModified = DateTime.now();
        });
        _checkInitialPdfAvailability();
      }
    }
  }

  Future<void> _compileProject() async {
    if (_currentProjectDetails == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot compile: Project details not loaded.')),
      );
      return;
    }
    if (_isCompiling) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compilation already in progress.')),
      );
      return;
    }

    await _saveContent();

    setState(() {
      _isCompiling = true;
      _compilationLogs = 'Starting compilation...\n';
      _pdfGeneratedSuccessfully = false;
    });

    final project = _currentProjectDetails!;
    var shell = Shell(workingDirectory: project.projectDirPath, verbose: true);
    String tectonicCommand = await TectonicInstaller.getTectonicExecutablePath() ?? 'tectonic';

    // Check if tectonicCommand is a full path or just a command.
    // If it's just 'tectonic', Shell will search PATH. If it's a path, it will use it directly.

    _compilationLogs += 'Using Tectonic command: $tectonicCommand\n';

    try {
      // Construct the command carefully if tectonicCommand could contain spaces (not typical for a command)
      // For simple command or full path, this is okay:
      final result = await shell.run('$tectonicCommand ${project.mainTexPath}');

      setState(() {
        _compilationLogs += 'Compilation finished.\n';
        _compilationLogs += 'Stdout:\n${result.outText}\n';
        _compilationLogs += 'Stderr:\n${result.errText}\n';
        if (result.exitCode == 0) {
          _compilationLogs += 'PDF generated successfully!\n';
          _pdfGeneratedSuccessfully = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Compilation successful!')),
          );
        } else {
          _compilationLogs += 'Compilation failed with exit code: ${result.exitCode}\n';
          _pdfGeneratedSuccessfully = false;
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Compilation failed. Exit code: ${result.exitCode}')),
          );
        }
      });
    } on ProcessException catch (e) {
      setState(() {
        _compilationLogs += 'Error running Tectonic: $e\n';
        _compilationLogs += 'Make sure Tectonic is installed and in your PATH.\n';
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Tectonic command not found or failed to run.')),
        );
      });
       print('Tectonic execution error: $e');
    } catch (e) {
      setState(() {
        _compilationLogs += 'An unexpected error occurred during compilation: $e\n';
      });
      print('Unexpected compilation error: $e');
    } finally {
      setState(() {
        _isCompiling = false;
      });
    }
    _showCompilationLogs();
  }

  void _viewPdf() {
    if (_currentProjectDetails == null) return;
    final pdfFileName = _currentProjectDetails!.mainTexPath.replaceAll(RegExp(r'\.tex$'), '.pdf');
    final pdfPath = '${_currentProjectDetails!.projectDirPath}/$pdfFileName';

    final pdfFile = File(pdfPath);
    pdfFile.exists().then((exists) {
      if (exists) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PdfViewScreen(filePath: pdfPath),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF not found. Please compile the project first.\nExpected at: $pdfPath')),
        );
      }
    }).catchError((e) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking for PDF: $e')),
      );
    });
  }

  void _showCompilationLogs() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          height: MediaQuery.of(context).size.height * 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Compilation Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(_compilationLogs, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
          if (_isCompiling)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          IconButton(
            icon: const Icon(Icons.save_alt_outlined),
            onPressed: _isCompiling ? null : _saveContent,
            tooltip: 'Save Document',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: TextField(
          controller: _texContentController,
          readOnly: _isCompiling,
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
              icon: _isCompiling
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.build_circle_outlined),
              label: Text(_isCompiling ? 'Compiling...' : 'Compile'),
              onPressed: (_currentProjectDetails == null || _isCompiling) ? null : () async {
                await _saveContent();
                if (_currentProjectDetails != null) {
                  _compileProject();
                }
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('View PDF'),
              onPressed: (_currentProjectDetails == null || _isCompiling || !_pdfGeneratedSuccessfully) ? null : () {
                if (_currentProjectDetails != null) {
                  _viewPdf();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
