import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latex_editor/providers/pdf_provider.dart'; // Import provider

class PdfViewScreen extends ConsumerStatefulWidget { // Changed to ConsumerStatefulWidget
  // No longer needs filePath directly, will get from provider
  const PdfViewScreen({super.key});

  @override
  ConsumerState<PdfViewScreen> createState() => _PdfViewScreenState(); // Changed state type
}

class _PdfViewScreenState extends ConsumerState<PdfViewScreen> { // Changed to ConsumerState
  int _totalPages = 0;
  int _currentPage = 0;
  bool pdfReady = false;
  PDFViewController? _pdfViewController;
  String? _errorMessage;
  // No filePath in constructor, it will come from provider.

  @override
  Widget build(BuildContext context) {
    final String? pdfPath = ref.watch(activeProjectPdfPathProvider);
    final Key? pdfKey = ref.watch(pdfGenerationKeyProvider); // Watch the key

    if (pdfPath == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("PDF Preview")),
        body: const Center(child: Text("No PDF has been compiled for the current project, or it's not available.")),
      );
    }

    // It's good practice to check file existence before passing to PDFView,
    // though PDFView itself has error handling.
    // This provides a clearer message if the file pointed to by the provider is missing.
    final pdfFile = File(pdfPath);
    if (!pdfFile.existsSync()) {
        return Scaffold(
            appBar: AppBar(title: const Text("PDF Preview Error")),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Error: PDF file not found at path:\n$pdfPath\n\nPlease recompile or ensure the file exists.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        );
    }

    // If we reach here, path is not null and file exists.
    // Specific PDFView errors will be handled by its onError callback.
    // If _errorMessage is already set (e.g. by a PDFView callback from a previous build), show it.
    if (_errorMessage != null) {
       return Scaffold(
        appBar: AppBar(title: const Text("PDF Preview Error")),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        )),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("PDF Preview (${_currentPage + 1}/$_totalPages)"),
        actions: <Widget>[
          if (pdfReady && _pdfViewController != null)
            IconButton(
              icon: const Icon(Icons.first_page),
              onPressed: () {
                _pdfViewController!.setPage(0);
              },
            ),
          if (pdfReady && _pdfViewController != null)
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                if (_currentPage > 0) {
                  _pdfViewController!.setPage(_currentPage - 1);
                }
              },
            ),
          if (pdfReady && _pdfViewController != null)
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                if (_currentPage < _totalPages - 1) {
                  _pdfViewController!.setPage(_currentPage + 1);
                }
              },
            ),
          if (pdfReady && _pdfViewController != null)
            IconButton(
              icon: const Icon(Icons.last_page),
              onPressed: () {
                _pdfViewController!.setPage(_totalPages - 1);
              },
            ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          PDFView(
            key: pdfKey, // Use the generation key here to force rebuild on new PDF
            filePath: pdfPath, // Use path from provider
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: false,
            pageFling: true,
            pageSnap: true,
            defaultPage: 0, // Reset to first page on new PDF
            fitPolicy: FitPolicy.BOTH,
            preventLinkNavigation: false,
            onRender: (pages) {
              if (mounted) {
                // Check if the key has changed; if so, reset page counts
                // This logic is a bit tricky with onRender. A simpler way is to reset
                // _currentPage and _totalPages when pdfKey changes if detected earlier.
                // For now, let's assume onRender is for the current PDF load.
                setState(() {
                  _totalPages = pages ?? 0;
                  _currentPage = 0; // Always reset to 0 for a new render with a new key
                  pdfReady = true;
                  _errorMessage = null; // Clear previous PDFView specific errors
                });
              }
            },
            onError: (error) {
              if (mounted) {
                setState(() {
                  _errorMessage = "PDF Rendering Error: ${error.toString()}";
                  pdfReady = false; // PDF is not ready/failed to load
                });
              }
              print("PDFView Error: ${error.toString()}");
            },
            onPageError: (page, error) {
               if (mounted) {
                setState(() {
                   _errorMessage = 'PDF Page Error on $page: ${error.toString()}';
                   pdfReady = false;
                });
              }
              print('PDFView Page $page Error: ${error.toString()}');
            },
            onViewCreated: (PDFViewController pdfViewController) {
              _pdfViewController = pdfViewController;
            },
            onPageChanged: (int? page, int? total) {
              if (mounted) {
                setState(() {
                  _currentPage = page ?? 0;
                  if (total != null) _totalPages = total;
                });
              }
            },
          ),
          if (!pdfReady && _errorMessage == null) // Show loading only if no error and not ready
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
