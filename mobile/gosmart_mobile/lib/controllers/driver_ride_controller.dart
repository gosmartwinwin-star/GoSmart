import 'dart:async';
import 'package:flutter/foundation.dart';
import '../application/ride/ride_gateway.dart';
import '../core/ride/secure_request_id.dart';
import '../domain/ride/canonical_ride.dart';

enum DriverRideAction { arrive, start, complete, cancel }

class DriverRideController extends ChangeNotifier {
  DriverRideController({required RideGateway gateway, required RideStreamRepository repository, String Function()? requestIdGenerator, String? Function()? authenticatedUserId}) : _gateway = gateway, _repository = repository, _requestIdGenerator = requestIdGenerator ?? secureRideRequestId, _authenticatedUserId = authenticatedUserId;
  final RideGateway _gateway; final RideStreamRepository _repository; final String Function() _requestIdGenerator; final String? Function()? _authenticatedUserId;
  CanonicalRide? ride; bool loading = false; bool mutating = false; String? errorMessage;
  StreamSubscription<CanonicalRide>? _subscription; String? _requestId; DriverRideAction? _pendingAction; bool _disposed = false;
  Future<void> recover() async { if (loading) return; loading = true; errorMessage = null; _notify(); try { final value = await _gateway.getMyActiveDriverRide(); if (value == null) { await _clear(); } else { await _set(value); } } on RideGatewayException catch (e) { errorMessage = PassengerError.message(e); } catch (_) { errorMessage = 'Aktif yolculuk bilgisi alınamadı.'; } finally { loading = false; _notify(); } }
  Future<void> act(DriverRideAction action) async { final current = ride; if (mutating || current == null || !_allowed(action, current.status)) return; mutating = true; errorMessage = null; if (_pendingAction != action) { _requestId = null; _pendingAction = action; } _requestId ??= _requestIdGenerator(); _notify(); try { switch (action) { case DriverRideAction.arrive: await _gateway.markDriverArrived(rideId: current.rideId, requestId: _requestId!, expectedVersion: current.version); break; case DriverRideAction.start: await _gateway.startRide(rideId: current.rideId, requestId: _requestId!, expectedVersion: current.version); break; case DriverRideAction.complete: await _gateway.completeRide(rideId: current.rideId, requestId: _requestId!, expectedVersion: current.version); break; case DriverRideAction.cancel: await _gateway.cancel(rideId: current.rideId, requestId: _requestId!, expectedVersion: current.version, driver: true); break; } _requestId = null; _pendingAction = null; } on RideGatewayException catch (e) { if (e.reason == 'stale_ride_version' || e.reason == 'ride_is_terminal') await refresh(); errorMessage = PassengerError.message(e); } catch (_) { errorMessage = 'Yolculuk işlemi tamamlanamadı.'; } finally { mutating = false; _notify(); } }
  bool _allowed(DriverRideAction action, RideStatus status) => switch (action) { DriverRideAction.arrive => status == RideStatus.driverEnRoute, DriverRideAction.start => status == RideStatus.driverArrived, DriverRideAction.complete => status == RideStatus.inProgress, DriverRideAction.cancel => status == RideStatus.driverEnRoute || status == RideStatus.driverArrived };
  Future<void> refresh() async { final id = ride?.rideId; if (id == null) return; try { _accept(await _repository.getRide(id)); } catch (_) { errorMessage = 'Yolculuk bilgisi yenilenemedi.'; _notify(); } }
  Future<void> _set(CanonicalRide value) async { ride = value; await _subscription?.cancel(); _subscription = _repository.watchRide(value.rideId).listen(_accept, onError: (_) { errorMessage = 'Yolculuk güncellemeleri alınamadı.'; _notify(); }); _notify(); }
  void _accept(CanonicalRide value) { if (ride?.rideId == value.rideId && value.version < (ride?.version ?? 0)) return; ride = value; _notify(); }
  Future<void> authChanged(String? userId) async { if (_authenticatedUserId != null && userId != _authenticatedUserId()) { return; } await _clear(); errorMessage = null; if (userId != null) { await recover(); } }
  Future<void> _clear() async { await _subscription?.cancel(); _subscription = null; ride = null; _requestId = null; _pendingAction = null; _notify(); }
  void _notify() { if (!_disposed) notifyListeners(); }
  @override void dispose() { _disposed = true; _subscription?.cancel(); super.dispose(); }
}

class PassengerError { static String message(RideGatewayException error) => switch (error.code) { 'unauthenticated' => 'Oturumunuz sona erdi. Lütfen tekrar giriş yapın.', 'permission-denied' => 'Bu işlem için yetkiniz bulunmuyor.', 'unavailable' => 'Bağlantı kurulamadı. Lütfen tekrar deneyin.', _ when error.reason == 'stale_ride_version' => 'Yolculuk durumu değişti. Güncel bilgiler yüklendi.', _ => 'İşlem şu anda tamamlanamadı.' }; }
