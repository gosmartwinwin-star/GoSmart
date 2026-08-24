import 'package:flutter/widgets.dart';
import '../domain/driver_application.dart';
import 'document_preview_renderer_stub.dart'
    if (dart.library.js_interop) 'document_preview_renderer_web.dart'
    as platform;

Widget buildDocumentPreviewRenderer({
  required DriverApplicationDocumentPreview preview,
  required String semanticLabel,
}) => platform.buildDocumentPreviewRenderer(
  preview: preview,
  semanticLabel: semanticLabel,
);
