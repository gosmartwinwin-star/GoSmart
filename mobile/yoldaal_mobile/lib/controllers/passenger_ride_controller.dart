import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/ride/ride_gateway.dart';
import '../core/ride/secure_request_id.dart';
import '../domain/ride/canonical_ride.dart';

class PassengerRideController extends ChangeNotifier {
  PassengerRideController({required RideGateway gateway, required RideStreamRepository repository, String Function()? requestIdGenerator, String? Function()? authenticatedUserId})
    : _gateway = gateway, _repository = repository, _requestIdGenerator = requestIdGenerator ?? secureRideRequestId, _authenticatedUserId = authenticatedUserId;
  final RideGateway _gateway;
  final RideStreamRepository _repository;
  final String Function() _requestIdGenerator;
  final String? Function()? _authenticatedUserId;
  CanonicalRide? ride;
  bool loading = false;
  bool mutating = false;
  String? errorMessage;
  StreamSubscription<CanonicalRide>? _subscription;
  String? _createRequestId;
  String? _cancelRequestId;
  bool _disposed = false;

  Future<void> recover() async {
    if (loading) return;
    loading = true; errorMessage = null; _notify();
    try {
      final active = await _gateway.getMyActiveRide();
      if (active == null) { await _clearRide(); } else { await _setRide(active); }
    } on RideGatewayException catch (error) { errorMessage = messageFor(error); }
    catch (_) { errorMessage = 'Aktif yolculuk bilgisi alınamadı.'; }
    finally { loading = false; _notify(); }
  }

  Future<bool> create({required RideLocation pickup, required RideLocation dropoff}) async {
    if (_authenticatedUserId != null && _authenticatedUserId() == null) { return false; }
    if (mutating || ride != null) return false;
    mutating = true; errorMessage = null; _createRequestId ??= _requestIdGenerator(); _notify();
    try {
      final created = await _gateway.createRide(requestId: _createRequestId!, pickup: pickup, dropoff: dropoff);
      _createRequestId = null; await _setRide(created); return true;
    } on RideGatewayException catch (error) {
      if (error.code == 'already-exists' || error.reason == 'passenger_active_ride_exists') { await recover(); }
      else { errorMessage = messageFor(error); }
      return false;
    } catch (_) { errorMessage = 'Yolculuk isteği oluşturulamadı.'; return false; }
    finally { mutating = false; _notify(); }
  }

  Future<void> cancel() async {
    if (_authenticatedUserId != null && _authenticatedUserId() == null) { return; }
    final current = ride;
    if (mutating || current == null || !current.status.passengerCanCancel) return;
    mutating = true; errorMessage = null; _cancelRequestId ??= _requestIdGenerator(); _notify();
    try {
      await _gateway.cancel(rideId: current.rideId, requestId: _cancelRequestId!, expectedVersion: current.version, driver: false);
      _cancelRequestId = null;
    } on RideGatewayException catch (error) {
      if (error.reason == 'stale_ride_version' || error.reason == 'ride_is_terminal') { await refresh(); }
      errorMessage = messageFor(error);
    } catch (_) { errorMessage = 'Yolculuk iptal edilemedi.'; }
    finally { mutating = false; _notify(); }
  }

  Future<void> refresh() async {
    final id = ride?.rideId; if (id == null) return;
    try { _accept(await _repository.getRide(id)); } catch (_) { errorMessage = 'Yolculuk bilgisi yenilenemedi.'; _notify(); }
  }
  Future<void> dismissTerminal() async { if (ride?.status.isTerminal == true) await _clearRide(); }
  Future<void> authChanged(String? userId) async { await _clearRide(); _createRequestId = null; _cancelRequestId = null; errorMessage = null; if (userId != null) { await recover(); } }
  Future<void> _setRide(CanonicalRide value) async { ride = value; _cancelRequestId = null; await _subscription?.cancel(); _subscription = _repository.watchRide(value.rideId).listen(_accept, onError: (_) { errorMessage = 'Yolculuk güncellemeleri alınamadı.'; _notify(); }); _notify(); }
  void _accept(CanonicalRide value) { if (ride?.rideId == value.rideId && value.version < (ride?.version ?? 0)) return; ride = value; _notify(); }
  Future<void> _clearRide() async { await _subscription?.cancel(); _subscription = null; ride = null; _cancelRequestId = null; _notify(); }
  static String messageFor(RideGatewayException error) => switch (error.code) { 'unauthenticated' => 'Oturumunuz sona erdi. Lütfen tekrar giriş yapın.', 'permission-denied' => 'Bu işlem için yetkiniz bulunmuyor.', 'unavailable' => 'Bağlantı kurulamadı. Lütfen tekrar deneyin.', _ when error.reason == 'stale_ride_version' => 'Yolculuk durumu değişti. Güncel bilgiler yüklendi.', _ => 'İşlem şu anda tamamlanamadı.' };
  void _notify() { if (!_disposed) notifyListeners(); }
  @override void dispose() { _disposed = true; _subscription?.cancel(); super.dispose(); }
}
