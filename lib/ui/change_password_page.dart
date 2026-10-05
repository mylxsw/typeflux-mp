import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_flow.dart';
import '../chat/chat_controller.dart';
import '../core/api.dart';
import 'account_components.dart';
import 'mobile_design.dart';
import 'strings.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    required this.controller,
    required this.onLogout,
  });
  final ChatController controller;
  final Future<void> Function() onLogout;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _old = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false,
      _changed = false,
      _showOld = false,
      _showNew = false,
      _showConfirmation = false;
  String? _oldError, _passwordError, _confirmationError, _error;
  bool get _hasPassword => widget.controller.accountHasPassword != false;

  @override
  void dispose() {
    _old.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final message = tr(context, 'settingPasswordChanged');
    await widget.onLogout();
    if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_changed) {
      setState(() {
        _oldError = _hasPassword && _old.text.isEmpty
            ? 'settingOldPasswordRequired'
            : null;
        _passwordError = AuthFlow.validatePassword(_password.text) == null
            ? null
            : 'settingPasswordRules';
        _confirmationError =
            _confirmation.text != _password.text || _confirmation.text.isEmpty
            ? 'settingPasswordMismatch'
            : null;
        _error = null;
      });
      if (_oldError != null ||
          _passwordError != null ||
          _confirmationError != null) {
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      if (!_changed) {
        await widget.controller.changePassword(
          oldPassword: _hasPassword ? _old.text : null,
          newPassword: _password.text,
        );
        _changed = true;
        _old.clear();
        _password.clear();
        _confirmation.clear();
        TextInput.finishAutofillContext(shouldSave: false);
      }
      await _finish();
    } on ApiError catch (error) {
      if (mounted) {
        setState(() {
          if ([
                'AUTH_INVALID_CREDENTIALS',
                'INVALID_CREDENTIALS',
              ].contains(error.code) &&
              !_changed) {
            _oldError = 'settingOldPasswordIncorrect';
          } else if ([
                'AUTH_PASSWORD_TOO_WEAK',
                'PASSWORD_TOO_WEAK',
              ].contains(error.code) &&
              !_changed) {
            _passwordError = 'settingPasswordRules';
          } else {
            _error = switch (error.code) {
              'UNAUTHORIZED' ||
              'AUTH_REQUIRED' ||
              'AUTH_INVALID_TOKEN' ||
              'AUTH_REFRESH_TOKEN_INVALID' ||
              'AUTH_REFRESH_TOKEN_REUSED' => 'AUTH_REQUIRED',
              'TOO_MANY_REQUESTS' || 'RATE_LIMITED' => 'settingTryLater',
              _ => 'NETWORK_ERROR',
            };
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _changed ? 'settingSignOutRetry' : 'NETWORK_ERROR',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _visibility({
    required bool visible,
    required VoidCallback onPressed,
  }) => IconButton(
    tooltip: tr(
      context,
      visible ? 'settingHidePassword' : 'settingShowPassword',
    ),
    onPressed: _busy ? null : onPressed,
    icon: Icon(
      visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      size: 21,
      color: MobilePalette.of(context).secondary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return PopScope(
      canPop: !_busy && !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _changed && !_busy) _submit();
      },
      child: AccountScaffold(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AutofillGroup(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AccountBackButton(
                        onPressed: _busy
                            ? null
                            : _changed
                            ? _submit
                            : () => Navigator.maybePop(context),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      tr(
                        context,
                        _hasPassword
                            ? 'settingChangePassword'
                            : 'settingSetPassword',
                      ),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr(
                        context,
                        _hasPassword
                            ? 'settingPasswordHelp'
                            : 'settingSetPasswordHelp',
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: p.secondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_changed) ...[
                      AccountNotice(
                        text: tr(context, 'settingPasswordChanged'),
                      ),
                    ] else ...[
                      if (_hasPassword) ...[
                        AccountField(
                          label: tr(context, 'settingOldPassword'),
                          controller: _old,
                          enabled: !_busy,
                          obscureText: !_showOld,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.next,
                          errorText: _oldError == null
                              ? null
                              : tr(context, _oldError!),
                          suffix: _visibility(
                            visible: _showOld,
                            onPressed: () =>
                                setState(() => _showOld = !_showOld),
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],
                      AccountField(
                        label: tr(context, 'settingNewPassword'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: !_showNew,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        errorText: _passwordError == null
                            ? null
                            : tr(context, _passwordError!),
                        suffix: _visibility(
                          visible: _showNew,
                          onPressed: () => setState(() => _showNew = !_showNew),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(context, 'settingPasswordRules'),
                        style: TextStyle(
                          color: p.secondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      AccountField(
                        label: tr(context, 'settingConfirmPassword'),
                        controller: _confirmation,
                        enabled: !_busy,
                        obscureText: !_showConfirmation,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        errorText: _confirmationError == null
                            ? null
                            : tr(context, _confirmationError!),
                        onSubmitted: (_) => _submit(),
                        suffix: _visibility(
                          visible: _showConfirmation,
                          onPressed: () => setState(
                            () => _showConfirmation = !_showConfirmation,
                          ),
                        ),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: AccountNotice(
                          text: tr(context, _error!),
                          error: true,
                        ),
                      ),
                    const SizedBox(height: 28),
                    AccountPrimaryButton(
                      label: tr(
                        context,
                        _changed ? 'settingSignInAgain' : 'settingSavePassword',
                      ),
                      busy: _busy,
                      onPressed: _busy ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
