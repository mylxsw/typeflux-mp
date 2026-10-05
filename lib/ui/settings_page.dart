import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chat/chat_controller.dart';
import '../core/preferences.dart';
import 'account_components.dart';
import 'account_identity.dart';
import 'advanced_server_page.dart';
import 'change_password_page.dart';
import 'mobile_design.dart';
import 'strings.dart';

Future<void> showTypefluxSettings(
  BuildContext context, {
  required ChatController controller,
  required Future<void> Function() onLogout,
}) {
  final preferences = PreferencesScope.maybeOf(context);
  final size = MediaQuery.sizeOf(context);
  final top = MediaQuery.paddingOf(context).top;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .18),
    constraints: BoxConstraints(
      maxWidth: 520,
      maxHeight: size.height - (top > 54 ? top + 4 : 58),
    ),
    builder: (_) => SettingsPage(
      controller: controller,
      onLogout: onLogout,
      preferences: preferences,
      presentedAsSheet: true,
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.onLogout,
    this.preferences,
    this.presentedAsSheet = false,
    this.version,
  });
  final ChatController controller;
  final Future<void> Function() onLogout;
  final AppPreferences? preferences;
  final bool presentedAsSheet;

  /// Tests can supply their build fixture; release UI reads platform metadata.
  final String? version;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppPreferences _preferences;
  bool _saving = false;
  String? _error, _version;

  @override
  void initState() {
    super.initState();
    _preferences =
        widget.preferences ?? AppPreferences(widget.controller.api.vault);
    _version = widget.version;
    if (widget.preferences == null) unawaited(_loadPreferences());
    if (_version == null) unawaited(_loadVersion());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.refreshAccountSummary());
    });
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      /* Unknown build metadata is displayed as unavailable. */
    }
  }

  Future<void> _loadPreferences() async {
    try {
      await _preferences.load();
    } catch (_) {
      if (mounted) setState(() => _error = 'settingLoadFailed');
    }
  }

  @override
  void dispose() {
    if (widget.preferences == null) _preferences.dispose();
    super.dispose();
  }

  Future<void> _save(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = 'settingSaveFailed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _languageLabel(BuildContext context) =>
      tr(context, switch (_preferences.locale?.languageCode) {
        'zh' => 'settingChinese',
        'en' => 'settingEnglish',
        _ => 'settingSystem',
      });
  Future<void> _language() async {
    final next = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MobilePalette.of(context).panel,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, label) in [
              ('', 'settingSystem'),
              ('zh', 'settingChinese'),
              ('en', 'settingEnglish'),
            ])
              ListTile(
                title: Text(tr(context, label)),
                trailing: (_preferences.locale?.languageCode ?? '') == value
                    ? DesignIcon(
                        Icons.check,
                        color: MobilePalette.of(context).accent,
                      )
                    : null,
                onTap: () => Navigator.pop(context, value),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (next != null && mounted) {
      await _save(
        () => _preferences.setLocale(next.isEmpty ? null : Locale(next)),
      );
    }
  }

  Future<void> _logout() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'settingLogoutTitle')),
        content: Text(tr(context, 'settingLogoutBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(tr(context, 'logout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await _save(() async {
      await widget.onLogout();
      if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
    });
  }

  Future<void> _privacy() async {
    try {
      if (!await launchUrl(
        Uri.parse('https://typeflux.app/privacy'),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('unavailable');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'settingOpenLinkFailed');
    }
  }

  Future<void> _deleteAccount() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(context, 'settingDeleteAccount')),
      content: Text(tr(context, 'settingDeleteUnavailable')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(context, 'settingDone')),
        ),
      ],
    ),
  );

  void _account() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => _AccountDetailsPage(
        controller: widget.controller,
        onLogout: widget.onLogout,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_preferences, widget.controller]),
    builder: (context, _) {
      final p = MobilePalette.of(context);
      final surface = ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
        child: Material(
          color: p.bg,
          child: PopScope(
            canPop: !_saving,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: p.dark
                        ? const Color(0x47787880)
                        : const Color(0x29787880),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          tr(context, 'settingTitle'),
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: MobileGlass(
                            radius: 18,
                            child: SizedBox(
                              height: 36,
                              child: TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.maybePop(context),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                  ),
                                  minimumSize: Size.zero,
                                  textStyle: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                child: Text(tr(context, 'settingDone')),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      MediaQuery.paddingOf(context).bottom + 22,
                    ),
                    children: [
                      _SettingsCard(
                        children: [
                          _profile(context),
                          Divider(height: .5, thickness: .5, color: p.line),
                          _credits(context),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
                        child: Text(
                          tr(context, 'settingGeneral'),
                          style: TextStyle(fontSize: 13, color: p.secondary),
                        ),
                      ),
                      _SettingsCard(
                        children: [
                          _appearance(context),
                          _SettingsRow(
                            icon: Icons.language,
                            tint: const Color(0xff2e6df0),
                            label: 'settingLanguage',
                            value: _languageLabel(context),
                            onTap: _saving ? null : _language,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SettingsCard(
                        children: [
                          _SettingsRow(
                            icon: Icons.front_hand_outlined,
                            tint: const Color(0xff34c759),
                            label: 'settingPrivacy',
                            onTap: _privacy,
                          ),
                          _SettingsRow(
                            icon: Icons.info_outline,
                            tint: const Color(0xff8e8e93),
                            label: 'settingVersion',
                            value: _version ?? '—',
                            chevron: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SettingsCard(
                        children: [
                          InkWell(
                            onTap: _saving ? null : _logout,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 50),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    tr(context, 'logout'),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _saving ? null : _deleteAccount,
                        style: TextButton.styleFrom(
                          foregroundColor: p.muted,
                          textStyle: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                        ),
                        child: Text(tr(context, 'settingDeleteAccount')),
                      ),
                      if (_saving)
                        const Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: AccountNotice(
                            text: tr(context, _error!),
                            error: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (widget.presentedAsSheet) return surface;
      return Scaffold(
        backgroundColor: p.bg,
        body: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top > 54
                ? MediaQuery.paddingOf(context).top + 4
                : 58,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: surface,
            ),
          ),
        ),
      );
    },
  );

  Widget _profile(BuildContext context) {
    final chat = widget.controller, p = MobilePalette.of(context);
    final plan = chat.accountSummary;
    return InkWell(
      key: const ValueKey('settings-profile'),
      onTap: _saving ? null : _account,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AccountAvatar(
              initials: accountInitials(chat.accountName, chat.accountEmail),
              size: 54,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        chat.accountName?.isNotEmpty == true
                            ? chat.accountName!
                            : tr(context, 'settingTypefluxAccount'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                        ),
                      ),
                      if (plan?.plan != null)
                        AccountPlanBadge(plan: plan!.plan!, paid: plan.paid),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (chat.accountEmail != null)
                    Text(
                      chat.accountEmail!,
                      style: TextStyle(fontSize: 13.5, color: p.secondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DesignIcon(Icons.chevron_right, size: 15, color: p.muted),
          ],
        ),
      ),
    );
  }

  Widget _credits(BuildContext context) {
    final chat = widget.controller,
        p = MobilePalette.of(context),
        summary = chat.accountSummary;
    final end = summary?.periodEnd?.toLocal();
    final date = end == null
        ? null
        : MaterialLocalizations.of(context).formatShortMonthDay(end);
    String amount(num value) =>
        value.toStringAsFixed(value == value.truncateToDouble() ? 0 : 2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, 'settingMonthlyCredits'),
                  style: TextStyle(fontSize: 13, color: p.secondary),
                ),
              ),
              if (date != null)
                Expanded(
                  child: Text(
                    tr(
                      context,
                      'settingCreditsReset',
                    ).replaceAll('{date}', date),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12.5, color: p.muted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (summary?.unlimited == true)
            Text(
              tr(context, 'settingUnlimited'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            )
          else if (summary?.hasBalance == true)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: amount(summary!.remaining!.clamp(0, double.infinity)),
                  ),
                  TextSpan(
                    text: ' / ${amount(summary.limit!)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: p.secondary,
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: p.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                tr(
                  context,
                  chat.accountSummaryLoading
                      ? 'settingCreditsLoading'
                      : 'settingCreditsUnavailable',
                ),
                style: TextStyle(fontSize: 14, color: p.secondary),
              ),
            ),
          if (summary?.remainingFraction != null)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Semantics(
                label: tr(context, 'settingMonthlyCredits'),
                value: '${(summary!.remainingFraction! * 100).round()}%',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    height: 6,
                    color: p.hover,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: summary.remainingFraction,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xff2e6df0), Color(0xff8c5cf5)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, 'settingSharedWithMac'),
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ),
              if (chat.accountSummaryError != null)
                TextButton(
                  onPressed: chat.refreshAccountSummary,
                  child: Text(tr(context, 'retry')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _appearance(BuildContext context) {
    final p = MobilePalette.of(context);
    final segment = Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.hover,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (mode, label) in [
            (ThemeMode.system, 'settingAutomatic'),
            (ThemeMode.light, 'settingLight'),
            (ThemeMode.dark, 'settingDark'),
          ])
            Semantics(
              selected: mode == _preferences.themeMode,
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: _saving
                    ? null
                    : () => _save(() => _preferences.setThemeMode(mode)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    color: mode == _preferences.themeMode ? p.panel : null,
                    boxShadow: mode == _preferences.themeMode
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .12),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    tr(context, label),
                    style: TextStyle(
                      fontSize: 13,
                      color: p.ink,
                      fontWeight: mode == _preferences.themeMode
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: LayoutBuilder(
        builder: (context, box) {
          final large =
              MediaQuery.textScalerOf(context).scale(16) > 20 ||
              box.maxWidth < 290;
          final label = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SettingIcon(Icons.dark_mode_outlined, const Color(0xff5856d6)),
              const SizedBox(width: 12),
              Text(
                tr(context, 'settingAppearance'),
                style: TextStyle(fontSize: 16, color: p.ink),
              ),
            ],
          );
          return large
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    const SizedBox(height: 8),
                    FittedBox(child: segment),
                  ],
                )
              : Row(children: [label, const Spacer(), segment]);
        },
      ),
    );
  }
}

class _AccountDetailsPage extends StatelessWidget {
  const _AccountDetailsPage({required this.controller, required this.onLogout});
  final ChatController controller;
  final Future<void> Function() onLogout;
  @override
  Widget build(BuildContext context) => AccountScaffold(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AccountBackButton(
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            tr(context, 'settingAccount'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          _SettingsCard(
            children: [
              _SettingsRow(
                icon: Icons.lock_outline_rounded,
                tint: const Color(0xff5856d6),
                label: controller.accountHasPassword != false
                    ? 'settingChangePassword'
                    : 'settingSetPassword',
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangePasswordPage(
                      controller: controller,
                      onLogout: onLogout,
                    ),
                  ),
                ),
              ),
              _SettingsRow(
                icon: Icons.settings_outlined,
                tint: const Color(0xff8e8e93),
                label: 'settingAdvanced',
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdvancedServerPage(
                      origin: controller.api.origin.origin,
                      signedIn: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return Material(
      color: p.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.line, width: .5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && children[i] is _SettingsRow)
              Divider(height: .5, thickness: .5, color: p.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon(this.icon, this.tint);
  final IconData icon;
  final Color tint;
  @override
  Widget build(BuildContext context) => Container(
    width: 29,
    height: 29,
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(child: DesignIcon(icon, color: Colors.white, size: 15)),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.tint,
    required this.label,
    this.onTap,
    this.value,
    this.chevron = true,
  });
  final IconData icon;
  final Color tint;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool chevron;
  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context),
        large = MediaQuery.textScalerOf(context).scale(16) > 21;
    final detail = value == null
        ? null
        : Text(
            value!,
            textAlign: large ? TextAlign.start : TextAlign.end,
            style: TextStyle(fontSize: 15, color: p.secondary),
          );
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _SettingIcon(icon, tint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, label),
                      style: TextStyle(fontSize: 16, color: p.ink),
                    ),
                    if (large && detail != null) detail,
                  ],
                ),
              ),
              if (!large && detail != null)
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: detail),
                ),
              if (chevron) ...[
                const SizedBox(width: 6),
                DesignIcon(Icons.chevron_right, size: 11, color: p.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
