import 'package:flutter_test/flutter_test.dart';
import 'package:gosmart_mobile/domain/customer/customer_access_policy.dart';

void main() {
  const policy = CustomerAccessPolicy();

  test('geçerli kullanıcı kimliği yolculuk talebi oluşturabilir', () {
    expect(policy.canRequestRide(authenticatedUserId: 'user-1'), isTrue);
  });

  test('null kullanıcı yolculuk talebi oluşturamaz', () {
    expect(policy.canRequestRide(authenticatedUserId: null), isFalse);
  });

  test('boş kullanıcı yolculuk talebi oluşturamaz', () {
    expect(policy.canRequestRide(authenticatedUserId: '   '), isFalse);
  });

  test('müşteri erişimi pass veya sürücü profili istemez', () {
    expect(policy.canRequestRide(authenticatedUserId: 'customer-1'), isTrue);
  });

  test('müşteri platform ücreti sıfırdır', () {
    expect(CustomerAccessPolicy.platformFee, 0.0);
  });
}
