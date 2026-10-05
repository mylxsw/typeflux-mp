import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../chat/chat_controller.dart';
import 'account_identity.dart';
import 'mobile_design.dart';
import 'settings_page.dart';
import 'strings.dart';

class MobileHistory extends StatefulWidget {
  const MobileHistory({
    super.key,
    required this.controller,
    required this.onNew,
    required this.onSelected,
    required this.onLogout,
    required this.onDelete,
    this.onClose,
  });
  final ChatController controller;
  final VoidCallback onNew, onSelected;
  final VoidCallback? onClose;
  final Future<void> Function() onLogout, onDelete;
  @override
  State<MobileHistory> createState() => _MobileHistoryState();
}

class _MobileHistoryState extends State<MobileHistory> {
  String query = '';
  String? revealed;
  final _searchFocus = FocusNode();
  ChatController get chat => widget.controller;
  bool get locked =>
      chat.busy ||
      chat.loading ||
      chat.historyRefreshing ||
      chat.pending != null;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && chat.accountSummary == null) {
        unawaited(chat.refreshAccountSummary());
      }
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  String _group(Map<String, dynamic> item) {
    final value = DateTime.tryParse(item['updated_at'] as String? ?? '')
        ?.toLocal();
    if (value == null) return 'earlier';
    final today = DateUtils.dateOnly(DateTime.now()),
        date = DateUtils.dateOnly(value);
    if (date == today) return 'today';
    if (date == DateTime(today.year, today.month, today.day - 1)) {
      return 'yesterday';
    }
    return 'earlier';
  }

  String _time(BuildContext context, Map<String, dynamic> item) {
    final date = DateTime.tryParse(item['updated_at'] as String? ?? '')
        ?.toLocal();
    if (date == null) return '';
    if (_group(item) == 'earlier') {
      return MaterialLocalizations.of(context).formatShortMonthDay(date);
    }
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: chat,
    builder: (context, _) {
      final p = MobilePalette.of(context);
      final items = chat.conversations
          .where(
            (item) => (item['title'] as String? ?? '').toLowerCase().contains(
              query.toLowerCase(),
            ),
          )
          .toList();
      const radius = BorderRadius.only(
        topLeft: Radius.circular(47),
        bottomLeft: Radius.circular(47),
        topRight: Radius.circular(30),
        bottomRight: Radius.circular(30),
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .1),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Material(
              color: p.dark ? const Color(0xb82c2c34) : const Color(0xdbfafafc),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(width: .5, color: p.cardBorder),
                ),
                padding: const EdgeInsets.fromLTRB(12, 58, 12, 12),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr(context, 'ask'),
                              style: TextStyle(
                                fontSize: 22,
                                letterSpacing: -.22,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                          ),
                          SizedBox.square(
                            dimension: 36,
                            child: IconButton(
                              tooltip: tr(context, 'new'),
                              padding: EdgeInsets.zero,
                              onPressed: locked ? null : widget.onNew,
                              icon: DesignIcon(
                                Icons.edit_square,
                                size: 20,
                                color: p.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _search(context),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: chat.refreshHistory,
                        color: p.accent,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          children: [
                            if (items.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  tr(
                                    context,
                                    query.isEmpty
                                        ? 'noConversations'
                                        : 'noMatches',
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: p.secondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            for (final group in [
                              'today',
                              'yesterday',
                              'earlier',
                            ])
                              if (items.any(
                                (item) => _group(item) == group,
                              )) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    14,
                                    12,
                                    5,
                                  ),
                                  child: Text(
                                    tr(context, group),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: p.muted,
                                    ),
                                  ),
                                ),
                                for (final item in items.where(
                                  (item) => _group(item) == group,
                                ))
                                  _row(context, item),
                              ],
                            if (chat.hasMore)
                              TextButton(
                                onPressed: chat.loading ? null : chat.loadMore,
                                child: Text(tr(context, 'more')),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: p.line, width: .5),
                        ),
                      ),
                      child: InkWell(
                        key: const ValueKey('history-account'),
                        onTap: _account,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                          child: Row(
                            children: [
                              AccountAvatar(
                                initials: accountInitials(
                                  chat.accountName,
                                  chat.accountEmail,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 3,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      chat.accountName?.isNotEmpty == true
                                          ? chat.accountName!
                                          : chat.accountEmail ?? 'Typeflux',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: p.ink,
                                      ),
                                    ),
                                    if (chat.accountSummary?.plan != null)
                                      AccountPlanBadge(
                                        plan: chat.accountSummary!.plan!,
                                        paid: chat.accountSummary!.paid,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Semantics(
                                label: tr(context, 'accountSettings'),
                                button: true,
                                child: DesignIcon(
                                  Icons.settings_outlined,
                                  size: 20,
                                  color: p.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _search(BuildContext context) {
    final p = MobilePalette.of(context);
    final height = (MediaQuery.textScalerOf(context).scale(18) + 16)
        .clamp(38.0, double.infinity)
        .toDouble();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _searchFocus.requestFocus,
      // The visible field is 38 pt; its surrounding area also focuses it.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: SizedBox(
          height: height,
          child: TextField(
            key: const ValueKey('history-search'),
            focusNode: _searchFocus,
            textAlignVertical: TextAlignVertical.center,
            onChanged: (value) => setState(() {
              query = value;
              revealed = null;
            }),
            style: TextStyle(fontSize: 15, height: 1.2, color: p.ink),
            decoration: InputDecoration(
              hintText: tr(context, 'searchConversations'),
              hintStyle: TextStyle(color: p.muted),
              prefixIcon: SizedBox(
                width: 33,
                height: height,
                child: Padding(
                  padding: const EdgeInsets.only(left: 11, right: 7),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 15,
                      child: DesignIcon(Icons.search, size: 15, color: p.muted),
                    ),
                  ),
                ),
              ),
              prefixIconConstraints: BoxConstraints.tightFor(
                width: 33,
                height: height,
              ),
              filled: true,
              fillColor: p.hover,
              isDense: true,
              contentPadding: const EdgeInsets.only(right: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: p.accent.withValues(alpha: .35),
                  width: .5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> item) {
    final p = MobilePalette.of(context),
        id = item['id'] as String,
        selected = chat.current?.id == item['id'];
    final running = selected && chat.current?.active == true;
    final canMutate = !locked && !running;
    final open = revealed == id;
    return Semantics(
      selected: selected,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              if (open)
                Positioned.fill(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _SwipeAction(
                        label: tr(context, 'historyRename'),
                        color: p.accent,
                        onTap: canMutate ? _renameUnavailable : null,
                      ),
                      _SwipeAction(
                        label: tr(context, 'historyDeleteShort'),
                        color: Theme.of(context).colorScheme.error,
                        onTap: canMutate ? () => _delete(item) : null,
                      ),
                    ],
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(open ? -144 : 0, 0, 0),
                child: GestureDetector(
                  onHorizontalDragEnd: canMutate
                      ? (details) {
                          final speed = details.primaryVelocity ?? 0;
                          if (speed.abs() > 100) {
                            setState(() => revealed = speed > 0 ? null : id);
                          }
                        }
                      : null,
                  onHorizontalDragUpdate: canMutate
                      ? (details) {
                          if (details.delta.dx < -3 && !open) {
                            setState(() => revealed = id);
                          }
                          if (details.delta.dx > 3 && open) {
                            setState(() => revealed = null);
                          }
                        }
                      : null,
                  child: Material(
                    color: selected
                        ? (p.dark
                              ? const Color(0xff15263e)
                              : const Color(0xffe6eefd))
                        : open
                        ? (p.dark
                              ? const Color(0xff282830)
                              : const Color(0xfffafafc))
                        : Colors.transparent,
                    child: InkWell(
                      onLongPress: canMutate
                          ? () => setState(() => revealed = open ? null : id)
                          : null,
                      onTap: locked
                          ? null
                          : () {
                              if (open) {
                                setState(() => revealed = null);
                                return;
                              }
                              FocusScope.of(context).unfocus();
                              unawaited(chat.select(id));
                              widget.onSelected();
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            if (running) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: p.accent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: p.accent.withValues(alpha: .22),
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                item['title'] as String? ?? tr(context, 'new'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: selected
                                      ? (p.dark
                                            ? const Color(0xff8ebdff)
                                            : const Color(0xff1b57d6))
                                      : p.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _time(context, item),
                              style: TextStyle(
                                fontSize: 12,
                                color: p.muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameUnavailable() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(context, 'historyRename')),
      content: Text(tr(context, 'historyRenameUnavailable')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(context, 'settingDone')),
        ),
      ],
    ),
  );
  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'delete')),
        content: Text(tr(context, 'deleteConfirm')),
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
            child: Text(tr(context, 'historyDeleteShort')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await chat.deleteConversation(item['id'] as String);
    if (!mounted) return;
    setState(() => revealed = null);
    if (!success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr(context, 'requestFailed'))));
    }
  }

  Future<void> _account() {
    final host = Navigator.of(context).context;
    widget.onClose?.call();
    return showTypefluxSettings(
      host,
      controller: chat,
      onLogout: widget.onLogout,
    );
  }
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    child: Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    ),
  );
}
