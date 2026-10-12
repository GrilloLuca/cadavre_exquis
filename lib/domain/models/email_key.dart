/// The key a user's per-email documents (`userProfiles`, `ageChecks`) are
/// stored under, so `Luca@Gmail.com` and `luca@gmail.com` share them.
String emailKey(String email) => email.trim().toLowerCase();
