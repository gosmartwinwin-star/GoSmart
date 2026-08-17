import 'package:flutter/foundation.dart';

import '../application/ride/ride_match_offer_gateway.dart';
import '../core/ride/secure_request_id.dart';
import '../domain/ride/ride_match_offer.dart';
import '../services/ride_match_offer_service.dart';

class DriverRideMatchOfferController extends ChangeNotifier {
  DriverRideMatchOfferController({
    required RideMatchOfferGateway gateway,
    String Function()? requestIdGenerator,
    DateTime Function()? now,
  }) : _gateway = gateway,
       _requestIdGenerator = requestIdGenerator ?? secureRideRequestId,
       _now = now ?? DateTime.now;

  final RideMatchOfferGateway _gateway;
  final String Function() _requestIdGenerator;
  final DateTime Function() _now;

  List<RideMatchOffer> _offers = const <RideMatchOffer>[];
  final Map<String, String> _acceptRequestIds = <String, String>{};

  bool loading = false;
  bool hasLoaded = false;
  String? acceptingRideId;
  String? errorMessage;
  String? acceptedRideId;

  List<RideMatchOffer> get offers => _offers;

  bool get accepting => acceptingRideId != null;

  bool get busy => loading || accepting;

  Future<void> load() async {
    if (busy) return;

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

  void _notify() {
    if (!hasListeners) return;
    notifyListeners();
  }
}
