import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/screens/home/home_screen.dart').readAsStringSync();
  });

  test(
    'HomeScreen wires ride chat through callable-backed injectable gateway',
    () {
      expect(
        source,
        contains("import '../../application/ride/ride_chat_gateway.dart';"),
      );

      expect(
        source,
        contains("import '../../widgets/ride/ride_chat_panel.dart';"),
      );

      expect(source, contains('this.chatGateway,'));
      expect(source, contains('this.chatRequestIdGenerator,'));

      expect(source, contains('final RideChatGateway? chatGateway;'));

      expect(
        source,
        contains('final String Function()? chatRequestIdGenerator;'),
      );

      expect(
        source,
        contains("key: ValueKey('passenger-ride-chat-\${ride.rideId}')"),
      );

      expect(source, contains('viewerRole: RideChatSenderRole.passenger,'));

      expect(source, contains('gateway: widget.chatGateway,'));

      expect(
        RegExp(
          r'widget\.chatRequestIdGenerator\s*\?\?\s*secureRideRequestId',
        ).hasMatch(source),
        isTrue,
      );
    },
  );

  test('HomeScreen does not introduce direct Firestore chat access', () {
    expect(source, isNot(contains("collection('messages')")));

    expect(source, isNot(contains('.snapshots()')));
  });
}
