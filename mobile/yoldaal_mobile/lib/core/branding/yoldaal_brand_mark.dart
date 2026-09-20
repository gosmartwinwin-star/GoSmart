import 'package:flutter/material.dart';

import '../assets/yoldaal_images.dart';

class YoldaAlBrandMark extends StatelessWidget {
  final double size;

  const YoldaAlBrandMark({
    super.key,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        YoldaAlImages.logo,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}