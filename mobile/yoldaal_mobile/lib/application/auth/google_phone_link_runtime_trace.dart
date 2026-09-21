/// Process-local diagnostic history for the Google -> canonical-phone
/// linking flow.
///
/// This class deliberately stores only an allow-listed set of non-sensitive
/// state codes. It stores no account identifiers, phone numbers, email
/// addresses, OTP values, credentials, tokens, arbitrary messages or
/// timestamps.
///
/// The trace is memory-only. It is intentionally not persisted to disk.
class GooglePhoneLinkRuntimeTrace {
  static const int capacity = 32;

  static const Set<String> allowedCodes = <String>{
    'phone_verification_required',
    'phone_verification_requesting',
    'manual_code_required',
    'auto_verification_linking',
    'link_succeeded',
    'direct_google_signed_in',
    'phone_verification_throttled',
    'phone_verification_failed',
    'phone_sign_in_failed',
    'link_unexpected',
    'phone_session_missing',
    'missing_pending_google_link',
    'google_firebase_signin_failed',
    'google_account_link_credential_in_use',
    'google_account_link_account_conflict',
    'google_account_already_linked',
    'google_account_link_network_failed',
    'google_account_link_not_allowed',
    'google_account_link_invalid_credential',
    'google_account_link_reauth_required',
    'google_account_link_user_disabled',
    'google_account_link_internal',
    'google_account_link_failed',
  };

  final List<String> _codes = <String>[];

  String? get latestCode => _codes.isEmpty ? null : _codes.last;

  List<String> snapshot() => List<String>.unmodifiable(_codes);

  bool record(String code) {
    if (!allowedCodes.contains(code)) {
      return false;
    }

    _codes.add(code);

    final overflow = _codes.length - capacity;
    if (overflow > 0) {
      _codes.removeRange(0, overflow);
    }

    return true;
  }

  void clear() {
    _codes.clear();
  }
}

final GooglePhoneLinkRuntimeTrace googlePhoneLinkRuntimeTrace =
    GooglePhoneLinkRuntimeTrace();
