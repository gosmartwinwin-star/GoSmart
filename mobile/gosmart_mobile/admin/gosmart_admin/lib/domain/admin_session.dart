final class AdminSession {
  AdminSession({
    required String userId,
    required this.email,
    required this.hasYoldaAlAdminClaim,
  }) : userId = _required(userId);

  final String userId;
  final String? email;
  final bool hasYoldaAlAdminClaim;

  static String _required(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(value, 'userId');
    return trimmed;
  }
}
