import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the file path of the latest successfully compiled PDF for the
/// currently active/viewed project.
///
/// When a new PDF is generated, this provider should be updated.
/// The PdfViewScreen will listen to this to reload the PDF.
final activeProjectPdfPathProvider = StateProvider<String?>((ref) => null);

/// Provider to track the generation count or a unique key for the PDF.
/// This helps in forcing a rebuild of the PDFView when the path is the same
/// but the content has changed (e.g., recompiled to the same filename).
final pdfGenerationKeyProvider = StateProvider<Key?>((ref) => null);
