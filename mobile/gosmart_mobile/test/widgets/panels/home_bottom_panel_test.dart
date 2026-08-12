import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/widgets/panels/home_bottom_panel.dart';

void main() {
  testWidgets('Profil dokunuşu callbacki tam bir kez çağırır', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [HomeBottomPanel(onProfileTap: () => calls++)],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Profil'));
    await tester.pump();

    expect(calls, 1);
  });
}
