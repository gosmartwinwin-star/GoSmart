import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AccountDeletionWebAuthUser {
  const AccountDeletionWebAuthUser({
    required this.uid,
    this.phoneNumber,
    this.email,
    this.displayName,
    this.providerIds = const <String>[],
  });

  final String uid;
  final String? phoneNumber;
  final String? email;
  final String? displayName;
  final List<String> providerIds;

  String get identityLabel {
    final phone = phoneNumber?.trim();
    if (phone != null && phone.isNotEmpty) return phone;

    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail;

    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;

    return 'Doğrulanmış Firebase hesabı';
  }
}

abstract interface class AccountDeletionPhoneConfirmation {
  Future<AccountDeletionWebAuthUser> confirm(String verificationCode);
}

typedef AccountDeletionGoogleSignIn =
    Future<AccountDeletionWebAuthUser> Function();
typedef AccountDeletionPhoneStart =
    Future<AccountDeletionPhoneConfirmation> Function(String phoneNumber);
typedef AccountDeletionWebSignOut = Future<void> Function();

class AccountDeletionWebAuthService {
  AccountDeletionWebAuthService({
    FirebaseAuth? auth,
    AccountDeletionGoogleSignIn? googleSignIn,
    AccountDeletionPhoneStart? phoneStart,
    AccountDeletionWebSignOut? signOut,
  }) : _auth = auth,
       _googleSignIn =
           googleSignIn ?? _firebaseGoogleSignIn(auth ?? FirebaseAuth.instance),
       _phoneStart =
           phoneStart ?? _firebasePhoneStart(auth ?? FirebaseAuth.instance),
       _signOut = signOut ?? _firebaseSignOut(auth ?? FirebaseAuth.instance);

  final FirebaseAuth? _auth;
  final AccountDeletionGoogleSignIn _googleSignIn;
  final AccountDeletionPhoneStart _phoneStart;
  final AccountDeletionWebSignOut _signOut;

  AccountDeletionPhoneConfirmation? _pendingPhoneConfirmation;

  AccountDeletionWebAuthUser? get currentUser {
    final user = _auth?.currentUser;
    return user == null ? null : _fromFirebaseUser(user);
  }

  bool get hasPendingPhoneConfirmation => _pendingPhoneConfirmation != null;

  Future<AccountDeletionWebAuthUser> signInWithGoogle() {
    return _googleSignIn();
  }

  Future<void> startPhoneSignIn(String phoneNumber) async {
    final normalized = phoneNumber.trim();
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized)) {
      throw const FormatException(
        'Telefon numarası ülke koduyla birlikte geçerli olmalıdır.',
      );
    }

    _pendingPhoneConfirmation = await _phoneStart(normalized);
  }

  Future<AccountDeletionWebAuthUser> confirmPhoneCode(
    String verificationCode,
  ) async {
    final normalized = verificationCode.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(normalized)) {
      throw const FormatException('Doğrulama kodu geçerli değil.');
    }

    final confirmation = _pendingPhoneConfirmation;
    if (confirmation == null) {
      throw StateError('Telefon doğrulaması başlatılmadı.');
    }

    final user = await confirmation.confirm(normalized);
    _pendingPhoneConfirmation = null;
    return user;
  }

  Future<void> signOut() async {
    _pendingPhoneConfirmation = null;
    await _signOut();
  }

  static AccountDeletionGoogleSignIn _firebaseGoogleSignIn(FirebaseAuth auth) {
    return () async {
      if (!kIsWeb) {
        throw UnsupportedError('Google web sign-in requires a web platform.');
      }

      final credential = await auth.signInWithPopup(GoogleAuthProvider());
      final user = credential.user;
      if (user == null) {
        throw StateError('Google sign-in returned no authenticated user.');
      }
      return _fromFirebaseUser(user);
    };
  }

  static AccountDeletionPhoneStart _firebasePhoneStart(FirebaseAuth auth) {
    return (phoneNumber) async {
      if (!kIsWeb) {
        throw UnsupportedError('Phone web sign-in requires a web platform.');
      }

      final result = await auth.signInWithPhoneNumber(phoneNumber);
      return _FirebasePhoneConfirmation(result);
    };
  }

  static AccountDeletionWebSignOut _firebaseSignOut(FirebaseAuth auth) {
    return auth.signOut;
  }

  static AccountDeletionWebAuthUser _fromFirebaseUser(User user) {
    return AccountDeletionWebAuthUser(
      uid: user.uid,
      phoneNumber: user.phoneNumber,
      email: user.email,
      displayName: user.displayName,
      providerIds: user.providerData
          .map((provider) => provider.providerId)
          .where((providerId) => providerId.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class _FirebasePhoneConfirmation implements AccountDeletionPhoneConfirmation {
  const _FirebasePhoneConfirmation(this._delegate);

  final ConfirmationResult _delegate;

  @override
  Future<AccountDeletionWebAuthUser> confirm(String verificationCode) async {
    final credential = await _delegate.confirm(verificationCode);
    final user = credential.user;
    if (user == null) {
      throw StateError('Phone sign-in returned no authenticated user.');
    }
    return AccountDeletionWebAuthService._fromFirebaseUser(user);
  }
}
