import 'package:flutter_test/flutter_test.dart';
import 'package:yoldaal_mobile/application/auth/auth_transition_hold.dart';

void main() {
  group('AuthTransitionHold', () {
    test('begin holds without notifying the active login tree', () {
      final hold = AuthTransitionHold();
      var notifications = 0;

      hold.addListener(() {
        notifications++;
      });

      expect(hold.isHeld, isFalse);

      hold.begin();

      expect(hold.isHeld, isTrue);
      expect(notifications, 0);
    });

    test('release clears hold and notifies root exactly once', () {
      final hold = AuthTransitionHold();
      var notifications = 0;

      hold.addListener(() {
        notifications++;
      });

      hold.begin();
      hold.release();

      expect(hold.isHeld, isFalse);
      expect(notifications, 1);

      hold.release();

      expect(notifications, 1);
    });
  });

  group('resolveAuthRootGateDecision', () {
    test('waiting state remains loading', () {
      expect(
        resolveAuthRootGateDecision(
          connectionWaiting: true,
          transitionHeld: false,
          hasError: false,
          hasUser: false,
        ),
        AuthRootGateDecision.loading,
      );
    });

    test('transition hold blocks a non-null Firebase user', () {
      expect(
        resolveAuthRootGateDecision(
          connectionWaiting: false,
          transitionHeld: true,
          hasError: false,
          hasUser: true,
        ),
        AuthRootGateDecision.loading,
      );
    });

    test('transition hold also stays fail closed after auth changes', () {
      expect(
        resolveAuthRootGateDecision(
          connectionWaiting: false,
          transitionHeld: true,
          hasError: false,
          hasUser: false,
        ),
        AuthRootGateDecision.loading,
      );
    });

    test('signed-out state resolves login when no hold exists', () {
      expect(
        resolveAuthRootGateDecision(
          connectionWaiting: false,
          transitionHeld: false,
          hasError: false,
          hasUser: false,
        ),
        AuthRootGateDecision.login,
      );
    });

    test('auth error resolves login when no hold exists', () {
      expect(
        resolveAuthRootGateDecision(
          connectionWaiting: false,
          transitionHeld: false,
          hasError: true,
          hasUser: false,
        ),
        AuthRootGateDecision.login,
      );
    });

    test('non-null user resolves authenticated when hold is released', () {
      expect(
        resolveAuthRootGateDecision(
          connectionWaiting: false,
          transitionHeld: false,
          hasError: false,
          hasUser: true,
        ),
        AuthRootGateDecision.authenticated,
      );
    });
  });
}
