import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

const driverRideOfferAvailablePushHintType = 'ride_offer_available';

typedef DriverOfferPushHintData = Map<String, dynamic>;
typedef DriverOfferPushInitialDataLoader =
    Future<DriverOfferPushHintData?> Function();

abstract interface class DriverOfferPushHintSource {
  int get revision;

  Stream<int> get revisions;
}

bool isDriverOfferPushHintData(DriverOfferPushHintData data) {
  return data['type'] == driverRideOfferAvailablePushHintType;
}

class DriverOfferPushHintBus implements DriverOfferPushHintSource {
  final StreamController<int> _revisionController =
      StreamController<int>.broadcast(sync: true);

  int _revision = 0;

  @override
  int get revision => _revision;

  @override
  Stream<int> get revisions => _revisionController.stream;

  void publish() {
    _revision += 1;
    _revisionController.add(_revision);
  }

  Future<void> dispose() => _revisionController.close();
}

class DriverOfferPushHintBridge {
  DriverOfferPushHintBridge({
    required DriverOfferPushHintBus sink,
    required Stream<DriverOfferPushHintData> foregroundMessages,
    required Stream<DriverOfferPushHintData> openedMessages,
    required DriverOfferPushInitialDataLoader initialMessageLoader,
  }) : _sink = sink,
       _foregroundMessages = foregroundMessages,
       _openedMessages = openedMessages,
       _initialMessageLoader = initialMessageLoader;

  final DriverOfferPushHintBus _sink;
  final Stream<DriverOfferPushHintData> _foregroundMessages;
  final Stream<DriverOfferPushHintData> _openedMessages;
  final DriverOfferPushInitialDataLoader _initialMessageLoader;

  StreamSubscription<DriverOfferPushHintData>? _foregroundSubscription;
  StreamSubscription<DriverOfferPushHintData>? _openedSubscription;

  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started || _disposed) return;

    _started = true;

    _foregroundSubscription = _foregroundMessages.listen(
      _handleData,
      onError: (_, _) {},
    );

    _openedSubscription = _openedMessages.listen(
      _handleData,
      onError: (_, _) {},
    );

    try {
      final initialData = await _initialMessageLoader();

      if (!_disposed && initialData != null) {
        _handleData(initialData);
      }
    } catch (_) {
      // Push delivery is a wake-up optimization only. Failure to recover an
      // initial notification must not block the application bootstrap.
    }
  }

  void _handleData(DriverOfferPushHintData data) {
    if (_disposed || !isDriverOfferPushHintData(data)) return;

    _sink.publish();
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    final foreground = _foregroundSubscription;
    final opened = _openedSubscription;

    _foregroundSubscription = null;
    _openedSubscription = null;

    if (foreground != null) {
      await foreground.cancel();
    }

    if (opened != null) {
      await opened.cancel();
    }
  }
}

final DriverOfferPushHintBus driverOfferPushHintBus = DriverOfferPushHintBus();

DriverOfferPushHintBridge? _firebaseDriverOfferPushHintBridge;

void registerDriverOfferPushBackgroundHandler() {
  FirebaseMessaging.onBackgroundMessage(
    yoldaAlFirebaseMessagingBackgroundHandler,
  );
}

Future<void> initializeDriverOfferPushHintBridge() async {
  if (_firebaseDriverOfferPushHintBridge != null) return;

  final bridge = DriverOfferPushHintBridge(
    sink: driverOfferPushHintBus,
    foregroundMessages: FirebaseMessaging.onMessage.map(
      (message) => message.data,
    ),
    openedMessages: FirebaseMessaging.onMessageOpenedApp.map(
      (message) => message.data,
    ),
    initialMessageLoader: () async {
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();

      return initialMessage?.data;
    },
  );

  _firebaseDriverOfferPushHintBridge = bridge;

  await bridge.start();
}

@pragma('vm:entry-point')
Future<void> yoldaAlFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  if (!isDriverOfferPushHintData(message.data)) return;

  // Android executes this callback in a separate isolate. The push payload
  // carries no ride authority, so this callback deliberately does not touch
  // controllers, accept rides, or derive ride state from the notification.
}
