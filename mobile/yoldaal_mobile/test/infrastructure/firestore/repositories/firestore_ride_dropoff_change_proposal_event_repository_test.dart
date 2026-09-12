import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/infrastructure/firestore/repositories/firestore_ride_dropoff_change_proposal_event_repository.dart';

void main() {
  test(
    'proposal event discovery exposes unique proposal ids without raw event fields',
    () async {
      String? requestedRideId;

      final repository = FirestoreRideDropoffChangeProposalEventRepository(
        snapshotReader: (rideId) {
          requestedRideId = rideId;

          return Stream<List<Map<String, dynamic>>>.value(
            <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'rideDropoffChangeProposed',
                'fromStatus': 'inProgress',
                'toStatus': 'inProgress',
                'actorType': 'passenger',
                'actorId': 'private-actor',
                'proposalId': 'proposal_1',
                'createdAt': Object(),
              },
              <String, dynamic>{
                'type': 'rideDropoffChangeProposed',
                'fromStatus': 'inProgress',
                'toStatus': 'inProgress',
                'actorType': 'driver',
                'actorId': 'private-other-actor',
                'proposalId': 'proposal_2',
                'createdAt': Object(),
              },
              <String, dynamic>{
                'type': 'rideDropoffChangeProposed',
                'proposalId': 'proposal_1',
              },
            ],
          );
        },
      );

      final proposalIds = await repository
          .watchProposalIds(rideId: 'ride_1')
          .first;

      expect(requestedRideId, 'ride_1');

      expect(proposalIds, <String>['proposal_1', 'proposal_2']);

      expect(proposalIds, isA<List<String>>());
    },
  );

  test(
    'multiple proposal ids remain discoverable without assuming one pending proposal',
    () async {
      final repository = FirestoreRideDropoffChangeProposalEventRepository(
        snapshotReader: (_) =>
            Stream<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'rideDropoffChangeProposed',
                'proposalId': 'proposal_old',
              },
              <String, dynamic>{
                'type': 'rideDropoffChangeProposed',
                'proposalId': 'proposal_new',
              },
              <String, dynamic>{
                'type': 'rideDropoffChangeProposed',
                'proposalId': 'proposal_other',
              },
            ]),
      );

      final proposalIds = await repository
          .watchProposalIds(rideId: 'ride_1')
          .first;

      expect(proposalIds, <String>[
        'proposal_old',
        'proposal_new',
        'proposal_other',
      ]);
    },
  );

  test('malformed event type or proposal id fails closed', () async {
    final invalidSnapshots = <List<Map<String, dynamic>>>[
      <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'rideDropoffChangedCompatible',
          'proposalId': 'proposal_1',
        },
      ],
      <Map<String, dynamic>>[
        <String, dynamic>{'type': 'rideDropoffChangeProposed'},
      ],
      <Map<String, dynamic>>[
        <String, dynamic>{'type': 'rideDropoffChangeProposed', 'proposalId': 7},
      ],
      <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'rideDropoffChangeProposed',
          'proposalId': '',
        },
      ],
      <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'rideDropoffChangeProposed',
          'proposalId': 'proposal/invalid',
        },
      ],
      <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'rideDropoffChangeProposed',
          'proposalId': ' proposal_1 ',
        },
      ],
    ];

    for (final snapshot in invalidSnapshots) {
      final repository = FirestoreRideDropoffChangeProposalEventRepository(
        snapshotReader: (_) =>
            Stream<List<Map<String, dynamic>>>.value(snapshot),
      );

      await expectLater(
        repository.watchProposalIds(rideId: 'ride_1'),
        emitsError(isA<FormatException>()),
      );
    }
  });

  test('invalid ride id is rejected before snapshot reader is invoked', () {
    var readerCalls = 0;

    final repository = FirestoreRideDropoffChangeProposalEventRepository(
      snapshotReader: (_) {
        readerCalls += 1;

        return const Stream<List<Map<String, dynamic>>>.empty();
      },
    );

    expect(
      () => repository.watchProposalIds(rideId: 'ride/invalid'),
      throwsArgumentError,
    );

    expect(readerCalls, 0);
  });

  test(
    'snapshot stream errors propagate without fabricating proposal state',
    () async {
      final repository = FirestoreRideDropoffChangeProposalEventRepository(
        snapshotReader: (_) =>
            Stream<List<Map<String, dynamic>>>.error(StateError('read failed')),
      );

      await expectLater(
        repository.watchProposalIds(rideId: 'ride_1'),
        emitsError(isA<StateError>()),
      );
    },
  );

  test(
    'subsequent snapshots replace discovery view instead of accumulating stale ids',
    () async {
      final snapshots = StreamController<List<Map<String, dynamic>>>();

      addTearDown(snapshots.close);

      final repository = FirestoreRideDropoffChangeProposalEventRepository(
        snapshotReader: (_) => snapshots.stream,
      );

      final values = <List<String>>[];

      final subscription = repository
          .watchProposalIds(rideId: 'ride_1')
          .listen(values.add);

      addTearDown(subscription.cancel);

      snapshots.add(<Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'rideDropoffChangeProposed',
          'proposalId': 'proposal_1',
        },
        <String, dynamic>{
          'type': 'rideDropoffChangeProposed',
          'proposalId': 'proposal_2',
        },
      ]);

      await Future<void>.delayed(Duration.zero);

      snapshots.add(<Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'rideDropoffChangeProposed',
          'proposalId': 'proposal_2',
        },
        <String, dynamic>{
          'type': 'rideDropoffChangeProposed',
          'proposalId': 'proposal_3',
        },
      ]);

      await Future<void>.delayed(Duration.zero);

      expect(values, <List<String>>[
        <String>['proposal_1', 'proposal_2'],
        <String>['proposal_2', 'proposal_3'],
      ]);
    },
  );
}
