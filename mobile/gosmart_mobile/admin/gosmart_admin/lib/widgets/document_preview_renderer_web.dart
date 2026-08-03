import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../domain/driver_application.dart';

Widget buildDocumentPreviewRenderer({
  required DriverApplicationDocumentPreview preview,
  required String semanticLabel,
}) => _WebDocumentPreview(preview: preview, semanticLabel: semanticLabel);

final class _WebDocumentPreview extends StatefulWidget {
  const _WebDocumentPreview({
    required this.preview,
    required this.semanticLabel,
  });
  final DriverApplicationDocumentPreview preview;
  final String semanticLabel;
  @override
  State<_WebDocumentPreview> createState() => _WebDocumentPreviewState();
}

class _WebDocumentPreviewState extends State<_WebDocumentPreview> {
  late final String viewType;
  web.HTMLElement? element;
  late final bool isPdf;

  @override
  void initState() {
    super.initState();
    viewType = 'gosmart-document-preview-${identityHashCode(this)}';
    isPdf = widget.preview.contentType == 'application/pdf';
    element = isPdf ? _pdfElement() : _imageElement();
    ui_web.platformViewRegistry.registerViewFactory(viewType, (_) => element!);
  }

  web.HTMLElement _imageElement() {
    final image = web.HTMLImageElement()
      ..src = widget.preview.rendererUri.toString()
      ..alt = widget.semanticLabel
      ..referrerPolicy = 'no-referrer';
    image.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain';
    image.setAttribute('aria-label', widget.semanticLabel);
    return image;
  }

  web.HTMLElement _pdfElement() {
    final frame = web.HTMLIFrameElement()
      ..src = widget.preview.rendererUri.toString()
      ..title = widget.semanticLabel
      ..referrerPolicy = 'no-referrer';
    frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
    frame.setAttribute('aria-label', widget.semanticLabel);
    return frame;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticLabel,
    child: HtmlElementView(viewType: viewType),
  );

  @override
  void dispose() {
    final current = element;
    if (current != null && isPdf) {
      (current as web.HTMLIFrameElement).src = 'about:blank';
    } else if (current != null) {
      (current as web.HTMLImageElement).src = '';
    }
    current?.remove();
    element = null;
    super.dispose();
  }
}
