import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mobile_design.dart';
import 'strings.dart';

/// Shared account surfaces from the final mobile v4 design.
class AccountScaffold extends StatelessWidget {
  const AccountScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: MobilePalette.of(context).bg,
    body: MobileAmbient(child: SizedBox.expand(child: child)),
  );
}

/// A single white group with persistent labels and hairline separators.
class AccountFieldGroup extends StatelessWidget {
  const AccountFieldGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.line, width: .5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: .5, thickness: .5, color: p.line),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class AccountField extends StatelessWidget {
  const AccountField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.errorText,
    this.enabled = true,
    this.obscureText = false,
    this.grouped = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
  });
  final String label;
  final TextEditingController controller;
  final String? hint, errorText;
  final bool enabled, obscureText, grouped;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted, onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    final field = Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: p.secondary,
                  ),
                ),
                const SizedBox(height: 3),
                Semantics(
                  label: label,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    obscureText: obscureText,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    autofillHints: autofillHints,
                    inputFormatters: inputFormatters,
                    onSubmitted: onSubmitted,
                    onChanged: onChanged,
                    cursorColor: p.accent,
                    cursorWidth: 2,
                    style: TextStyle(fontSize: 16.5, height: 1.2, color: p.ink),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(color: p.muted, fontSize: 16.5),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ?suffix,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        grouped ? field : AccountFieldGroup(children: [field]),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: AccountNotice(text: errorText!, error: true),
          ),
      ],
    );
  }
}

class AccountPrimaryButton extends StatelessWidget {
  const AccountPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: onPressed == null || busy
            ? []
            : [
                BoxShadow(
                  color: p.accent.withValues(alpha: .35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: p.accent.withValues(alpha: .38),
            disabledForegroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: const StadiumBorder(),
            textStyle: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600),
          ),
          child: busy
              ? Semantics(
                  label: label,
                  liveRegion: true,
                  child: const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class AccountNotice extends StatelessWidget {
  const AccountNotice({super.key, required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: TextStyle(
        color: error
            ? MobilePalette.of(context).red
            : MobilePalette.of(context).accentText,
        fontSize: 13,
        height: 1.45,
      ),
    ),
  );
}

class AccountBackButton extends StatelessWidget {
  const AccountBackButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => MobileIconButton(
    label: tr(context, 'authBack'),
    icon: Icons.chevron_left,
    onPressed: onPressed,
    glass: true,
    color: MobilePalette.of(context).ink,
  );
}
