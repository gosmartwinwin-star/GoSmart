import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/application/ride/ride_gateway.dart';
import 'package:gosmart_mobile/controllers/driver_ride_controller.dart';
import 'package:gosmart_mobile/domain/ride/canonical_ride.dart';

void main() {
  test('complete retry reuses exact logical mutation identity', () async {
    final fixture = await Fixture.create(RideStatus.inProgress); fixture.api.completeFailures = 1;
    await fixture.controller.act(DriverRideAction.complete);
    await fixture.controller.act(DriverRideAction.complete);
    expect(fixture.api.completeCalls, hasLength(2));
    expect(fixture.api.completeCalls[1], fixture.api.completeCalls[0]);
    expect(fixture.generatedIds, 1);
    fixture.dispose();
  });

  test('successful complete clears identity and terminal blocks another call', () async {
    final fixture = await Fixture.create(RideStatus.inProgress);
    await fixture.controller.act(DriverRideAction.complete);
    final firstId = fixture.api.completeCalls.single.requestId;
    fixture.api.emit(ride(status: RideStatus.completed, version: 2));
    await Future<void>.delayed(Duration.zero);
    await fixture.controller.act(DriverRideAction.complete);
    expect(fixture.api.completeCalls, hasLength(1));
    fixture.api.driverRide = ride(status: RideStatus.inProgress, version: 1, id: 'ride-2');
    await fixture.controller.authChanged('driver');
    await fixture.controller.act(DriverRideAction.complete);
    expect(fixture.api.completeCalls.last.requestId, isNot(firstId));
    fixture.dispose();
  });

  test('pending complete duplicate tap creates one invocation and one id', () async {
    final fixture = await Fixture.create(RideStatus.inProgress); fixture.api.completePending = Completer<void>();
    final first = fixture.controller.act(DriverRideAction.complete);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.controller.mutating, isTrue);
    await fixture.controller.act(DriverRideAction.complete);
    expect(fixture.api.completeCalls, hasLength(1));
    expect(fixture.generatedIds, 1);
    fixture.api.completePending!.complete();
    await first;
    fixture.dispose();
  });

  test('stale complete refreshes without blind mutation retry', () async {
    final fixture = await Fixture.create(RideStatus.inProgress);
    fixture.api.completeError = const RideGatewayException('failed-precondition', reason: 'stale_ride_version');
    fixture.api.refreshed = ride(status: RideStatus.completed, version: 2);
    await fixture.controller.act(DriverRideAction.complete);
    expect(fixture.api.completeCalls, hasLength(1));
    expect(fixture.api.getCalls, 1);
    expect(fixture.controller.ride?.version, 2);
    fixture.dispose();
  });

  test('driver cancel retry reuses ride version reason and request id', () async {
    final fixture = await Fixture.create(RideStatus.driverEnRoute); fixture.api.cancelFailures = 1;
    await fixture.controller.act(DriverRideAction.cancel);
    await fixture.controller.act(DriverRideAction.cancel);
    expect(fixture.api.cancelCalls, hasLength(2));
    expect(fixture.api.cancelCalls[1], fixture.api.cancelCalls[0]);
    expect(fixture.api.cancelCalls.every((call) => call.driver), isTrue);
    expect(fixture.generatedIds, 1);
    fixture.dispose();
  });

  test('successful cancel clears identity before a new ride', () async {
    final fixture = await Fixture.create(RideStatus.driverArrived);
    await fixture.controller.act(DriverRideAction.cancel);
    final firstId = fixture.api.cancelCalls.single.requestId;
    fixture.api.driverRide = ride(id: 'ride-2', status: RideStatus.driverEnRoute);
    await fixture.controller.authChanged('driver');
    await fixture.controller.act(DriverRideAction.cancel);
    expect(fixture.api.cancelCalls.last.requestId, isNot(firstId));
    fixture.dispose();
  });

  test('pending cancel duplicate tap creates one invocation and one id', () async {
    final fixture = await Fixture.create(RideStatus.driverEnRoute); fixture.api.cancelPending = Completer<void>();
    final first = fixture.controller.act(DriverRideAction.cancel);
    await Future<void>.delayed(Duration.zero);
    await fixture.controller.act(DriverRideAction.cancel);
    expect(fixture.api.cancelCalls, hasLength(1));
    expect(fixture.generatedIds, 1);
    fixture.api.cancelPending!.complete();
    await first;
    fixture.dispose();
  });

  test('stale cancel refreshes without changed-version mutation retry', () async {
    final fixture = await Fixture.create(RideStatus.driverEnRoute);
    fixture.api.cancelError = const RideGatewayException('failed-precondition', reason: 'stale_ride_version');
    fixture.api.refreshed = ride(status: RideStatus.driverArrived, version: 2);
    await fixture.controller.act(DriverRideAction.cancel);
    expect(fixture.api.cancelCalls, hasLength(1));
    expect(fixture.api.cancelCalls.single.version, 1);
    expect(fixture.api.getCalls, 1);
    fixture.dispose();
  });

  test('arrive start complete and cancel identities are isolated', () async {
    final fixture = await Fixture.create(RideStatus.driverEnRoute);
    await fixture.controller.act(DriverRideAction.arrive);
    fixture.api.emit(ride(status: RideStatus.driverArrived, version: 2));
    await Future<void>.delayed(Duration.zero);
    await fixture.controller.act(DriverRideAction.start);
    fixture.api.emit(ride(status: RideStatus.inProgress, version: 3));
    await Future<void>.delayed(Duration.zero);
    await fixture.controller.act(DriverRideAction.complete);
    final ids = [fixture.api.arriveCalls.single.requestId, fixture.api.startCalls.single.requestId, fixture.api.completeCalls.single.requestId];
    expect(ids.toSet(), hasLength(3));
    fixture.api.driverRide = ride(id: 'ride-2', status: RideStatus.driverEnRoute);
    await fixture.controller.authChanged('driver');
    await fixture.controller.act(DriverRideAction.cancel);
    expect(ids, isNot(contains(fixture.api.cancelCalls.single.requestId)));
    fixture.dispose();
  });

  test('auth change clears pending complete identity and old listener', () async {
    final fixture = await Fixture.create(RideStatus.inProgress); fixture.api.completePending = Completer<void>();
    final old = fixture.controller.act(DriverRideAction.complete);
    await Future<void>.delayed(Duration.zero);
    final oldId = fixture.api.completeCalls.single.requestId;
    fixture.api.driverRide = ride(id: 'ride-2', status: RideStatus.inProgress);
    final change = fixture.controller.authChanged('driver');
    fixture.api.completePending!.complete(); await old; await change;
    await fixture.controller.act(DriverRideAction.complete);
    expect(fixture.api.completeCalls.last.requestId, isNot(oldId));
    expect(fixture.api.cancelledOldListener, isTrue);
    fixture.dispose();
  });

  test('logout clears pending cancel identity before new session', () async {
    final fixture = await Fixture.create(RideStatus.driverEnRoute); fixture.api.cancelPending = Completer<void>();
    final old = fixture.controller.act(DriverRideAction.cancel);
    await Future<void>.delayed(Duration.zero);
    final oldId = fixture.api.cancelCalls.single.requestId;
    final logout = fixture.controller.authChanged(null);
    fixture.api.cancelPending!.complete(); await old; await logout;
    fixture.api.driverRide = ride(id: 'ride-2', status: RideStatus.driverEnRoute);
    await fixture.controller.authChanged('driver');
    await fixture.controller.act(DriverRideAction.cancel);
    expect(fixture.api.cancelCalls.last.requestId, isNot(oldId));
    fixture.dispose();
  });
}

const point = RideLocation(latitude: 41, longitude: 29, addressLabel: 'Adres');
CanonicalRide ride({String id = 'ride-1', required RideStatus status, int version = 1}) => CanonicalRide(rideId: id, status: status, version: version, pickup: point, dropoff: point, route: const RideRoute(distanceMeters: 1, durationSeconds: 1, encodedPolyline: 'x'));
typedef Call = ({String rideId, String requestId, int version, bool driver});

class Fixture {
  Fixture._();
  static Future<Fixture> create(RideStatus status) async { final value=Fixture._(); value.api.driverRide=ride(status:status); value.controller=DriverRideController(gateway:value.api,repository:value.api,requestIdGenerator:()=> 'generated-${++value.generatedIds}'); await value.controller.recover(); return value; }
  final Api api = Api(); late final DriverRideController controller; int generatedIds = 0;
  void dispose() => controller.dispose();
}

class Api implements RideGateway, RideStreamRepository {
  CanonicalRide? driverRide, refreshed; int completeFailures = 0, cancelFailures = 0, getCalls = 0; RideGatewayException? completeError, cancelError; Completer<void>? completePending, cancelPending;
  final completeCalls=<Call>[], cancelCalls=<Call>[], arriveCalls=<Call>[], startCalls=<Call>[];
  late final stream = StreamController<CanonicalRide>.broadcast(onCancel: () => cancelledOldListener = true); bool cancelledOldListener = false;
  void emit(CanonicalRide value) => stream.add(value);
  Call call(String rideId,String requestId,int version,bool driver)=> (rideId:rideId,requestId:requestId,version:version,driver:driver);
  @override Future<CanonicalRide?> getMyActiveDriverRide() async => driverRide;
  @override Future<CanonicalRide?> getMyActiveRide() async => null;
  @override Stream<CanonicalRide> watchRide(String rideId) => stream.stream;
  @override Future<CanonicalRide> getRide(String rideId) async { getCalls++; return refreshed!; }
  @override Future<void> completeRide({required String rideId,required String requestId,required int expectedVersion}) async { completeCalls.add(call(rideId,requestId,expectedVersion,true)); if(completeError case final error?) throw error; if(completeFailures-->0) throw const RideGatewayException('unavailable'); await completePending?.future; }
  @override Future<void> cancel({required String rideId,required String requestId,required int expectedVersion,required bool driver}) async { cancelCalls.add(call(rideId,requestId,expectedVersion,driver)); if(cancelError case final error?) throw error; if(cancelFailures-->0) throw const RideGatewayException('unavailable'); await cancelPending?.future; }
  @override Future<void> markDriverArrived({required String rideId,required String requestId,required int expectedVersion}) async => arriveCalls.add(call(rideId,requestId,expectedVersion,true));
  @override Future<void> startRide({required String rideId,required String requestId,required int expectedVersion}) async => startCalls.add(call(rideId,requestId,expectedVersion,true));
  @override Future<CanonicalRide> createRide({required String requestId,required RideLocation pickup,required RideLocation dropoff}) => throw UnimplementedError();
}
