import 'package:flutter/material.dart';

import '../core/api.dart';
import 'account_components.dart';
import 'mobile_design.dart';
import 'strings.dart';

/// An authenticated account cannot change origin without clearing its session.
class AdvancedServerPage extends StatefulWidget {
  const AdvancedServerPage({
    super.key,
    required this.origin,
    this.signedIn = false,
  });
  final String origin;
  final bool signedIn;

  @override
  State<AdvancedServerPage> createState() => _AdvancedServerPageState();
}

class _AdvancedServerPageState extends State<AdvancedServerPage> {
  late final TextEditingController _origin = TextEditingController(
    text: widget.origin,
  );
  String? _error;

  @override
  void dispose() {
    _origin.dispose();
    super.dispose();
  }

  void _save() {
    final next = Uri.tryParse(_origin.text.trim());
    try {
      if (next == null) throw const FormatException();
      TypefluxApi.validateOrigin(next);
      Navigator.pop(context, next.origin);
    } on FormatException {
      setState(() => _error = 'settingInvalidServer');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return AccountScaffold(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: AccountBackButton(
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  tr(context, 'settingAdvanced'),
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    context,
                    widget.signedIn
                        ? 'settingServerSignedIn'
                        : 'settingServerHelp',
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: p.secondary,
                  ),
                ),
                const SizedBox(height: 30),
                if (widget.signedIn) ...[
                  Text(
                    tr(context, 'server'),
                    style: TextStyle(fontSize: 14, color: p.secondary),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: p.panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: p.line),
                    ),
                    child: SelectableText(
                      widget.origin,
                      style: TextStyle(color: p.ink, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AccountNotice(text: tr(context, 'settingServerIsolation')),
                ] else ...[
                  AccountField(
                    label: tr(context, 'server'),
                    controller: _origin,
                    hint: 'https://api.typeflux.app',
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    errorText: _error == null ? null : tr(context, _error!),
                    onSubmitted: (_) => _save(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  const SizedBox(height: 28),
                  AccountPrimaryButton(
                    label: tr(context, 'settingSave'),
                    onPressed: _save,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
