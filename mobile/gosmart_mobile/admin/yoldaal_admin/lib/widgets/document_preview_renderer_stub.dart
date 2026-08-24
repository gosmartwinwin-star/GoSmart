import 'package:flutter/material.dart';
import '../domain/driver_application.dart';

Widget buildDocumentPreviewRenderer({
  required DriverApplicationDocumentPreview preview,
  required String semanticLabel,
}) => Semantics(
  label: semanticLabel,
  child: const Center(
    child: Text('Belge önizleme test ortamında gösterilmiyor.'),
  ),
);
