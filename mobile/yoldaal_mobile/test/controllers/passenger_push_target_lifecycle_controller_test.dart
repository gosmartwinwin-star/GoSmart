import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/controllers/passenger_push_target_lifecycle_controller.dart';
import 'package:yoldaal_mobile/services/passenger_push_target_registration_service.dart';

void main() {
  test('inactive lifecycle ignores installation ID changes', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    fixture.source.emit('opaque/fid+inactive=1');

    await _flushEvents();
    await fixture.lifecycle.idle;

    expect(fixture.invoker.payloads, isEmpty);
  });

  test('eligible transition registers current installation once', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    fixture.lifecycle.setEligible(true);
    await fixture.lifecycle.idle;

    expect(fixture.invoker.payloads, [
      {'fid': _initialFid, 'platform': 'android'},
    ]);

    fixture.lifecycle.setEligible(true);
    await fixture.lifecycle.idle;

    expect(fixture.invoker.payloads, hasLength(1));
  });

  test('disable then re-enable refreshes current installation', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    fixture.lifecycle.setEligible(true);
    await fixture.lifecycle.idle;

    fixture.lifecycle.setEligible(false);
    fixture.source.currentId = 'opaque/fid+resumed=2';
    fixture.lifecycle.setEligible(true);

    await fixture.lifecycle.idle;

    expect(fixture.invoker.payloads, hasLength(2));
    expect(fixture.invoker.payloads.last, {
      'fid': 'opaque/fid+resumed=2',
      'platform': 'android',
    });
  });

  test('eligible ID change registers exact changed FID', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    fixture.lifecycle.setEligible(true);
    await fixture.lifecycle.idle;

    fixture.source.currentId = 'opaque/fid+changed=3';
    fixture.source.emit('opaque/fid+changed=3');

    await _flushEvents();
    await fixture.lifecycle.idle;

    expect(fixture.invoker.payloads, hasLength(2));
    expect(fixture.invoker.payloads.last, {
      'fid': 'opaque/fid+changed=3',
      'platform': 'android',
    });
  });

  test('changed FID waits behind in-flight current registration', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final firstResponse = Completer<Object?>();
    fixture.invoker.blockNext = firstResponse;

    fixture.lifecycle.setEligible(true);
    await _flushEvents();

    expect(fixture.invoker.payloads, hasLength(1));

    fixture.source.currentId = 'opaque/fid+serialized=4';
    fixture.source.emit('opaque/fid+serialized=4');

    await _flushEvents();

    expect(fixture.invoker.payloads, hasLength(1));

    firstResponse.complete(const {'updatedAtMillis': 1});

    await _flushEvents();
    await fixture.lifecycle.idle;

    expect(fixture.invoker.payloads, hasLength(2));
    expect(fixture.invoker.payloads.last, {
      'fid': 'opaque/fid+serialized=4',
      'platform': 'android',
    });
  });

  test('disable invalidates queued stale FID registration', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final firstResponse = Completer<Object?>();
    fixture.invoker.blockNext = firstResponse;

    fixture.lifecycle.setEligible(true);
    await _flushEvents();

    fixture.source.currentId = 'opaque/fid+stale=5';
    fixture.source.emit('opaque/fid+stale=5');

    await _flushEvents();

    fixture.lifecycle.setEligible(false);

    firstResponse.complete(const {'updatedAtMillis': 1});

    await _flushEvents();
    await fixture.lifecycle.idle;

    expect(fixture.invoker.payloads, hasLength(1));
  });

  test(
    'registration failure is fail-soft and later change continues',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);

      fixture.invoker.failuresRemaining = 1;

      fixture.lifecycle.setEligible(true);
      await fixture.lifecycle.idle;

      expect(fixture.invoker.payloads, hasLength(1));

      fixture.source.currentId = 'opaque/fid+retry=6';
      fixture.source.emit('opaque/fid+retry=6');

      await _flushEvents();
      await fixture.lifecycle.idle;

      expect(fixture.invoker.payloads, hasLength(2));
      expect(fixture.invoker.payloads.last['fid'], 'opaque/fid+retry=6');
    },
  );

  test('dispose stops future registration work', () async {
    final fixture = _fixture();

    fixture.lifecycle.setEligible(true);
    await fixture.lifecycle.idle;

    expect(fixture.invoker.payloads, hasLength(1));

    fixture.lifecycle.dispose();

    fixture.source.currentId = 'opaque/fid+disposed=7';
    fixture.source.emit('opaque/fid+disposed=7');
    fixture.lifecycle.setEligible(true);

    await _flushEvents();
    await fixture.lifecycle.idle;

    expect(fixture.invoker.payloads, hasLength(1));

    await fixture.source.close();
  });
}

const _initialFid = 'opaque/fid+initial=0';

_Fixture _fixture() {
  final source = _InstallationIdSource(currentId: _initialFid);
  final invoker = _RecordingInvoker();

  final registration = PassengerPushTargetRegistrationService(
    authSession: _AuthSession(),
    installationIdSource: source,
    invoker: invoker,
  );

  final lifecycle = PassengerPushTargetLifecycleController(
    registration: registration,
    platform: PassengerPushTargetPlatform.android,
  );

  return _Fixture(source: source, invoker: invoker, lifecycle: lifecycle);
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _Fixture {
  _Fixture({
    required this.source,
    required this.invoker,
    required this.lifecycle,
  });

  final _InstallationIdSource source;
  final _RecordingInvoker invoker;
  final PassengerPushTargetLifecycleController lifecycle;

  Future<void> dispose() async {
    lifecycle.dispose();
    await source.close();
  }
}

class _AuthSession implements PassengerPushTargetAuthSession {
  @override
  Future<void> requireAuthenticatedUser() async {}
}

class _InstallationIdSource implements PassengerPushInstallationIdSource {
  _InstallationIdSource({required this.currentId});

  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  String currentId;

  @override
  Future<String> getId() async => currentId;

  @override
  Stream<String> get onIdChange => _changes.stream;

  void emit(String fid) {
    _changes.add(fid);
  }

  Future<void> close() => _changes.close();
}

class _RecordingInvoker implements PassengerPushTargetCallableInvoker {
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  Completer<Object?>? blockNext;
  int failuresRemaining = 0;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));

    if (failuresRemaining > 0) {
      failuresRemaining -= 1;

      throw const PassengerPushTargetRegistrationException(code: 'unavailable');
    }

    final blocker = blockNext;

    if (blocker != null) {
      blockNext = null;
      return blocker.future;
    }

    return {'updatedAtMillis': payloads.length};
  }
}
