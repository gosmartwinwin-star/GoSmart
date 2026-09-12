import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/ride/ride_match_offer_gateway.dart';
import '../core/ride/secure_request_id.dart';
import '../domain/ride/ride_match_offer.dart';
import '../services/ride_match_offer_service.dart';

const driverRideMatchOfferPollInterval = Duration(seconds: 15);

class DriverRideMatchOfferController extends ChangeNotifier {
  DriverRideMatchOfferController({
    required RideMatchOfferGateway gateway,
    String Function()? requestIdGenerator,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? countdownTimerFactory,
    Timer Function(Duration, void Function(Timer))? periodicTimerFactory,
  }) : _gateway = gateway,
       _requestIdGenerator = requestIdGenerator ?? secureRideRequestId,
       _now = now ?? DateTime.now,
       _countdownTimerFactory =
           countdownTimerFactory ??
           ((delay, callback) => Timer(delay, callback)),
       _periodicTimerFactory = periodicTimerFactory ?? Timer.periodic;

  final RideMatchOfferGateway _gateway;
  final String Function() _requestIdGenerator;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _countdownTimerFactory;
  final Timer Function(Duration, void Function(Timer)) _periodicTimerFactory;

  Timer? _countdownTimer;
  Timer? _pollTimer;
  bool _disposed = false;

  List<RideMatchOffer> _offers = const <RideMatchOffer>[];
  final Map<String, String> _acceptRequestIds = <String, String>{};

  bool loading = false;
  bool hasLoaded = false;
  String? acceptingRideId;
  String? errorMessage;
  String? acceptedRideId;

  List<RideMatchOffer> get offers => _offers;

  int remainingMinutesFor(RideMatchOffer offer) {
    final remainingMilliseconds = offer.expiresAt
        .toUtc()
        .difference(_now().toUtc())
        .inMilliseconds;

    if (remainingMilliseconds <= 0) {
      return 0;
    }

    return (remainingMilliseconds + 59999) ~/ 60000;
  }

  bool get accepting => acceptingRideId != null;

  bool get busy => loading || accepting;

  bool get polling => _pollTimer?.isActive ?? false;

  bool startPolling() {
    if (_disposed || !hasListeners || polling) {
      return false;
    }

    _pollTimer = _periodicTimerFactory(driverRideMatchOfferPollInterval, (_) {
      if (_disposed) return;
      unawaited(load());
    });

    return true;
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> load() async {
    if (busy) return;

    _cancelCountdownTimer();
    loading = true;
    errorMessage = null;
    _notify();

    try {
      final loaded = await _gateway.getMyRideMatchOffers();
      final current = _now().toUtc();

      _offers = List<RideMatchOffer>.unmodifiable(
        loaded.where((offer) => offer.expiresAt.isAfter(current)),
      );

      final liveKeys = _offers.map(_offerKey).toSet();

      _acceptRequestIds.removeWhere((key, _) => !liveKeys.contains(key));
    } on RideMatchOfferException catch (error) {
      errorMessage = _loadMessage(error);
    } catch (_) {
      errorMessage = 'Yolculuk teklifleri yüklenemedi. Tekrar deneyin.';
    } finally {
      hasLoaded = true;
      loading = false;
      _scheduleCountdownTimer();
      _notify();
    }
  }

  Future<bool> accept(RideMatchOffer offer) async {
    if (busy) return false;

    final key = _offerKey(offer);
    final canonicalOffer = _findOffer(key);

    if (canonicalOffer == null) {
      errorMessage = 'Bu yolculuk teklifi artık geçerli değil.';
      _notify();
      return false;
    }

    final current = _now().toUtc();

    if (!canonicalOffer.expiresAt.isAfter(current)) {
      _removeOffer(canonicalOffer);
      _acceptRequestIds.remove(key);
      _scheduleCountdownTimer();

      errorMessage = 'Bu yolculuk teklifinin süresi doldu.';
      _notify();
      return false;
    }

    final requestId = _acceptRequestIds.putIfAbsent(key, _requestIdGenerator);

    acceptingRideId = canonicalOffer.rideId;
    errorMessage = null;
    acceptedRideId = null;
    _notify();

    var accepted = false;

    try {
      await _gateway.acceptRideMatchOffer(
        offer: canonicalOffer,
        requestId: requestId,
      );

      _acceptRequestIds.remove(key);
      _offers = const <RideMatchOffer>[];
      acceptedRideId = canonicalOffer.rideId;
      accepted = true;
    } on RideMatchOfferException catch (error) {
      if (_invalidatesOffer(error)) {
        _removeOffer(canonicalOffer);
        _acceptRequestIds.remove(key);
      } else if (_invalidatesAllOffers(error)) {
        _offers = const <RideMatchOffer>[];
        _acceptRequestIds.clear();
      }

      errorMessage = _acceptMessage(error);
    } catch (_) {
      errorMessage = 'Yolculuk kabulü doğrulanamadı. Tekrar deneyin.';
    } finally {
      acceptingRideId = null;
      _scheduleCountdownTimer();
      _notify();
    }

    return accepted;
  }

  void clearAcceptedRide() {
    if (acceptedRideId == null) return;

    acceptedRideId = null;
    _notify();
  }

  RideMatchOffer? _findOffer(String key) {
    for (final offer in _offers) {
      if (_offerKey(offer) == key) {
        return offer;
      }
    }

    return null;
  }

  static String _offerKey(RideMatchOffer offer) =>
      '${offer.rideId}:${offer.rideVersion}';

  void _removeOffer(RideMatchOffer offer) {
    final key = _offerKey(offer);

    _offers = List<RideMatchOffer>.unmodifiable(
      _offers.where((candidate) => _offerKey(candidate) != key),
    );
  }

  bool _pruneExpiredOffers() {
    final current = _now().toUtc();
    final liveOffers = _offers
        .where((offer) => offer.expiresAt.toUtc().isAfter(current))
        .toList(growable: false);

    if (liveOffers.length == _offers.length) {
      return false;
    }

    _offers = List<RideMatchOffer>.unmodifiable(liveOffers);

    final liveKeys = _offers.map(_offerKey).toSet();
    _acceptRequestIds.removeWhere((key, _) => !liveKeys.contains(key));

    return true;
  }

  void _cancelCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _scheduleCountdownTimer() {
    _cancelCountdownTimer();

    if (_disposed || !hasListeners || _offers.isEmpty) {
      return;
    }

    _pruneExpiredOffers();

    if (_offers.isEmpty) {
      return;
    }

    final current = _now().toUtc();
    int? nextDelayMilliseconds;

    for (final offer in _offers) {
      final remainingMilliseconds = offer.expiresAt
          .toUtc()
          .difference(current)
          .inMilliseconds;

      if (remainingMilliseconds <= 0) {
        continue;
      }

      final visibleMinutes = (remainingMilliseconds + 59999) ~/ 60000;

      final boundaryRemainingMilliseconds = visibleMinutes > 1
          ? (visibleMinutes - 1) * 60000
          : 0;

      final delayMilliseconds =
          remainingMilliseconds - boundaryRemainingMilliseconds;

      if (nextDelayMilliseconds == null ||
          delayMilliseconds < nextDelayMilliseconds) {
        nextDelayMilliseconds = delayMilliseconds;
      }
    }

    if (nextDelayMilliseconds == null) {
      return;
    }

    _countdownTimer = _countdownTimerFactory(
      Duration(milliseconds: nextDelayMilliseconds),
      () {
        _countdownTimer = null;

        if (_disposed) {
          return;
        }

        _pruneExpiredOffers();
        _notify();
        _scheduleCountdownTimer();
      },
    );
  }

  static bool _invalidatesOffer(RideMatchOfferException error) {
    const reasons = <String>{
      'ride_match_offer_required',
      'ride_match_offer_not_active',
      'ride_match_offer_mismatch',
      'ride_match_offer_stale',
      'ride_match_offer_route_changed',
      'ride_match_offer_expired',
      'ride_match_offer_invalid',
      'stale_ride_version',
    };

    return reasons.contains(error.reason);
  }

  static bool _invalidatesAllOffers(RideMatchOfferException error) {
    const reasons = <String>{
      'driver_active_ride_exists',
      'driver_profile_required',
      'driver_profile_not_approved',
      'subscription_required',
      'active_return_route_required',
      'active_return_route_invalid',
      'active_return_route_expired',
    };

    return reasons.contains(error.reason);
  }

  static String _loadMessage(RideMatchOfferException error) {
    switch (error.reason) {
      case 'driver_active_ride_exists':
        return 'Zaten aktif bir yolculuğunuz var.';
      case 'subscription_required':
        return 'Eşleşmeleri görmek için aktif sürücü erişimi gerekli.';
      case 'active_return_route_required':
        return 'Eşleşmeleri görmek için aktif dönüş rotası gerekli.';
      case 'active_return_route_expired':
        return 'Dönüş rotanızın süresi doldu.';
      case 'driver_profile_required':
      case 'driver_profile_not_approved':
        return 'Onaylı sürücü profili gerekli.';
    }

    if (error.code == 'unavailable') {
      return 'Yolculuk teklifleri şu anda yüklenemiyor. '
          'Tekrar deneyin.';
    }

    return 'Yolculuk teklifleri yüklenemedi. Tekrar deneyin.';
  }

  static String _acceptMessage(RideMatchOfferException error) {
    if (_invalidatesOffer(error)) {
      return 'Bu yolculuk teklifi artık geçerli değil.';
    }

    switch (error.reason) {
      case 'driver_active_ride_exists':
        return 'Zaten aktif bir yolculuğunuz var.';
      case 'subscription_required':
        return 'Aktif sürücü erişimi gerekli.';
      case 'active_return_route_required':
        return 'Aktif dönüş rotası gerekli.';
      case 'active_return_route_expired':
        return 'Dönüş rotanızın süresi doldu.';
    }

    if (error.code == 'unavailable') {
      return 'Yolculuk kabulü doğrulanamadı. Tekrar deneyin.';
    }

    return 'Yolculuk kabulü tamamlanamadı. Tekrar deneyin.';
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);

    if (_disposed) {
      return;
    }

    _pruneExpiredOffers();
    _scheduleCountdownTimer();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);

    if (_disposed || !hasListeners) {
      _cancelCountdownTimer();
      stopPolling();
    }
  }

  void _notify() {
    if (_disposed || !hasListeners) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelCountdownTimer();
    stopPolling();
    super.dispose();
  }
}
