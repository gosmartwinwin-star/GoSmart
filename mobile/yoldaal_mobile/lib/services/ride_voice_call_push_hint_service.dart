import 'dart:async';

const rideVoiceCallAvailablePushHintType = 'ride_voice_call_available';

typedef RideVoiceCallPushHintData = Map<String, dynamic>;

abstract interface class RideVoiceCallPushHintSource {
  int get revision;

  Stream<int> get revisions;
}

bool isRideVoiceCallPushHintData(RideVoiceCallPushHintData data) {
  return data.length == 1 && data['type'] == rideVoiceCallAvailablePushHintType;
}

class RideVoiceCallPushHintBus implements RideVoiceCallPushHintSource {
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

final RideVoiceCallPushHintBus rideVoiceCallPushHintBus =
    RideVoiceCallPushHintBus();
