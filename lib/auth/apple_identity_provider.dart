import 'package:flutter/foundation.dart';

/// The native authorization adapter supplies an Apple identity token only.
/// Typeflux sessions are created exclusively by the backend token exchange.
abstract interface class AppleIdentityProvider {
  Future<String> authenticate();
}

class AppleAuthorizationFailure implements Exception {
  const AppleAuthorizationFailure(this.messageKey, {this.cancelled = false});
  final String messageKey;
  final bool cancelled;
}

/// Signing and audience registration are deployment inputs, not client guesses.
/// Replace this adapter with native authorization after those inputs are ready.
class UnconfiguredAppleIdentityProvider implements AppleIdentityProvider {
  const UnconfiguredAppleIdentityProvider();

  @override
  Future<String> authenticate() async {
    throw AppleAuthorizationFailure(
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
          ? 'authAppleNotConfigured'
          : 'authApplePlatformUnavailable',
    );
  }
}
