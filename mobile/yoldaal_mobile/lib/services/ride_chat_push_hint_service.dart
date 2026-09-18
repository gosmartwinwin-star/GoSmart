import 'dart:async';

const rideChatMessageAvailablePushHintType = 'ride_chat_message_available';

typedef RideChatPushHintData = Map<String, dynamic>;

abstract interface class RideChatPushHintSource {
  int get revision;

  Stream<int> get revisions;
}

bool isRideChatPushHintData(RideChatPushHintData data) {
  return data.length == 1 &&
      data['type'] == rideChatMessageAvailablePushHintType;
}

class RideChatPushHintBus implements RideChatPushHintSource {
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

final RideChatPushHintBus rideChatPushHintBus = RideChatPushHintBus();
