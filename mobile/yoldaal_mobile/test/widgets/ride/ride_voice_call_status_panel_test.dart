import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/controllers/ride_voice_call_recovery_controller.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_push_hint_service.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_create_service.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_recovery_service.dart';
import 'package:yoldaal_mobile/services/ride_voice_call_transition_service.dart';
import 'package:yoldaal_mobile/widgets/ride/ride_voice_call_status_panel.dart';

void main() {
  testWidgets('null authoritative call renders nothing', (tester) async {
    final harness = _Harness(
      result: const <String, dynamic>{'activeCall': null},
    );
    addTearDown(harness.dispose);

    await harness.pump(
      tester,
      viewerRole: RideVoiceCallStatusViewerRole.passenger,
    );

    expect(
      find.byKey(const ValueKey('ride-voice-call-status-panel')),
      findsNothing,
    );
  });

  testWidgets('role mismatch renders nothing', (tester) async {
    final harness = _Harness(
      result: _call(state: 'ringing', role: 'passenger', side: 'callee'),
    );
    addTearDown(harness.dispose);

    await harness.pump(
      tester,
      viewerRole: RideVoiceCallStatusViewerRole.driver,
    );

    expect(
      find.byKey(const ValueKey('ride-voice-call-status-panel')),
      findsNothing,
    );
  });

  final cases = <({String state, String side, String title, String message})>[
    (
      state: 'ringing',
      side: 'callee',
      title: 'Gelen sesli arama',
      message: 'Karşı taraf sizi arıyor.',
    ),
    (
      state: 'ringing',
      side: 'caller',
      title: 'Arama isteği gönderildi',
      message: 'Karşı tarafın yanıtı bekleniyor.',
    ),
    (
      state: 'accepted',
      side: 'callee',
      title: 'Arama kabul edildi',
      message: 'Ses bağlantısı hazırlanıyor.',
    ),
    (
      state: 'connecting',
      side: 'caller',
      title: 'Arama bağlanıyor',
      message: 'Ses bağlantısı kuruluyor.',
    ),
    (
      state: 'active',
      side: 'caller',
      title: 'Sesli arama etkin',
      message: 'Arama oturumu etkin durumda.',
    ),
  ];

  for (final item in cases) {
    testWidgets('${item.state}/${item.side} renders presentation-only state', (
      tester,
    ) async {
      final harness = _Harness(
        result: _call(state: item.state, role: 'passenger', side: item.side),
      );
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        viewerRole: RideVoiceCallStatusViewerRole.passenger,
      );

      expect(
        find.byKey(const ValueKey('ride-voice-call-status-panel')),
        findsOneWidget,
      );
      expect(find.text(item.title), findsOneWidget);
      expect(find.text(item.message), findsOneWidget);
      expect(find.text('ride-secret-123'), findsNothing);
      expect(find.text('rvc_0123456789abcdef0123456789abcdef'), findsNothing);
    });
  }

  testWidgets('ringing callee shows accept and decline actions only', (
    tester,
  ) async {
    final harness = _Harness(
      result: _call(state: 'ringing', role: 'passenger', side: 'callee'),
    );
    addTearDown(harness.dispose);

    await harness.pump(
      tester,
      viewerRole: RideVoiceCallStatusViewerRole.passenger,
    );

    expect(
      find.byKey(const ValueKey('ride-voice-call-accept-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ride-voice-call-decline-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ride-voice-call-cancel-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ride-voice-call-end-button')),
      findsNothing,
    );
  });

  testWidgets('ringing caller shows cancel action only', (tester) async {
    final harness = _Harness(
      result: _call(state: 'ringing', role: 'driver', side: 'caller'),
    );
    addTearDown(harness.dispose);

    await harness.pump(
      tester,
      viewerRole: RideVoiceCallStatusViewerRole.driver,
    );

    expect(
      find.byKey(const ValueKey('ride-voice-call-accept-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ride-voice-call-decline-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ride-voice-call-cancel-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ride-voice-call-end-button')),
      findsNothing,
    );
  });

  testWidgets('accepted connecting and active states show end action only', (
    tester,
  ) async {
    for (final state in <String>['accepted', 'connecting', 'active']) {
      final harness = _Harness(
        result: _call(state: state, role: 'passenger', side: 'callee'),
      );

      await harness.pump(
        tester,
        viewerRole: RideVoiceCallStatusViewerRole.passenger,
      );

      expect(
        find.byKey(const ValueKey('ride-voice-call-accept-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ride-voice-call-decline-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ride-voice-call-cancel-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ride-voice-call-end-button')),
        findsOneWidget,
      );

      await harness.dispose();
    }
  });

  testWidgets('action controls disable while transition is in flight', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    final harness = _Harness(
      result: _call(state: 'ringing', role: 'passenger', side: 'callee'),
      transitionPending: pending,
    );
    addTearDown(harness.dispose);

    await harness.pump(
      tester,
      viewerRole: RideVoiceCallStatusViewerRole.passenger,
    );

    final action = harness.controller.acceptCall();
    await tester.pump();

    final accept = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ride-voice-call-accept-button')),
    );
    final decline = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('ride-voice-call-decline-button')),
    );

    expect(accept.onPressed, isNull);
    expect(decline.onPressed, isNull);
    expect(harness.transitionInvoker.calls, 1);

    pending.complete(const <String, dynamic>{'ok': true});
    await action;
    await tester.pump();
  });

  testWidgets('accept button delegates through shared controller transition', (
    tester,
  ) async {
    final harness = _Harness(
      result: _call(state: 'ringing', role: 'passenger', side: 'callee'),
    );
    addTearDown(harness.dispose);

    await harness.pump(
      tester,
      viewerRole: RideVoiceCallStatusViewerRole.passenger,
    );

    await tester.tap(
      find.byKey(const ValueKey('ride-voice-call-accept-button')),
    );
    await tester.pump();
    await tester.pump();

    expect(harness.transitionInvoker.calls, 1);
    expect(harness.transitionInvoker.data?['toState'], 'accepted');
    expect(find.text('ride-secret-123'), findsNothing);
    expect(find.text('rvc_0123456789abcdef0123456789abcdef'), findsNothing);
  });
  testWidgets('start control appears only for eligible no-active-call state', (
    tester,
  ) async {
    final eligible = _Harness(
      result: const <String, dynamic>{'activeCall': null},
      eligibleRideId: 'ride-1',
    );
    addTearDown(eligible.dispose);

    await eligible.pump(
      tester,
      viewerRole: RideVoiceCallStatusViewerRole.passenger,
    );

    expect(
      find.byKey(const ValueKey('ride-voice-call-start-button')),
      findsOneWidget,
    );

    final ineligible = _Harness(
      result: const <String, dynamic>{'activeCall': null},
    );
    addTearDown(ineligible.dispose);

    await ineligible.pump(
      tester,
      viewerRole: RideVoiceCallStatusViewerRole.passenger,
    );

    expect(
      find.byKey(const ValueKey('ride-voice-call-start-button')),
      findsNothing,
    );
  });

  testWidgets('start control delegates create and disables while in flight', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    final harness = _Harness(
      result: const <String, dynamic>{'activeCall': null},
      eligibleRideId: 'ride-1',
      createPending: pending,
    );
    addTearDown(harness.dispose);

    await harness.pump(
      tester,
      viewerRole: RideVoiceCallStatusViewerRole.passenger,
    );

    final action = harness.controller.startCall();
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ride-voice-call-start-button')),
    );

    expect(button.onPressed, isNull);
    expect(harness.createInvoker.calls, 1);
    expect(harness.createInvoker.callable, 'createRideVoiceCall');
    expect(harness.createInvoker.data, <String, dynamic>{'rideId': 'ride-1'});

    pending.complete(const <String, dynamic>{'ignored': true});
    await action;
    await tester.pump();
  });
  testWidgets(
    'panel rebuilds from authoritative recovery controller notification',
    (tester) async {
      final harness = _Harness(
        results: <Object?>[
          _call(state: 'ringing', role: 'driver', side: 'callee'),
          _call(state: 'active', role: 'driver', side: 'callee'),
        ],
      );
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        viewerRole: RideVoiceCallStatusViewerRole.driver,
      );

      expect(find.text('Gelen sesli arama'), findsOneWidget);

      harness.hints.emit(1);
      await tester.pump();
      await tester.pump();

      expect(find.text('Sesli arama etkin'), findsOneWidget);
      expect(harness.invoker.calls, 2);
    },
  );
}

Map<String, dynamic> _call({
  required String state,
  required String role,
  required String side,
}) => <String, dynamic>{
  'activeCall': <String, dynamic>{
    'rideId': 'ride-secret-123',
    'callId': 'rvc_0123456789abcdef0123456789abcdef',
    'state': state,
    'role': role,
    'side': side,
  },
};

class _Harness {
  _Harness({
    Object? result,
    List<Object?>? results,
    Completer<Object?>? transitionPending,
    String? eligibleRideId,
    Completer<Object?>? createPending,
  }) : hints = _FakeHintSource(),
       invoker = _FakeInvoker(results: results ?? <Object?>[result]),
       transitionInvoker = _FakeTransitionInvoker(pending: transitionPending),
       createInvoker = _FakeCreateInvoker(pending: createPending),
       eligibleRideId = eligibleRideId {
    controller = RideVoiceCallRecoveryController(
      recoveryService: RideVoiceCallRecoveryService(invoker: invoker),
      transitionService: RideVoiceCallTransitionService(
        invoker: transitionInvoker,
      ),
      createService: RideVoiceCallCreateService(invoker: createInvoker),
      hintSource: hints,
      currentEligibleRideId: () => eligibleRideId,
      isAuthenticated: () => true,
    );
  }

  final _FakeHintSource hints;
  final _FakeInvoker invoker;
  final _FakeTransitionInvoker transitionInvoker;
  final _FakeCreateInvoker createInvoker;
  final String? eligibleRideId;
  late final RideVoiceCallRecoveryController controller;

  Future<void> pump(
    WidgetTester tester, {
    required RideVoiceCallStatusViewerRole viewerRole,
  }) async {
    controller.start();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideVoiceCallStatusPanel(
            controller: controller,
            viewerRole: viewerRole,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
  }

  Future<void> dispose() async {
    controller.dispose();
    await hints.dispose();
  }
}

class _FakeHintSource implements RideVoiceCallPushHintSource {
  final StreamController<int> _controller = StreamController<int>.broadcast(
    sync: true,
  );

  int _revision = 0;

  @override
  int get revision => _revision;

  @override
  Stream<int> get revisions => _controller.stream;

  void emit(int revision) {
    _revision = revision;
    _controller.add(revision);
  }

  Future<void> dispose() => _controller.close();
}

class _FakeInvoker implements RideVoiceCallRecoveryCallableInvoker {
  _FakeInvoker({required List<Object?> results})
    : _results = List<Object?>.from(results);

  final List<Object?> _results;
  int calls = 0;

  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    expect(callable, 'getMyActiveRideVoiceCall');
    expect(data, isEmpty);

    calls += 1;

    if (_results.isEmpty) {
      return const <String, dynamic>{'activeCall': null};
    }

    return _results.removeAt(0);
  }
}

class _FakeTransitionInvoker implements RideVoiceCallTransitionCallableInvoker {
  _FakeTransitionInvoker({this.pending});

  final Completer<Object?>? pending;

  int calls = 0;
  Map<String, dynamic>? data;

  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    calls += 1;
    this.data = Map<String, dynamic>.from(data);

    final currentPending = pending;
    if (currentPending != null) {
      return currentPending.future;
    }

    return const <String, dynamic>{'ok': true};
  }
}

class _FakeCreateInvoker implements RideVoiceCallCreateCallableInvoker {
  _FakeCreateInvoker({this.pending});

  final Completer<Object?>? pending;

  int calls = 0;
  String? callable;
  Map<String, dynamic>? data;

  @override
  Future<Object?> call(String callable, Map<String, dynamic> data) async {
    calls += 1;
    this.callable = callable;
    this.data = Map<String, dynamic>.from(data);

    final currentPending = pending;
    if (currentPending != null) {
      return currentPending.future;
    }

    return const <String, dynamic>{'ignored': true};
  }
}
