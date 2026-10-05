import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_controller.dart';
import 'conversation_orb.dart';
import 'mobile_design.dart';
import 'mobile_history.dart';
import 'mobile_transcript.dart';
import 'model_picker.dart';
import 'strings.dart';

class MobileChat extends StatefulWidget {
  const MobileChat({
    super.key,
    required this.controller,
    required this.composer,
    required this.scrollController,
    required this.attachments,
    required this.onAttach,
    required this.onSend,
    required this.onRemove,
    required this.onLogout,
    required this.onDelete,
    required this.onRetry,
    this.error,
    this.picking = false,
    this.onVoice,
    this.recording = false,
    this.voicePartial,
    this.voiceFailed = false,
    this.onShare,
  });
  final ChatController controller;
  final TextEditingController composer;
  final ScrollController scrollController;
  final List<Map<String, dynamic>> attachments;
  final Future<void> Function() onAttach, onSend, onLogout, onDelete;
  final ValueChanged<Map<String, dynamic>> onRemove;
  final VoidCallback onRetry;
  final String? error;
  final bool picking, recording, voiceFailed;
  final Future<void> Function()? onVoice;
  final Future<void> Function(String text)? onShare;
  final String? voicePartial;
  @override
  State<MobileChat> createState() => _MobileChatState();
}

class _MobileChatState extends State<MobileChat> {
  final draftFocus = FocusNode(), pickerFocus = FocusNode();
  final composerKey = GlobalKey();
  bool history = false, picker = false, modelsPage = false;
  double composerHeight = 108;
  ChatController get chat => widget.controller;
  bool get hasImages => widget.attachments.any((a) => a['kind'] == 'image');
  bool get incompatibleImage => hasImages && chat.selectedModel?.vision != true;
  bool get locked => chat.busy || chat.loading || chat.pending != null;
  @override
  void initState() {
    super.initState();
    widget.composer.addListener(_draftChanged);
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.composer.removeListener(_draftChanged);
    draftFocus.dispose();
    pickerFocus.dispose();
    super.dispose();
  }

  void _new() {
    FocusScope.of(context).unfocus();
    chat.newConversation();
    setState(() {
      history = false;
      picker = false;
    });
  }

  void _closePicker() {
    setState(() => picker = false);
    pickerFocus.requestFocus();
  }

  void _measureComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = composerKey.currentContext?.findRenderObject() as RenderBox?;
      if (mounted &&
          box != null &&
          (box.size.height - composerHeight).abs() > .5) {
        setState(() => composerHeight = box.size.height);
      }
    });
  }

  void _openHistory() {
    FocusScope.of(context).unfocus();
    setState(() {
      history = true;
      picker = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    _measureComposer();
    final empty =
        (chat.current?.messages.isEmpty ?? true) &&
        chat.current?.active != true;
    final safe = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final navigationTop = math.max(56.0, safe.top + 2);
    final bottom = keyboard ? 8.0 : math.max(30.0, safe.bottom + 9);
    return PopScope(
      canPop: !history && !picker,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            if (picker) {
              picker = false;
            } else {
              history = false;
            }
          });
        }
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: MobileAmbient(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final composerBottom = composerHeight + bottom;
              final popoverBottom = keyboard
                  ? composerBottom + 16
                  : math.max(148.0, composerBottom + 16);
              return Stack(
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      excluding: history,
                      child: empty
                          ? _empty(
                              context,
                              bounds.maxHeight,
                              navigationTop,
                              composerBottom,
                            )
                          : Padding(
                              padding: EdgeInsets.only(top: navigationTop + 56),
                              child: Column(
                                children: [
                                  if (chat.loading)
                                    LinearProgressIndicator(
                                      minHeight: 1,
                                      color: p.accent,
                                    ),
                                  if (chat.reconnecting)
                                    _notice(tr(context, 'reconnecting')),
                                  if (widget.error != null ||
                                      chat.error != null)
                                    _notice(
                                      friendlyError(
                                        context,
                                        widget.error ?? chat.error!,
                                      ),
                                      action: chat.pending == null
                                          ? widget.onRetry
                                          : null,
                                    ),
                                  if (chat.pending != null)
                                    _notice(
                                      tr(context, 'pending'),
                                      action: chat.busy
                                          ? null
                                          : () =>
                                                unawaited(chat.retryPending()),
                                    ),
                                  if (chat.current?.needsDevice == true)
                                    _notice(tr(context, 'deviceNeeded')),
                                  Expanded(
                                    child: MobileTranscript(
                                      controller: chat,
                                      scrollController: widget.scrollController,
                                      bottomPadding: composerBottom + 16,
                                      onShare: widget.onShare,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  if (empty && (widget.error != null || chat.error != null))
                    Positioned(
                      left: 0,
                      right: 0,
                      top: navigationTop + 56,
                      child: _notice(
                        friendlyError(context, widget.error ?? chat.error!),
                        action: widget.onRetry,
                      ),
                    ),
                  if (!empty)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: navigationTop + 64,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [.55, 1],
                              colors: [p.bg, p.bg.withValues(alpha: 0)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: navigationTop,
                    child: _navigation(context, empty),
                  ),
                  if (picker)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _closePicker,
                        child: Semantics(
                          label: tr(context, 'closePicker'),
                          button: true,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: bottom,
                    child: _composer(context),
                  ),
                  if (picker)
                    Positioned(
                      left: modelsPage ? 14 : 22,
                      bottom: popoverBottom,
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.escape):
                              _closePicker,
                        },
                        child: Focus(
                          autofocus: true,
                          child: SizedBox(
                            width: math.min(
                              modelsPage ? 352 : 300,
                              bounds.maxWidth - (modelsPage ? 28 : 44),
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: math.max(
                                  100,
                                  bounds.maxHeight -
                                      popoverBottom -
                                      navigationTop -
                                      20,
                                ),
                              ),
                              child: MobileModelPicker(
                                controller: chat,
                                modelsPage: modelsPage,
                                hasImages: hasImages,
                                onPageChanged: (value) =>
                                    setState(() => modelsPage = value),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!history && !picker)
                    Positioned(
                      left: 0,
                      top: navigationTop + 52,
                      bottom: bottom + composerHeight,
                      width: 20,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) > 100) {
                            _openHistory();
                          }
                        },
                      ),
                    ),
                  if (history) ...[
                    Positioned.fill(
                      child: GestureDetector(
                        key: const ValueKey('history-scrim'),
                        onTap: () => setState(() => history = false),
                        child: Semantics(
                          label: tr(context, 'closeHistory'),
                          button: true,
                          child: const ColoredBox(color: Color(0x2e000000)),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      bottom: 8,
                      left: 8,
                      width: math.min(318, bounds.maxWidth - 34),
                      child: GestureDetector(
                        onHorizontalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) < -100) {
                            setState(() => history = false);
                          }
                        },
                        child: MobileHistory(
                          controller: chat,
                          onNew: _new,
                          onSelected: () => setState(() => history = false),
                          onClose: () => setState(() => history = false),
                          onLogout: widget.onLogout,
                          onDelete: widget.onDelete,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _navigation(BuildContext context, bool empty) {
    final p = MobilePalette.of(context);
    final active = chat.current?.active == true;
    final status = chat.current?.status;
    final label = tr(
      context,
      active
          ? 'running'
          : status == 'completed'
          ? 'completed'
          : ['failed', 'cancelled'].contains(status)
          ? 'interrupted'
          : 'cloudConversation',
    );
    final steps = chat.current?.run?['steps'];
    final detail = steps is int && steps > 0
        ? '$label · ${tr(context, active ? 'runningStep' : 'stepCount').replaceAll('{count}', '$steps')}'
        : label;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          MobileIconButton(
            label: tr(context, 'backToHistory'),
            icon: Icons.view_sidebar_outlined,
            glass: true,
            color: p.ink,
            onPressed: _openHistory,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: empty
                ? const SizedBox()
                : GestureDetector(
                    onLongPress: chat.current?.active == true || locked
                        ? null
                        : widget.onDelete,
                    child: MobileGlass(
                      radius: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        height: 44,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              chat.current?.title.isNotEmpty == true
                                  ? chat.current!.title
                                  : tr(context, 'new'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: active
                                        ? p.accent
                                        : status == 'completed'
                                        ? p.green
                                        : p.muted,
                                    boxShadow: active
                                        ? [
                                            BoxShadow(
                                              color: p.accent.withValues(
                                                alpha: .22,
                                              ),
                                              spreadRadius: 3,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    detail,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: p.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          MobileIconButton(
            label: tr(context, 'new'),
            icon: Icons.edit_square,
            glass: true,
            color: empty ? p.muted : p.ink,
            onPressed: locked || widget.recording ? null : _new,
          ),
        ],
      ),
    );
  }

  Widget _empty(
    BuildContext context,
    double height,
    double navigationTop,
    double composerBottom,
  ) {
    final p = MobilePalette.of(context);
    final scaled = MediaQuery.textScalerOf(context).scale(1);
    final compact = height < 650 || scaled > 1.35;
    final center = Opacity(
      opacity: picker ? .55 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConversationOrb(listening: widget.recording),
          if (!picker || !modelsPage) ...[
            const SizedBox(height: 18),
            Text(
              tr(context, 'mobileWelcome'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 25,
                letterSpacing: -.25,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
            ),
          ],
          if (!picker) ...[
            const SizedBox(height: 8),
            Text(
              tr(context, 'mobileSubtitle'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.5, color: p.secondary),
            ),
          ],
        ],
      ),
    );
    final suggestions = SizedBox(
      height: 110 + 36 * (math.max(1, scaled) - 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 20, right: 12),
        children: [
          _suggestion(
            context,
            Icons.image_outlined,
            'suggestImage',
            'suggestImageHint',
            () => unawaited(_attach()),
          ),
          _suggestion(
            context,
            Icons.translate,
            'suggestTranslate',
            'suggestTranslateHint',
            () => _suggest('translateDraft'),
          ),
          _suggestion(
            context,
            Icons.language,
            'suggestWeb',
            'suggestWebHint',
            () => _suggest('webDraft'),
          ),
        ],
      ),
    );
    if (compact) {
      return Padding(
        padding: EdgeInsets.only(
          top: navigationTop + 60,
          bottom: composerBottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: center,
              ),
              const SizedBox(height: 20),
              suggestions,
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        Positioned(
          top: (picker ? 214 : 236) + (height - 852) * .35,
          left: 20,
          right: 20,
          child: center,
        ),
        if (!picker)
          Positioned(
            left: 0,
            right: 0,
            bottom: math.max(164, composerBottom + 36),
            child: suggestions,
          ),
      ],
    );
  }

  void _suggest(String key) {
    widget.composer.text = tr(context, key);
    draftFocus.requestFocus();
  }

  Widget _suggestion(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) {
    final p = MobilePalette.of(context);
    return Container(
      width: 168,
      margin: const EdgeInsets.only(right: 10, bottom: 4),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line, width: .5),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: locked ? null : action,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: DesignIcon(icon, size: 15, color: p.accent),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr(context, title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tr(context, subtitle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  color: p.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _attach() async {
    await widget.onAttach();
    if (mounted && incompatibleImage) {
      setState(() {
        picker = true;
        modelsPage = true;
      });
    }
  }

  Widget _composer(BuildContext context) {
    final p = MobilePalette.of(context), active = chat.current?.active == true;
    final model = chat.selectedModel;
    final effort = chat.reasoningEffort;
    final top = model?.isHighestEffort(effort) == true;
    final stop = active;
    final canSend =
        !locked &&
        !incompatibleImage &&
        (widget.composer.text.trim().isNotEmpty ||
            widget.attachments.isNotEmpty);
    return MobileGlass(
      key: composerKey,
      radius: 26,
      // The 44pt targets add 5pt around the 34pt artwork.
      padding: const EdgeInsets.fromLTRB(10, 13, 10, 5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 73),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                child: SizedBox(
                  height: 54,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final attachment in widget.attachments)
                        _attachmentThumb(context, attachment),
                    ],
                  ),
                ),
              ),
            if ((widget.recording || widget.voiceFailed) &&
                widget.voicePartial?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      widget.voicePartial!,
                      maxLines: 3,
                      style: TextStyle(fontSize: 14, color: p.secondary),
                    ),
                    if (widget.voiceFailed)
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: widget.voicePartial!),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tr(context, 'copied'))),
                            );
                          }
                        },
                        icon: DesignIcon(
                          Icons.copy_outlined,
                          size: 14,
                          color: p.accent,
                        ),
                        label: Text(tr(context, 'copyRecoveredDictation')),
                      ),
                  ],
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 29.4),
              child: TextField(
                key: const ValueKey('message-draft'),
                controller: widget.composer,
                focusNode: draftFocus,
                minLines: 1,
                maxLines: 4,
                enabled: !locked && !widget.recording,
                style: TextStyle(fontSize: 16, height: 1.4, color: p.ink),
                decoration: InputDecoration(
                  hintText: tr(
                    context,
                    (chat.current?.messages.isEmpty ?? true)
                        ? 'askPlaceholder'
                        : 'followupPlaceholder',
                  ),
                  hintStyle: TextStyle(color: p.muted),
                  contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 7),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
            ),
            if (incompatibleImage)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  tr(context, 'visionUnavailable'),
                  style: TextStyle(fontSize: 11, color: p.secondary),
                ),
              ),
            Row(
              children: [
                MobileIconButton(
                  label: tr(context, 'attach'),
                  icon: Icons.add,
                  onPressed: locked || widget.picking || widget.recording
                      ? null
                      : () => unawaited(_attach()),
                ),
                Expanded(
                  child: Focus(
                    focusNode: pickerFocus,
                    child: Semantics(
                      label: tr(context, 'modelAndReasoning'),
                      expanded: picker,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          key: const ValueKey('model-trigger'),
                          borderRadius: BorderRadius.circular(17),
                          onTap: locked || active || widget.recording
                              ? null
                              : () => setState(() {
                                  picker = !picker;
                                  modelsPage = false;
                                }),
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: picker ? p.hover : null,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    model?.name ?? tr(context, 'default'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: locked || active ? p.muted : p.ink,
                                    ),
                                  ),
                                ),
                                if (effort.isNotEmpty) ...[
                                  const SizedBox(width: 5),
                                  Text(
                                    tr(context, 'effort_$effort'),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: top ? p.purple : p.secondary,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 5),
                                RotatedBox(
                                  quarterTurns: picker ? 2 : 0,
                                  child: DesignIcon(
                                    Icons.keyboard_arrow_down,
                                    size: 11,
                                    color: p.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!active &&
                    (widget.recording ||
                        (widget.composer.text.trim().isEmpty &&
                            widget.attachments.isEmpty)))
                  MobileIconButton(
                    label: tr(
                      context,
                      widget.recording ? 'stopRecording' : 'voiceInput',
                    ),
                    icon: Icons.mic_none,
                    color: widget.recording ? p.accent : p.secondary,
                    onPressed: locked || widget.onVoice == null
                        ? null
                        : () => unawaited(widget.onVoice!()),
                  ),
                Semantics(
                  button: true,
                  label: tr(context, stop ? 'stop' : 'send'),
                  child: Tooltip(
                    message: tr(context, stop ? 'stop' : 'send'),
                    child: InkResponse(
                      key: const ValueKey('send-or-stop'),
                      radius: 22,
                      onTap: stop
                          ? (chat.busy
                                ? null
                                : () => unawaited(chat.runAction('cancel')))
                          : (canSend && !widget.recording
                                ? () {
                                    setState(() => picker = false);
                                    unawaited(widget.onSend());
                                  }
                                : null),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: stop
                                  ? p.ink
                                  : canSend && !widget.recording
                                  ? p.accent
                                  : p.fill2,
                              boxShadow: canSend && !stop
                                  ? [
                                      BoxShadow(
                                        color: p.accent.withValues(alpha: .4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: stop
                                  ? Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: p.bg,
                                        borderRadius: BorderRadius.circular(
                                          2.5,
                                        ),
                                      ),
                                    )
                                  : DesignIcon(
                                      Icons.arrow_upward_rounded,
                                      size: 15,
                                      color: canSend ? Colors.white : p.muted,
                                    ),
                            ),
                          ),
                        ),
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

  Widget _attachmentThumb(
    BuildContext context,
    Map<String, dynamic> attachment,
  ) {
    final p = MobilePalette.of(context);
    final data = attachment['image'];
    Widget preview = Center(
      child: DesignIcon(
        attachment['kind'] == 'image'
            ? Icons.image_outlined
            : Icons.description_outlined,
        color: p.secondary,
        size: 22,
      ),
    );
    if (data is String &&
        data.startsWith('data:image/') &&
        data.length < 3000000) {
      try {
        preview = Image.memory(
          base64Decode(data.substring(data.indexOf(',') + 1)),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Icon(Icons.image_outlined, color: p.secondary),
        );
      } on FormatException {
        /* Keep the attachment name available. */
      }
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: attachment['name'] as String? ?? '',
        child: SizedBox.square(
          dimension: 54,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(color: p.fill2, child: preview),
                ),
              ),
              Positioned(
                top: -9,
                right: -9,
                child: SizedBox.square(
                  dimension: 44,
                  child: IconButton(
                    tooltip: tr(context, 'removeAttachment'),
                    padding: EdgeInsets.zero,
                    onPressed: locked
                        ? null
                        : () => widget.onRemove(attachment),
                    icon: Container(
                      width: 17,
                      height: 17,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x8c000000),
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 12,
                        color: Colors.white,
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

  Widget _notice(String text, {VoidCallback? action}) {
    final p = MobilePalette.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.tool,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: p.secondary),
            ),
          ),
          if (action != null)
            TextButton(onPressed: action, child: Text(tr(context, 'retry'))),
        ],
      ),
    );
  }
}
