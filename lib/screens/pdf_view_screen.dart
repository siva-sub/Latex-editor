import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

class PdfViewScreen extends StatefulWidget {
  final String filePath;

  const PdfViewScreen({super.key, required this.filePath});

  @override
  State<PdfViewScreen> createState() => _PdfViewScreenState();
}

class _PdfViewScreenState extends State<PdfViewScreen> {
  int _totalPages = 0;
  int _currentPage = 0;
  bool pdfReady = false;
  PDFViewController? _pdfViewController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    File(widget.filePath).exists().then((exists) {
      if (!exists) {
        setState(() {
          _errorMessage = "PDF file not found at path: ${widget.filePath}";
        });
      }
    }).catchError((e) {
       setState(() {
          _errorMessage = "Error checking PDF file existence: $e";
        });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("PDF Viewer Error"),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text("Error: $_errorMessage", style: const TextStyle(color: Colors.red)),
          ),
        ),
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
            filePath: widget.filePath,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: false,
            pageFling: true,
            pageSnap: true,
            defaultPage: _currentPage,
            fitPolicy: FitPolicy.BOTH,
            preventLinkNavigation: false, // if you want to disable navigation on link tap
            onRender: (pages) {
              if (mounted) {
                setState(() {
                  _totalPages = pages ?? 0;
                  pdfReady = true;
                });
              }
            },
            onError: (error) {
              if (mounted) {
                setState(() {
                  _errorMessage = error.toString();
                });
              }
              print(error.toString());
            },
            onPageError: (page, error) {
               if (mounted) {
                setState(() {
                   _errorMessage = 'Error on page $page: ${error.toString()}';
                });
              }
              print('$page: ${error.toString()}');
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
          if (!pdfReady && _errorMessage == null)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
