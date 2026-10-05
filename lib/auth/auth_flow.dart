import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/session.dart';
import 'apple_identity_provider.dart';

enum AuthStep { signIn, register, activate, forgotPassword, resetPassword }

typedef AuthApiFactory = TypefluxApi Function(Uri origin, Vault vault);

TypefluxApi createAuthApi(Uri origin, Vault vault) =>
    TypefluxApi(origin: origin, vault: vault);

/// Owns the email-account flow. Passwords and codes remain in memory only.
class AuthFlow extends ChangeNotifier {
  AuthFlow({
    required this.vault,
    required this.origin,
    required this.onSignedIn,
    this.apiFactory = createAuthApi,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Vault vault;
  final AuthApiFactory apiFactory;
  final Future<void> Function(TypefluxApi) onSignedIn;
  final DateTime Function() _now;
  String origin;
  AuthStep step = AuthStep.signIn;
  String email = '', password = '', code = '', newPassword = '';
  String? error, notice;
  final Map<String, String> fieldErrors = {};
  bool busy = false, resending = false;
  bool activationCodeSent = false;
  bool _disposed = false;
  TypefluxApi? _activeApi;
  DateTime? _resendAfter;
  Timer? _timer;
  bool get working => busy || resending;

  int get resendSeconds {
    final remaining = _resendAfter?.difference(_now()).inMilliseconds ?? 0;
    return remaining > 0 ? (remaining / 1000).ceil() : 0;
  }

  static String? validateEmail(String email) {
    final value = email.trim();
    if (value.isEmpty) return 'authEmailRequired';
    if (value.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      return 'authEmailInvalid';
    }
    return null;
  }

  static String? validatePassword(String password) {
    if (password.isEmpty) return 'authPasswordRequired';
    if (password.runes.length < 8 ||
        !RegExp(r'\p{Lu}', unicode: true).hasMatch(password) ||
        !RegExp(r'\p{Ll}', unicode: true).hasMatch(password) ||
        !RegExp(r'\p{Nd}', unicode: true).hasMatch(password)) {
      return 'authPasswordRules';
    }
    return null;
  }

  static String? validateCode(String code) =>
      RegExp(r'^\d{6}$').hasMatch(code) ? null : 'authCodeInvalid';

  void navigate(AuthStep next) {
    if (working || _disposed) return;
    step = next;
    error = null;
    notice = null;
    fieldErrors.clear();
    code = '';
    newPassword = '';
    if (next == AuthStep.signIn || next == AuthStep.forgotPassword) {
      password = '';
    }
    if (next != AuthStep.activate && next != AuthStep.resetPassword) {
      _stopCooldown();
    }
    notifyListeners();
  }

  void changeOrigin(String value) {
    if (working || _disposed || origin == value) return;
    origin = value;
    password = '';
    code = '';
    newPassword = '';
    _resendAfter = null;
    _timer?.cancel();
    step = AuthStep.signIn;
    error = null;
    notice = null;
    fieldErrors.clear();
    notifyListeners();
  }

  void clearFieldError(String field) {
    if (_disposed || !fieldErrors.containsKey(field)) return;
    fieldErrors.remove(field);
    notifyListeners();
  }

  bool _validate() {
    fieldErrors.clear();
    final emailError = validateEmail(email);
    if (emailError != null) fieldErrors['email'] = emailError;
    switch (step) {
      case AuthStep.signIn:
        if (password.isEmpty) fieldErrors['password'] = 'authPasswordRequired';
      case AuthStep.register:
        final result = validatePassword(password);
        if (result != null) fieldErrors['password'] = result;
      case AuthStep.activate:
        final result = validateCode(code);
        if (result != null) fieldErrors['code'] = result;
      case AuthStep.resetPassword:
        final codeError = validateCode(code);
        if (codeError != null) fieldErrors['code'] = codeError;
        final passwordError = validatePassword(newPassword);
        if (passwordError != null) fieldErrors['newPassword'] = passwordError;
      case AuthStep.forgotPassword:
        break;
    }
    if (fieldErrors.isNotEmpty) notifyListeners();
    return fieldErrors.isEmpty;
  }

  Future<void> submit() async {
    if (working || _disposed) return;
    error = null;
    notice = null;
    if (!_validate()) return;
    busy = true;
    notifyListeners();
    TypefluxApi? api;
    var transferred = false;
    try {
      api = apiFactory(Uri.parse(origin), vault);
      _activeApi = api;
      final selected = step;
      final address = email.trim();
      switch (selected) {
        case AuthStep.signIn:
          await api.login(address, password);
          if (_disposed) {
            await _discardSession(api);
            return;
          }
          transferred = true;
          _activeApi = null;
          try {
            await onSignedIn(api);
          } catch (_) {
            transferred = false;
            await _discardSession(api);
            rethrow;
          }
          password = '';
        case AuthStep.register:
          await api.request(
            'POST',
            '/auth/register',
            authenticated: false,
            body: {'email': address, 'password': password},
          );
          if (_disposed) return;
          step = AuthStep.activate;
          activationCodeSent = true;
          code = '';
          notice = 'authActivationSent';
          _startCooldown();
        case AuthStep.activate:
          await api.request(
            'POST',
            '/auth/activate',
            authenticated: false,
            body: {'email': address, 'code': code},
          );
          if (_disposed) return;
          // Keep activation success separate from a subsequent sign-in failure.
          step = AuthStep.signIn;
          code = '';
          notice = 'authActivated';
          _stopCooldown();
          if (password.isNotEmpty) {
            await api.login(address, password);
            if (_disposed) {
              await _discardSession(api);
              return;
            }
            transferred = true;
            _activeApi = null;
            try {
              await onSignedIn(api);
            } catch (_) {
              transferred = false;
              await _discardSession(api);
              rethrow;
            }
            password = '';
          }
        case AuthStep.forgotPassword:
          await api.request(
            'POST',
            '/auth/forgot-password',
            authenticated: false,
            body: {'email': address},
          );
          if (_disposed) return;
          step = AuthStep.resetPassword;
          code = '';
          notice = 'authResetSent';
          _startCooldown();
        case AuthStep.resetPassword:
          await api.request(
            'POST',
            '/auth/reset-password',
            authenticated: false,
            body: {'email': address, 'code': code, 'new_password': newPassword},
          );
          if (_disposed) return;
          step = AuthStep.signIn;
          code = '';
          password = '';
          newPassword = '';
          notice = 'authPasswordReset';
          _stopCooldown();
      }
    } catch (failure) {
      if (!_disposed) {
        error = errorKey(failure);
        if (failure is ApiError && failure.code == 'AUTH_USER_NOT_ACTIVE') {
          step = AuthStep.activate;
          activationCodeSent = false;
          code = '';
        }
      }
    } finally {
      _activeApi = null;
      if (!transferred) api?.close();
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> signInWithApple(AppleIdentityProvider provider) async {
    if (working || _disposed) return;
    error = null;
    notice = null;
    fieldErrors.clear();
    busy = true;
    notifyListeners();
    TypefluxApi? api;
    var transferred = false;
    try {
      final identityToken = await provider.authenticate();
      if (_disposed) return;
      if (identityToken.isEmpty) {
        throw const AppleAuthorizationFailure('authAppleTokenMissing');
      }
      api = apiFactory(Uri.parse(origin), vault);
      _activeApi = api;
      await api.loginWithApple(identityToken);
      if (_disposed) {
        await _discardSession(api);
        return;
      }
      transferred = true;
      _activeApi = null;
      try {
        await onSignedIn(api);
      } catch (_) {
        transferred = false;
        await _discardSession(api);
        rethrow;
      }
      password = '';
      newPassword = '';
      code = '';
    } on AppleAuthorizationFailure catch (failure) {
      if (!_disposed && !failure.cancelled) error = failure.messageKey;
    } catch (failure) {
      if (!_disposed) error = errorKey(failure);
    } finally {
      _activeApi = null;
      if (!transferred) api?.close();
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resend() async {
    if (working || _disposed || resendSeconds > 0) return;
    if (step != AuthStep.activate && step != AuthStep.resetPassword) return;
    error = null;
    notice = null;
    if (step == AuthStep.activate && password.isEmpty) {
      error = 'authActivationPasswordNeeded';
      notifyListeners();
      return;
    }
    resending = true;
    notifyListeners();
    TypefluxApi? api;
    try {
      api = apiFactory(Uri.parse(origin), vault);
      _activeApi = api;
      await api.request(
        'POST',
        step == AuthStep.activate
            ? '/auth/resend-activation'
            : '/auth/forgot-password',
        authenticated: false,
        body: {
          'email': email.trim(),
          if (step == AuthStep.activate) 'password': password,
        },
      );
      if (_disposed) return;
      if (step == AuthStep.activate) activationCodeSent = true;
      notice = step == AuthStep.activate
          ? 'authActivationSent'
          : 'authResetSent';
      _startCooldown();
    } catch (failure) {
      if (!_disposed) {
        error = errorKey(failure);
        if (failure is ApiError && failure.status == 429) _startCooldown();
      }
    } finally {
      _activeApi = null;
      api?.close();
      resending = false;
      if (!_disposed) notifyListeners();
    }
  }

  void refreshClock() {
    if (_disposed) return;
    if (resendSeconds == 0) _timer?.cancel();
    notifyListeners();
  }

  void _startCooldown() {
    _resendAfter = _now().add(const Duration(seconds: 60));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => refreshClock());
  }

  void _stopCooldown() {
    _timer?.cancel();
    _resendAfter = null;
  }

  static String errorKey(Object error) {
    if (error is FormatException) return 'authServerInvalid';
    if (error is ApiError) {
      const known = {
        'AUTH_USER_EXISTS',
        'AUTH_INVALID_CREDENTIALS',
        'AUTH_USER_NOT_ACTIVE',
        'AUTH_ACTIVATION_INVALID',
        'AUTH_ACTIVATION_LOCKED',
        'AUTH_ACTIVATION_RESEND_LIMITED',
        'AUTH_EMAIL_NOT_FOUND',
        'AUTH_PASSWORD_TOO_WEAK',
        'AUTH_RESET_CODE_INVALID',
        'AUTH_RESET_CODE_LOCKED',
        'AUTH_EMAIL_DOMAIN_NOT_ALLOWED',
      };
      if (known.contains(error.code)) return error.code;
      if (error.status == 429) return 'authRateLimited';
      if (error.code == 'BAD_REQUEST') return 'authCheckFields';
      if (error.status >= 500) return 'authServiceUnavailable';
      return 'requestFailed';
    }
    return 'NETWORK_ERROR';
  }

  Future<void> _discardSession(TypefluxApi api) => api.discardSession();

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _activeApi?.close();
    password = '';
    newPassword = '';
    code = '';
    super.dispose();
  }
}
