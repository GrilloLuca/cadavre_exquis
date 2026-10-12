enum AuthErrorCode {
  /// Wrong email or password (or no account for that email).
  invalidCredentials,

  /// The password is too weak to register with.
  weakPassword,

  /// Any other failure; [AuthException.message] may describe it.
  other,
}

/// Thrown by `AuthRepository` operations. The UI layer maps [code] to a
/// localized message; for [AuthErrorCode.other] it may show [message], the
/// provider's own (English) description, as before this layer existed.
class AuthException implements Exception {
  final AuthErrorCode code;
  final String? message;

  const AuthException(this.code, {this.message});
}
