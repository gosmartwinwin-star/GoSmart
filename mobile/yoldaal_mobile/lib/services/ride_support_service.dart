import '../application/ride/ride_gateway.dart';
import '../application/ride/ride_support_gateway.dart';
import '../core/firebase/firebase_functions_registry.dart';
import 'ride_lifecycle_service.dart';

class RideSupportService
    implements RideSupportGateway, RideActiveSupportGateway {
  RideSupportService({RideCallableInvoker? invoker})
    : _invoker = invoker ?? FirebaseRideCallableInvoker();

  final RideCallableInvoker _invoker;

  @override
  Future<RideSupportCaseResult> createCase({
    required String rideId,
    required String category,
    required String requestId,
  }) =>
      _createCase(
        callableName: FirebaseFunctionsRegistry.createRideSupportCase,
        rideId: rideId,
        category: category,
        requestId: requestId,
      );

  @override
  Future<RideSupportCaseResult> createActiveCase({
    required String rideId,
    required String category,
    required String requestId,
  }) =>
      _createCase(
        callableName: FirebaseFunctionsRegistry.createActiveRideSupportCase,
        rideId: rideId,
        category: category,
        requestId: requestId,
      );

  Future<RideSupportCaseResult> _createCase({
    required String callableName,
    required String rideId,
    required String category,
    required String requestId,
  }) async {
    _validateRideId(rideId);
    _validateCategory(category);
    _validateRequestId(requestId);

    final data = await _call(
      callableName,
      {
        'rideId': rideId,
        'category': category,
        'requestId': requestId,
      },
    );

    final rawRideId = data['rideId'];
    final rawCaseId = data['caseId'];
    final rawCategory = data['category'];
    final rawCreatedAtMillis = data['createdAtMillis'];

    if (data.length != 4 ||
        rawRideId != rideId ||
        rawCaseId is! String ||
        rawCaseId.isEmpty ||
        rawCategory != category ||
        rawCreatedAtMillis is! int ||
        rawCreatedAtMillis < 0) {
      throw const RideGatewayException('invalid-response');
    }

    return RideSupportCaseResult(
      rideId: rideId,
      caseId: rawCaseId,
      category: category,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        rawCreatedAtMillis,
        isUtc: true,
      ),
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _invoker.call(name, payload);
    } on RideGatewayException {
      rethrow;
    } catch (_) {
      throw const RideGatewayException('invalid-response');
    }
  }

  static void _validateRideId(String value) {
    if (value.isEmpty ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'rideId',
        'Invalid ride id.',
      );
    }
  }

  static void _validateCategory(String value) {
    if (!rideSupportCategories.contains(value)) {
      throw ArgumentError.value(
        value,
        'category',
        'Invalid ride support category.',
      );
    }
  }

  static void _validateRequestId(String value) {
    if (value.length < 16 ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'requestId',
        'Invalid request id.',
      );
    }
  }
}
