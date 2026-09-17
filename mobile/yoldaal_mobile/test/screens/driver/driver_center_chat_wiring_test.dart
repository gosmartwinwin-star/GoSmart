import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/screens/driver/driver_center_screen.dart',
    ).readAsStringSync();
  });

  test('DriverCenterScreen wires ride chat through injectable gateway', () {
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
      contains("key: ValueKey('driver-ride-chat-\${activeRide.rideId}')"),
    );

    expect(source, contains('viewerRole: RideChatSenderRole.driver,'));

    expect(source, contains('gateway: widget.chatGateway,'));

    expect(
      source,
      contains('widget.chatRequestIdGenerator ?? secureRideRequestId'),
    );
  });

  test(
    'DriverCenterScreen does not introduce direct Firestore chat access',
    () {
      expect(source, isNot(contains("collection('messages')")));

      expect(source, isNot(contains('.snapshots()')));
    },
  );
}
