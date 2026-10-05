import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/account_links.dart';
import '../auth/apple_identity_provider.dart';
import '../auth/auth_flow.dart';
import '../core/api.dart';
import '../core/environment.dart';
import '../core/session.dart';
import 'account_components.dart';
import 'advanced_server_page.dart';
import 'conversation_orb.dart';
import 'mobile_design.dart';
import 'strings.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.vault,
    required this.onSignedIn,
    this.initialOrigin,
    this.apiFactory = createAuthApi,
    this.appleIdentityProvider = const UnconfiguredAppleIdentityProvider(),
  });
  final Vault vault;
  final String? initialOrigin;
  final Future<void> Function(TypefluxApi) onSignedIn;
  final AuthApiFactory apiFactory;
  final AppleIdentityProvider appleIdentityProvider;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  final email = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  final newPassword = TextEditingController();
  final scroll = ScrollController();
  late final AuthFlow flow;
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => unawaited(_legal(privacy: false));
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => unawaited(_legal(privacy: true));
  bool _welcome = true;
  bool showPassword = false, showNewPassword = false;
  AuthStep _previousStep = AuthStep.signIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    flow = AuthFlow(
      vault: widget.vault,
      origin: widget.initialOrigin ?? AppEnvironment.current.resolveOrigin(),
      apiFactory: widget.apiFactory,
      onSignedIn: widget.onSignedIn,
    )..addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (flow.step != _previousStep) {
      _previousStep = flow.step;
      password.text = flow.password;
      newPassword.text = flow.newPassword;
      code.text = flow.code;
      showPassword = false;
      showNewPassword = false;
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) scroll.jumpTo(0);
      });
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) flow.refreshClock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    flow.removeListener(_changed);
    flow.dispose();
    email.dispose();
    password.dispose();
    newPassword.dispose();
    code.dispose();
    scroll.dispose();
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  void _navigate(AuthStep step) {
    if (flow.working) return;
    FocusManager.instance.primaryFocus?.unfocus();
    flow.navigate(step);
    setState(() => _welcome = false);
  }

  void _back() {
    if (flow.working) return;
    if (flow.step == AuthStep.signIn) {
      flow.navigate(AuthStep.signIn);
      password.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _welcome = true);
    } else {
      _navigate(
        flow.step == AuthStep.resetPassword
            ? AuthStep.forgotPassword
            : AuthStep.signIn,
      );
    }
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(flow.submit());
  }

  Future<void> _legal({required bool privacy}) async {
    var opened = false;
    try {
      opened = await openAccountLegal(
        privacy: privacy,
        chinese: Localizations.localeOf(context).languageCode == 'zh',
      );
    } catch (_) {
      // Surface a stable message; platform failures may include private state.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'authLegalOpenFailed'))),
      );
    }
  }

  Future<void> _advanced() async {
    if (flow.working) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AdvancedServerPage(origin: flow.origin),
      ),
    );
    if (!mounted || value == null) return;
    flow.changeOrigin(value);
    password.clear();
    newPassword.clear();
    code.clear();
  }

  Widget _emailField({bool done = false}) => AccountField(
    key: const ValueKey('auth-email'),
    grouped: true,
    label: tr(context, 'email'),
    hint: tr(context, 'authEmailHint'),
    controller: email,
    enabled: !flow.working,
    keyboardType: TextInputType.emailAddress,
    textInputAction: done ? TextInputAction.done : TextInputAction.next,
    autofillHints: const [AutofillHints.email],
    onChanged: (value) {
      flow.email = value;
      flow.clearFieldError('email');
    },
    onSubmitted: done ? (_) => _submit() : null,
  );

  Widget _passwordField({bool resetting = false}) {
    final shown = resetting ? showNewPassword : showPassword;
    return AccountField(
      key: ValueKey(resetting ? 'auth-new-password' : 'auth-password'),
      grouped: true,
      label: tr(context, resetting ? 'authNewPassword' : 'password'),
      hint: resetting || flow.step == AuthStep.register
          ? tr(context, 'authNewPasswordHint')
          : '••••••••',
      controller: resetting ? newPassword : password,
      enabled: !flow.working,
      obscureText: !shown,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      autofillHints: [
        resetting || flow.step == AuthStep.register
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      onChanged: (value) {
        if (resetting) {
          flow.newPassword = value;
        } else {
          flow.password = value;
        }
        flow.clearFieldError(resetting ? 'newPassword' : 'password');
      },
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _secondary(
    String label,
    VoidCallback action, {
    Key? key,
    bool enabled = true,
  }) => TextButton(
    key: key,
    onPressed: flow.working || !enabled ? null : action,
    style: TextButton.styleFrom(
      foregroundColor: MobilePalette.of(context).accentText,
      textStyle: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500),
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    child: Text(label, textAlign: TextAlign.center),
  );

  Widget _caption(String key, {TextAlign align = TextAlign.left}) => Text(
    tr(context, key),
    textAlign: align,
    style: TextStyle(
      color: MobilePalette.of(context).secondary,
      fontSize: 12,
      height: 1.5,
    ),
  );

  Widget _welcomeButton({
    required String key,
    required String label,
    required IconData icon,
    required bool apple,
    required VoidCallback onPressed,
  }) {
    final p = MobilePalette.of(context);
    final foreground = apple ? (p.dark ? Colors.black : Colors.white) : p.ink;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: FilledButton(
        key: ValueKey(key),
        onPressed: flow.working ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: apple
              ? (p.dark ? Colors.white : Colors.black)
              : p.surface,
          foregroundColor: foreground,
          disabledBackgroundColor: apple
              ? (p.dark ? Colors.white : Colors.black)
              : p.surface,
          disabledForegroundColor: foreground.withValues(alpha: .6),
          shape: StadiumBorder(
            side: apple
                ? BorderSide.none
                : BorderSide(color: p.line, width: .5),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (apple && flow.busy)
              SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              DesignIcon(icon, size: 19, color: foreground),
            const SizedBox(width: 9),
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  Widget _welcomePage() {
    final p = MobilePalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              minHeight: constraints.maxHeight,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 29),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: constraints.maxHeight >= 650 ? 142 : 52),
                    const Center(child: ConversationOrb(size: 132, phase: .62)),
                    const SizedBox(height: 26),
                    Text(
                      'Typeflux',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.2,
                        letterSpacing: -.3,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'authWelcomeDescription'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: p.secondary,
                      ),
                    ),
                    const SizedBox(height: 60),
                    const Spacer(),
                    _welcomeButton(
                      key: 'auth-apple',
                      label: tr(context, 'authContinueApple'),
                      icon: Icons.apple,
                      apple: true,
                      onPressed: () => unawaited(
                        flow.signInWithApple(widget.appleIdentityProvider),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _welcomeButton(
                      key: 'auth-email-login',
                      label: tr(context, 'authContinueEmail'),
                      icon: Icons.mail_outline,
                      apple: false,
                      onPressed: () => _navigate(AuthStep.signIn),
                    ),
                    if (flow.error != null) ...[
                      const SizedBox(height: 12),
                      AccountNotice(
                        text: tr(context, flow.error!),
                        error: true,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: tr(context, 'authLegalPrefix')),
                          TextSpan(
                            text: tr(context, 'authTerms'),
                            style: TextStyle(color: p.secondary),
                            recognizer: _terms,
                          ),
                          TextSpan(text: tr(context, 'authLegalAnd')),
                          TextSpan(
                            text: tr(context, 'authPrivacy'),
                            style: TextStyle(color: p.secondary),
                            recognizer: _privacy,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.6,
                        color: p.muted,
                      ),
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

  Widget _emailPage() {
    final p = MobilePalette.of(context);
    final signIn = flow.step == AuthStep.signIn;
    final register = flow.step == AuthStep.register;
    final activate = flow.step == AuthStep.activate;
    final forgot = flow.step == AuthStep.forgotPassword;
    final reset = flow.step == AuthStep.resetPassword;
    final title = switch (flow.step) {
      AuthStep.signIn => 'authEmailLoginTitle',
      AuthStep.register => 'authCreateAccount',
      AuthStep.activate => 'authVerifyEmail',
      AuthStep.forgotPassword => 'authForgotTitle',
      AuthStep.resetPassword => 'authResetTitle',
    };
    final subtitle = switch (flow.step) {
      AuthStep.signIn => 'authEmailLoginSubtitle',
      AuthStep.register => 'authRegisterSubtitle',
      AuthStep.activate =>
        flow.activationCodeSent
            ? 'authVerifySubtitle'
            : 'authVerifySubtitlePending',
      AuthStep.forgotPassword => 'authForgotSubtitle',
      AuthStep.resetPassword => 'authResetSubtitle',
    };
    final action = switch (flow.step) {
      AuthStep.signIn => 'login',
      AuthStep.register => 'authCreateAccount',
      AuthStep.activate => 'authVerifyAndSignIn',
      AuthStep.forgotPassword => 'authSendResetCode',
      AuthStep.resetPassword => 'authResetTitle',
    };
    final groupError = flow.fieldErrors.values.firstOrNull ?? flow.error;
    return Stack(
      children: [
        SingleChildScrollView(
          controller: scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 74, 24, 28),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          tr(context, title),
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.45,
                            color: p.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(context, subtitle),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: p.secondary,
                        ),
                      ),
                      if (activate || reset) ...[
                        const SizedBox(height: 8),
                        Text(
                          flow.email.trim(),
                          style: TextStyle(fontSize: 15, color: p.secondary),
                        ),
                      ],
                      const SizedBox(height: 28),
                      AccountFieldGroup(
                        children: [
                          if (signIn || register || forgot)
                            _emailField(done: forgot),
                          if (signIn || register) _passwordField(),
                          if (activate || reset)
                            AccountField(
                              key: const ValueKey('auth-code'),
                              grouped: true,
                              label: tr(context, 'authCodeLabel'),
                              hint: tr(context, 'authCodeHint'),
                              controller: code,
                              enabled: !flow.working,
                              keyboardType: TextInputType.number,
                              textInputAction: reset
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              onChanged: (value) {
                                flow.code = value;
                                flow.clearFieldError('code');
                              },
                              onSubmitted: activate ? (_) => _submit() : null,
                            ),
                          if (reset) _passwordField(resetting: true),
                        ],
                      ),
                      if (groupError != null) ...[
                        const SizedBox(height: 8),
                        AccountNotice(
                          text: tr(context, groupError),
                          error: true,
                        ),
                      ],
                      if (register || reset) ...[
                        const SizedBox(height: 8),
                        _caption('authPasswordRules'),
                      ],
                      if (activate || reset) ...[
                        const SizedBox(height: 8),
                        _caption(
                          activate ? 'authCodeExpiry' : 'authResetCodeExpiry',
                        ),
                      ],
                      if (flow.notice != null &&
                          flow.notice != 'authActivationSent' &&
                          flow.notice != 'authResetSent') ...[
                        const SizedBox(height: 12),
                        AccountNotice(text: tr(context, flow.notice!)),
                      ],
                      const SizedBox(height: 22),
                      AccountPrimaryButton(
                        key: const ValueKey('auth-submit'),
                        label: tr(context, action),
                        busy: flow.busy,
                        onPressed: flow.working ? null : _submit,
                      ),
                      if (signIn) ...[
                        const SizedBox(height: 5),
                        Center(
                          child: _secondary(
                            tr(context, 'authForgotLink'),
                            () => _navigate(AuthStep.forgotPassword),
                            key: const ValueKey('auth-forgot'),
                          ),
                        ),
                      ],
                      if (register || reset) ...[
                        const SizedBox(height: 12),
                        _caption(
                          register ? 'authNextVerify' : 'authResetReturn',
                          align: TextAlign.center,
                        ),
                      ],
                      if (activate || reset) ...[
                        const SizedBox(height: 12),
                        _secondary(
                          flow.resending
                              ? tr(context, 'authSending')
                              : flow.resendSeconds > 0
                              ? tr(context, 'authResendCountdown').replaceAll(
                                  '{seconds}',
                                  '${flow.resendSeconds}',
                                )
                              : tr(context, 'authResend'),
                          () => unawaited(flow.resend()),
                          key: const ValueKey('auth-resend'),
                          enabled: flow.resendSeconds == 0,
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (signIn || register)
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              tr(
                                context,
                                signIn ? 'authNoAccount' : 'authHasAccount',
                              ),
                              style: TextStyle(
                                color: p.secondary,
                                fontSize: 14,
                              ),
                            ),
                            _secondary(
                              tr(
                                context,
                                signIn ? 'authCreateAccount' : 'login',
                              ),
                              () => _navigate(
                                signIn ? AuthStep.register : AuthStep.signIn,
                              ),
                              key: const ValueKey('auth-switch'),
                            ),
                          ],
                        )
                      else
                        _secondary(
                          tr(context, 'authBackToLogin'),
                          () => _navigate(AuthStep.signIn),
                        ),
                      if (signIn)
                        Center(
                          child: _secondary(
                            tr(context, 'settingAdvanced'),
                            () => unawaited(_advanced()),
                            key: const ValueKey('auth-advanced'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 2,
          left: 16,
          child: AccountBackButton(onPressed: flow.working ? null : _back),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _welcome && !flow.working,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !flow.working && !_welcome) _back();
    },
    child: AccountScaffold(
      child: SafeArea(child: _welcome ? _welcomePage() : _emailPage()),
    ),
  );
}
