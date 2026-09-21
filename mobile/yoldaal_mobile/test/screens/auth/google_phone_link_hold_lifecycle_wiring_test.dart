import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/screens/auth/login_screen.dart').readAsStringSync();
  });

  String completeSignInSource() {
    final start = source.indexOf('Future<void> _completeSignIn(');
    final end = source.indexOf('Future<void> _abortGooglePhoneLink(');

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    return source.substring(start, end);
  }

  String googleStartSource() {
    final start = source.indexOf('Future<void> _startGoogleSignIn(');
    final end = source.indexOf('String _messageForGoogleError(');

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    return source.substring(start, end);
  }

  test('SMS waiting phase does not acquire the process-global auth hold', () {
    final googleStart = googleStartSource();

    final phoneDisposition = googleStart.indexOf(
      'GoogleSignInStartDisposition.phoneVerificationRequired',
    );

    expect(phoneDisposition, greaterThanOrEqualTo(0));

    final dispositionTail = googleStart.substring(phoneDisposition);

    expect(dispositionTail.contains('_googlePhoneLinkPending = true;'), isTrue);

    expect(dispositionTail.contains('authTransitionHold.begin();'), isFalse);
  });

  test(
    'pending Google link acquires hold immediately before phone sign-in',
    () {
      final complete = completeSignInSource();

      final begin = complete.indexOf('authTransitionHold.begin();');
      final signIn = complete.indexOf(
        'await _auth.signInWithCredential(credential);',
      );
      final sessionOpened = complete.indexOf('phoneSessionOpened = true;');

      expect(begin, greaterThanOrEqualTo(0));
      expect(signIn, greaterThan(begin));
      expect(sessionOpened, greaterThan(signIn));

      final prefix = complete.substring(0, begin);

      expect(
        prefix.contains(
          'final googleLinkWasPending = _googlePhoneLinkPending;',
        ),
        isTrue,
      );
      expect(
        complete.substring(
          complete.lastIndexOf('if (googleLinkWasPending)', begin),
          begin,
        ),
        contains('if (googleLinkWasPending)'),
      );
    },
  );

  test(
    'pre-session failures release hold without clearing pending Google link',
    () {
      final complete = completeSignInSource();

      final retryReleaseBlocks = RegExp(
        r'if \(phoneSessionOpened\) \{\s*'
        r'await _abortGooglePhoneLink\(\);\s*'
        r'\} else \{[\s\S]*?'
        r'authTransitionHold\.release\(\);\s*'
        r'\}',
      ).allMatches(complete);

      expect(retryReleaseBlocks.length, 3);

      for (final match in retryReleaseBlocks) {
        final block = match.group(0)!;

        expect(block.contains('_googlePhoneLinkPending = false'), isFalse);
        expect(block.contains('clearPendingLink'), isFalse);
      }
    },
  );

  test('success and post-session failure preserve fail-closed ordering', () {
    final complete = completeSignInSource();

    final signIn = complete.indexOf(
      'await _auth.signInWithCredential(credential);',
    );
    final link = complete.indexOf(
      'await _googleSignInCoordinator.linkPendingAfterPhoneSignIn();',
    );
    final pendingClear = complete.indexOf(
      '_googlePhoneLinkPending = false;',
      link,
    );
    final successRelease = complete.indexOf(
      'authTransitionHold.release();',
      pendingClear,
    );
    final successMarker = complete.indexOf(
      "_recordGooglePhoneLinkRuntimeState('link_succeeded');",
      successRelease,
    );
    final refresh = complete.indexOf('await user.getIdToken(true);');

    expect(link, greaterThan(signIn));
    expect(pendingClear, greaterThan(link));
    expect(successRelease, greaterThan(pendingClear));
    expect(successMarker, greaterThan(successRelease));
    expect(
      refresh,
      -1,
      reason:
          'Persistent Google link success must not depend on a post-link '
          'token refresh inside _completeSignIn.',
    );

    expect(
      RegExp(
        r'if \(phoneSessionOpened\) \{\s*'
        r'await _abortGooglePhoneLink\(\);',
      ).allMatches(complete).length,
      3,
    );

    final abortStart = source.indexOf('Future<void> _abortGooglePhoneLink(');
    final googleStart = source.indexOf('Future<void> _startGoogleSignIn(');

    expect(abortStart, greaterThanOrEqualTo(0));
    expect(googleStart, greaterThan(abortStart));

    final abort = source.substring(abortStart, googleStart);

    final signOut = abort.indexOf('await _auth.signOut();');
    final clearPending = abort.indexOf(
      '_googleSignInCoordinator.clearPendingLink();',
    );
    final release = abort.indexOf('authTransitionHold.release();');

    expect(signOut, greaterThanOrEqualTo(0));
    expect(clearPending, greaterThan(signOut));
    expect(release, greaterThan(clearPending));
  });
}
