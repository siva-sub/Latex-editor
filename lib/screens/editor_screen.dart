import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latex_editor/models/project_model.dart';
import 'package:latex_editor/providers/project_provider.dart';
import 'package:process_run/process_run.dart';
import 'package:latex_editor/screens/pdf_view_screen.dart';
import 'package:latex_editor/utils/tectonic_installer.dart';
import 'dart:async'; // For Timer (debouncer)
import 'package:latex_editor/utils/pandoc_installer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/languages/tex.dart';
import 'package:latex_editor/providers/pdf_provider.dart';

enum MessageType { info, success, error, warning }

class EditorScreen extends ConsumerStatefulWidget {
  final String projectId;

  const EditorScreen({super.key, required this.projectId});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  CodeController? _texContentController; // Changed to CodeController (nullable for late init)
  bool _isLoading = true;
  Project? _currentProjectDetails;
  bool _isCompiling = false;
  String _compilationLogs = '';
  bool _pdfGeneratedSuccessfully = false;

  Timer? _debounceTimer;
  final Duration _debounceDuration = const Duration(seconds: 2);

  String _statusBarMessage = "Initializing..."; // Initial before initState
  MessageType _statusBarMessageType = MessageType.info;
  bool _isAutoCompiling = false;

  @override
  void initState() {
    super.initState();
    _statusBarMessage = "Loading..."; // Set in initState
    _loadProjectData().then((_) {
      if (mounted) {
        setState(() {
          // Set to Ready only if no other status was set during load (e.g. error)
          if (_statusBarMessage == "Loading..." || _statusBarMessage == "Initializing...") {
            _statusBarMessage = "Ready";
            _statusBarMessageType = MessageType.info;
          }
        });
      }
      if (_texContentController != null) {
        _texContentController!.addListener(_onTextChanged);
      }
    });
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {
      _statusBarMessage = "Editing...";
      _statusBarMessageType = MessageType.info;
    });
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) {
        // print("Debounce tick: Auto-compilation to be triggered for project: ${_currentProjectDetails?.name}");
        if (!_isCompiling && !_isAutoCompiling) { // Don't trigger if any compile is running
          _triggerAutoCompilation();
        } else {
          setState(() {
             _statusBarMessage = "Ready (compilation pending)"; // Or some other status
             _statusBarMessageType = MessageType.info;
          });
        }
      }
    });
  }

  Future<void> _triggerAutoCompilation() async {
    if (_isCompiling || _isAutoCompiling) {
      print("Auto-compilation skipped: A compilation is already in progress.");
      // Optionally update status bar: e.g., "Auto-compile deferred: busy"
      return;
    }
    if (_currentProjectDetails == null) {
      print("Auto-compilation skipped: No project loaded.");
      return;
    }

    // print("Triggering auto-compilation for ${ _currentProjectDetails!.name}");
    if (!mounted) return;
    setState(() {
      _isAutoCompiling = true;
      _statusBarMessage = "Auto-compiling...";
      _statusBarMessageType = MessageType.info;
    });

    await _compileProject(isAutoCompile: true);

    if (mounted) {
      setState(() {
        _isAutoCompiling = false;
        // _compileProject will set the final status message (success/error)
        // If not, set a default "Ready" or "Last compiled..." status here.
        if (!_isCompiling && _statusBarMessage == "Auto-compiling...") { // If compile didn't update status
           _statusBarMessage = _pdfGeneratedSuccessfully ? "Preview up-to-date" : "Ready";
           _statusBarMessageType = _pdfGeneratedSuccessfully ? MessageType.success : MessageType.info;
        }
      });
    }
  }

  Future<void> _loadProjectData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _statusBarMessage = "Loading project...";
      _statusBarMessageType = MessageType.info;
    });

    _currentProjectDetails = ref.read(projectByIdProvider(widget.projectId));

    if (_currentProjectDetails != null) {
      final content = await ref.read(projectListProvider.notifier).getTexFileContent(_currentProjectDetails!);
      if (mounted) {
        final currentTheme = Theme.of(context).brightness == Brightness.dark ? atomOneDarkTheme : githubTheme;
        _texContentController ??= CodeController(
            language: tex,
            theme: currentTheme, // Apply theme dynamically
            text: content ?? '% Error: Could not load TeX file.\n');

        if (content == null && _texContentController!.text.startsWith('% Error')) {
             ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error loading TeX file content.')),
            );
        } else if (_texContentController!.text != content) {
            _texContentController!.text = content ?? '';
        }

      }
    } else {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Project with ID ${widget.projectId} not found.')),
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
        // If still "Loading project...", change to "Ready"
        if (_statusBarMessage == "Loading project..." || _statusBarMessage == "Loading...") {
            _statusBarMessage = "Ready";
            _statusBarMessageType = MessageType.info;
        }
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
    _texContentController?.removeListener(_onTextChanged); // Remove listener
    _texContentController?.dispose();
    _debounceTimer?.cancel(); // Cancel timer
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
          _texContentController?.text ?? '', // Use text from controller
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

  Future<void> _compileProject({bool isAutoCompile = false}) async {
    if (_currentProjectDetails == null) {
      if (!isAutoCompile) { // Only show SnackBar for manual compiles
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot compile: Project details not loaded.')),
        );
      }
      );
      return;
    }
    if (_isCompiling) {
      if (!isAutoCompile) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compilation already in progress.')),
        );
      }
      return;
    }

    // For auto-compile, save silently. For manual, save can show usual feedback.
    // _saveContent already shows a SnackBar, which is fine for manual.
    // For auto-compile, we might want a truly silent save if _saveContent could be parameterized.
    // For now, the SnackBar from _saveContent will still appear.
    await _saveContent(); // Shows its own "Saved" SnackBar for manual, which might be okay.

    if (!mounted) return;
    setState(() {
      _isCompiling = true; // This is for manual compilation context mainly
      _compilationLogs = 'Starting compilation...\n';
      if (!isAutoCompile) {
        _statusBarMessage = "Compiling...";
        _statusBarMessageType = MessageType.info;
      }
      // For auto-compile, _statusBarMessage is already "Auto-compiling..."
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

          // Update the PDF path provider
          final pdfFileName = project.mainTexPath.replaceAll(RegExp(r'\.tex$'), '.pdf');
          final pdfPath = '${project.projectDirPath}/$pdfFileName';
          ref.read(activeProjectPdfPathProvider.notifier).state = pdfPath;
          ref.read(pdfGenerationKeyProvider.notifier).state = UniqueKey(); // Force refresh

          if (!isAutoCompile) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Compilation successful!')),
            );
          }
          _statusBarMessage = "Preview up-to-date (${TimeOfDay.now().format(context)})";
          _statusBarMessageType = MessageType.success;
        } else {
          _compilationLogs += 'Compilation failed with exit code: ${result.exitCode}\n';
          _pdfGeneratedSuccessfully = false;
          if (!isAutoCompile) {
             ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Compilation failed. Exit code: ${result.exitCode}')),
             );
          }
          _statusBarMessage = "Compilation failed (exit code: ${result.exitCode})";
          _statusBarMessageType = MessageType.error;
        }
      });
    } on ProcessException catch (e) {
      if(mounted) {
        setState(() {
          _compilationLogs += 'Error running Tectonic: $e\n';
          _compilationLogs += 'Make sure Tectonic is installed and in your PATH.\n';
          _statusBarMessage = "Tectonic not found or error.";
          _statusBarMessageType = MessageType.error;
          if (!isAutoCompile) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: Tectonic command not found or failed to run.')),
            );
          }
        });
      }
       print('Tectonic execution error: $e');
    } catch (e) {
      if(mounted) {
        setState(() {
          _compilationLogs += 'An unexpected error occurred during compilation: $e\n';
          _statusBarMessage = "Compilation error.";
          _statusBarMessageType = MessageType.error;
        });
      }
      print('Unexpected compilation error: $e');
    } finally {
      if(mounted) {
        setState(() {
          _isCompiling = false; // This is for manual compilation context
          // _isAutoCompiling is handled in _triggerAutoCompilation
          if (_statusBarMessage.contains("Compiling...") || _statusBarMessage.contains("Auto-compiling...")) {
             // If no specific success/error message was set by compile logic (e.g. due to early exit or unexpected flow)
             _statusBarMessage = "Ready";
             _statusBarMessageType = MessageType.info;
          }
        });
      }
      });
    }
    // For auto-compile, only show logs if there was an error.
    // For manual compile, always show logs.
    if (!isAutoCompile || result.exitCode != 0) {
      _showCompilationLogs();
    } else if (isAutoCompile && result.exitCode == 0) {
      // Optionally, a very subtle feedback for successful auto-compile
      // For now, the PDF refresh (next step) will be the main feedback.
      print("Auto-compilation successful. PDF updated.");
      // TODO: Update a status bar message (Step 4)
    }
  }

  void _viewPdf() {
    if (_currentProjectDetails == null) {
      ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Cannot view PDF: No project loaded.')),
      );
      return;
    }
    if (!_pdfGeneratedSuccessfully) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Cannot view PDF: No successful compilation yet or PDF is missing.')),
      );
      return;
    }

    // The activeProjectPdfPathProvider should have been set by a successful compile.
    // PdfViewScreen will pick it up.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PdfViewScreen(), // Constructor no longer needs filePath
      ),
    );
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24.0), // Adjust height as needed
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            color: _getStatusBackgroundColor(context, _statusBarMessageType),
            child: Row(
              children: [
                if (_isAutoCompiling || (_isCompiling && _statusBarMessage.toLowerCase().contains("compiling")))
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                Expanded(
                  child: Text(
                    _statusBarMessage,
                    style: TextStyle(color: _getStatusForegroundColor(context, _statusBarMessageType)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // Keep manual compilation progress in actions for clarity, or remove if status bar is enough
          if (_isCompiling && !_isAutoCompiling) // Show only for manual main compilation
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          IconButton(
            icon: const Icon(Icons.save_alt_outlined),
            onPressed: _isCompiling ? null : _saveContent,
            tooltip: 'Save Document',
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined), // Or Icons.output / Icons.upload_file
            onPressed: _isCompiling ? null : _showExportOptionsDialog,
            tooltip: 'Export Project As...',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: _texContentController == null
            ? const Center(child: CircularProgressIndicator()) // Show loading if controller is not ready
            : CodeTheme(
                data: CodeThemeData(
                  styles: Theme.of(context).brightness == Brightness.dark
                          ? atomOneDarkTheme
                          : githubTheme
                ),
                child: CodeField(
                  controller: _texContentController!,
                  readOnly: _isCompiling,
                  expands: true,
                  maxLines: null, // Ensure it expands
                  minLines: null, // Ensure it expands
                  lineNumberStyle: const LineNumberStyle(width: 40), // Optional: show line numbers
                  textStyle: const TextStyle(fontFamily: 'monospace'), // Base text style
                  // background: monokaiSublimeTheme['root']?.backgroundColor, // Set background from theme
                ),
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

  void _showExportOptionsDialog() {
    if (_currentProjectDetails == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project not loaded.')),
      );
      return;
    }

    // Define available export formats
    // Key: User-facing label, Value: format argument for Pandoc (and file extension)
    Map<String, String> exportFormats = {
      'Word Document (.docx)': 'docx',
      'HTML Document (.html)': 'html',
      'Markdown (.md)': 'md',
      // TODO: Add more formats as needed, e.g., ODT, EPUB
    };

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Export Project As...'),
          content: SingleChildScrollView(
            child: ListBody(
              children: exportFormats.entries.map((entry) {
                return ListTile(
                  title: Text(entry.key),
                  onTap: () {
                    Navigator.of(dialogContext).pop(); // Close the dialog
                    _exportWithPandoc(entry.value, entry.key.substring(entry.key.lastIndexOf('(') + 1, entry.key.lastIndexOf(')'))); // Pass format and extension
                  },
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportWithPandoc(String format, String fileExtension) async {
    if (_currentProjectDetails == null) return;
    if (_isCompiling) { // Also check if already exporting with Pandoc if we add such a flag
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Another process is running.')));
      return;
    }

    await _saveContent(); // Ensure latest content is saved

    // TODO: Add a state flag like _isExportingWithPandoc if needed for UI feedback
    setState(() {
      // _isExportingWithPandoc = true; // If we add more specific UI feedback for this
      _compilationLogs = 'Starting Pandoc export to $format...\n'; // Reuse compilationLogs for now
    });
    _showCompilationLogs(); // Show logs modal

    final project = _currentProjectDetails!;
    final pandocCmd = await PandocInstaller.getPandocExecutablePath() ?? 'pandoc';

    // Define output directory and file name
    // For simplicity, save in a subdirectory within the project folder
    final exportsDir = Directory('${project.projectDirPath}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    // Sanitize project name for use in a filename
    final sanitizedProjectName = project.name.replaceAll(RegExp(r'[^\w\s-]'), '_').replaceAll(' ', '_');
    final outputFileName = '$sanitizedProjectName.$fileExtension';
    final outputFilePath = '${exportsDir.path}/$outputFileName';

    final shell = Shell(workingDirectory: project.projectDirPath, verbose: true);
    _compilationLogs += 'Using Pandoc command: $pandocCmd\n';
    _compilationLogs += 'Input file: ${project.mainTexPath}\n';
    _compilationLogs += 'Output file: $outputFilePath\n';
    _compilationLogs += 'Format: $format\n';
     setState(() {}); // Update logs displayed in modal

    try {
      // Pandoc command: pandoc input.tex -o output.ext
      final result = await shell.run('$pandocCmd ${project.mainTexPath} -o $outputFilePath');

      if (mounted) {
        setState(() {
          _compilationLogs += 'Pandoc process finished.\n';
          _compilationLogs += 'Stdout:\n${result.outText}\n';
          _compilationLogs += 'Stderr:\n${result.errText}\n';
          if (result.exitCode == 0) {
            _compilationLogs += 'Export successful to $outputFilePath!\n';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Exported to $outputFileName!'),
                action: SnackBarAction(
                  label: 'Share',
                  onPressed: () async {
                    final xfile = XFile(outputFilePath);
                    await Share.shareXFiles([xfile], text: 'Exported ${project.name} as $outputFileName');
                  },
                ),
              ),
            );
          } else {
            _compilationLogs += 'Pandoc export failed. Exit code: ${result.exitCode}\n';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Pandoc export failed. Exit code: ${result.exitCode}')),
            );
          }
        });
      }
    } on ProcessException catch (e) {
      if (mounted) {
        setState(() {
          _compilationLogs += 'Error running Pandoc: $e\n';
          _compilationLogs += 'Make sure Pandoc is installed and in your PATH.\n';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Pandoc command not found or failed to run.')),
        );
      }
      print('Pandoc execution error: $e');
    } catch (e) {
      if (mounted) {
        setState(() {
          _compilationLogs += 'An unexpected error occurred during Pandoc export: $e\n';
        });
      }
      print('Unexpected Pandoc export error: $e');
    } finally {
      if (mounted) {
        setState(() {
          // _isExportingWithPandoc = false; // Reset flag
        });
         // Re-render the logs modal if it's still open or call _showCompilationLogs again
         // For simplicity, the modal will auto-update as _compilationLogs changes if it's open.
      }
    }
  }

  Color _getStatusBackgroundColor(BuildContext context, MessageType type) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    switch (type) {
      case MessageType.success:
        return Colors.green.withOpacity(isDark ? 0.3 : 0.15);
      case MessageType.error:
        return Colors.red.withOpacity(isDark ? 0.3 : 0.15);
      case MessageType.warning:
        return Colors.orange.withOpacity(isDark ? 0.3 : 0.15);
      case MessageType.info:
      default:
        // For Yaru theme, use a subtle AppBar related color or a neutral one
        // return Theme.of(context).appBarTheme.backgroundColor?.withOpacity(0.5) ?? Theme.of(context).colorScheme.surface.withOpacity(0.1);
        // A slightly more distinct but still subtle approach for info:
        return Theme.of(context).colorScheme.onSurface.withOpacity(0.05);
    }
  }

  Color _getStatusForegroundColor(BuildContext context, MessageType type) {
    // Use default text colors which should contrast with the Yaru theme's background
    // For specific error/success, could use themed colors, but often onSurface is fine
    // if background provides enough indication.
    switch (type) {
      case MessageType.success:
        return Colors.green.shade700; // Darker green for light theme, lighter for dark if needed
      case MessageType.error:
        return Colors.red.shade700;
      case MessageType.warning:
        return Colors.orange.shade700;
      case MessageType.info:
      default:
        return Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
    }
  }
}
