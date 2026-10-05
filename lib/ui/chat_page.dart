import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../chat/attachments.dart';
import '../chat/chat_controller.dart';
import '../core/preferences.dart';
import '../voice/voice_controller.dart';
import '../voice/windows_bridge.dart';
import 'strings.dart';
import 'mobile_chat.dart';
import 'mobile_design.dart';
import 'mobile_transcript.dart';
import 'conversation_orb.dart';
import 'settings_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.controller,
    required this.onLogout,
    this.voiceController,
    this.windowsBridge,
  });
  final ChatController controller;
  final Future<void> Function() onLogout;
  final VoiceController? voiceController;
  final WindowsBridge? windowsBridge;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final composer = TextEditingController(), scroll = ScrollController();
  late final bridge = widget.windowsBridge ?? WindowsBridge();
  late final voice =
      widget.voiceController ?? VoiceController(widget.controller.api);
  final attachments = <Map<String, dynamic>>[];
  bool hotkey = false, desktopRecording = false, picking = false;
  String? uiError;
  String? _conversationId;
  String? _recordingConversationId;
  int _voiceOperation = 0;
  String _historyQuery = '';
  bool _sidebarVisible = true;
  ChatController get chat => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conversationId = chat.current?.id;
    chat.addListener(_changed);
    voice.addListener(_voiceChanged);
  }

  void _changed() {
    final follow = !scroll.hasClients || scroll.position.extentAfter < 100;
    if (_conversationId != chat.current?.id) {
      if (voice.active && !desktopRecording) {
        _voiceOperation++;
        unawaited(voice.cancel());
      }
      _conversationId = chat.current?.id;
      composer.clear();
      attachments.clear();
    }
    if (mounted) setState(() {});
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _voiceChanged() {
    if (mounted) {
      setState(() {});
      if (desktopRecording) {
        final key = switch (voice.phase) {
          VoicePhase.starting => 'starting',
          VoicePhase.recording => 'recording',
          VoicePhase.finishing => 'finishing',
          _ => '',
        };
        unawaited(
          bridge
              .showStatus(key.isEmpty ? '' : tr(context, key))
              .catchError((Object _) {}),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Desktop windows remain useful while another application has focus.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!bridge.available) {
        chat.setForeground(false);
        if (voice.active) {
          _voiceOperation++;
          voice.error = 'ASR_INTERRUPTED';
          unawaited(voice.cancel(failed: true));
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      chat.setForeground(true);
    }
  }

  @override
  void dispose() {
    _voiceOperation++;
    WidgetsBinding.instance.removeObserver(this);
    chat.removeListener(_changed);
    voice.removeListener(_voiceChanged);
    voice.dispose();
    unawaited(bridge.disable());
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> toggleHotkey() async {
    try {
      if (hotkey) {
        await bridge.disable();
      } else {
        await bridge.enable(() => toggleVoice(desktop: true));
      }
      if (mounted) setState(() => hotkey = !hotkey);
    } catch (_) {
      if (mounted) setState(() => uiError = 'HOTKEY_UNAVAILABLE');
    }
  }

  Future<void> toggleVoice({bool desktop = false}) async {
    if (voice.phase == VoicePhase.recording) {
      if (desktop != desktopRecording) return;
      final operation = _voiceOperation;
      final text = await voice.stop();
      if (!mounted ||
          operation != _voiceOperation ||
          text == null ||
          text.isEmpty ||
          (!desktopRecording && _recordingConversationId != chat.current?.id)) {
        await bridge.reset();
        desktopRecording = false;
        return;
      }
      var inserted = false;
      if (desktopRecording) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!mounted || operation != _voiceOperation || !desktopRecording) {
          return;
        }
        try {
          inserted = await bridge.insert(text);
        } catch (_) {
          inserted = false;
        }
      }
      if (!mounted) return;
      if (!inserted) {
        composer.text += text;
        composer.selection = TextSelection.collapsed(
          offset: composer.text.length,
        );
        if (desktopRecording) setState(() => uiError = 'insertFailed');
      }
      desktopRecording = false;
    } else if (!voice.active) {
      if (chat.busy || chat.pending != null || chat.current?.active == true) {
        return;
      }
      if (mounted) setState(() => uiError = null);
      _voiceOperation++;
      desktopRecording = desktop;
      _recordingConversationId = chat.current?.id;
      await voice.start(scenario: desktop ? 'voice-input' : 'ask-anything');
      if (!voice.active) {
        await bridge.reset();
        desktopRecording = false;
      }
    }
  }

  Future<void> shareReply(String text) async {
    if (text.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => uiError = 'shareFailed');
    }
  }

  Future<void> attach() async {
    if (picking || chat.busy || chat.pending != null) return;
    final attachingTo = chat.current?.id;
    setState(() {
      picking = true;
      uiError = null;
    });
    try {
      final chosen = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'txt',
          'md',
          'csv',
          'json',
          'log',
        ],
        withData: true,
      );
      if (chosen == null || !mounted || chat.current?.id != attachingTo) return;
      final file = chosen.files.single;
      if (file.size > 20 * 1024 * 1024 ||
          file.bytes == null ||
          attachments.length >= 10) {
        throw const FormatException('ATTACHMENT_TOO_LARGE');
      }
      final prepared = await compute(prepareAttachment, {
        'name': file.name,
        'bytes': file.bytes!,
      });
      if (!mounted || chat.current?.id != attachingTo) return;
      if (prepared['kind'] == 'image') {
        if (attachments.where((a) => a['kind'] == 'image').length >= 8) {
          throw const FormatException('ATTACHMENT_TOO_LARGE');
        }
      }
      final payload = [...attachments, prepared].fold<int>(
        0,
        (sum, a) =>
            sum +
            (a['image'] as String? ?? '').length +
            (a['text'] as String? ?? '').length * 4,
      );
      if (payload > 4000000) {
        throw const FormatException('ATTACHMENT_TOO_LARGE');
      }
      setState(() => attachments.add(prepared));
    } catch (e) {
      if (mounted) {
        setState(
          () => uiError = e is FormatException ? e.message : 'requestFailed',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> send() async {
    if (attachments.any((a) => a['kind'] == 'image') &&
        chat.selectedModel?.vision != true) {
      setState(() => uiError = 'visionUnavailable');
      return;
    }
    final text = composer.text;
    final accepted = await chat.send(text, List.of(attachments));
    if (mounted && accepted) {
      setState(() {
        composer.clear();
        attachments.clear();
      });
    }
  }

  Future<void> delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'delete')),
        content: Text(tr(context, 'deleteConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'delete')),
          ),
        ],
      ),
    );
    if (yes == true) await chat.deleteCurrent();
  }

  Future<void> logout() async {
    _voiceOperation++;
    desktopRecording = false;
    await bridge.disable();
    await voice.cancel();
    await widget.onLogout();
  }

  Widget sidebar() {
    final p = MobilePalette.of(context);
    final query = _historyQuery.trim().toLowerCase();
    final items = chat.conversations
        .where(
          (item) =>
              (item['title'] as String? ?? '').toLowerCase().contains(query),
        )
        .toList();
    return SizedBox(
      width: 264,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
        child: MobileGlass(
          radius: 20,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(context, 'ask'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr(context, 'new'),
                      iconSize: 18,
                      onPressed:
                          chat.busy || chat.pending != null || voice.active
                          ? null
                          : chat.newConversation,
                      icon: const Icon(Icons.edit_square),
                    ),
                    IconButton(
                      tooltip: tr(context, 'history'),
                      iconSize: 18,
                      onPressed: () => setState(() => _sidebarVisible = false),
                      icon: const Icon(Icons.view_sidebar_outlined),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    onChanged: (value) => setState(() => _historyQuery = value),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: tr(context, 'searchConversations'),
                      prefixIcon: Icon(Icons.search, size: 17, color: p.muted),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      filled: true,
                      fillColor: p.hover,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            tr(
                              context,
                              query.isEmpty ? 'noConversations' : 'noMatches',
                            ),
                            style: TextStyle(fontSize: 12, color: p.secondary),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: items.length + (chat.hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == items.length) {
                            return TextButton(
                              onPressed: chat.loading ? null : chat.loadMore,
                              child: Text(tr(context, 'more')),
                            );
                          }
                          final item = items[index];
                          final selected = chat.current?.id == item['id'];
                          final date = DateTime.tryParse(
                            item['updated_at'] as String? ?? '',
                          )?.toLocal();
                          final today = DateTime.now();
                          final time = date == null
                              ? ''
                              : date.year == today.year &&
                                    date.month == today.month &&
                                    date.day == today.day
                              ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                              : '${date.month}/${date.day}';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Material(
                              color: selected
                                  ? p.accent.withValues(alpha: .12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap:
                                    chat.busy ||
                                        chat.pending != null ||
                                        voice.active
                                    ? null
                                    : () => unawaited(
                                        chat.select(item['id'] as String),
                                      ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 13,
                                  ),
                                  child: Row(
                                    children: [
                                      if (selected &&
                                          chat.current?.active == true) ...[
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            color: p.accent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Expanded(
                                        child: Text(
                                          item['title'] as String? ??
                                              tr(context, 'new'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: p.ink,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        time,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: p.secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (bridge.available)
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(
                      tr(context, 'hotkey'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: hotkey,
                    onChanged: voice.active ? null : (_) => toggleHotkey(),
                  ),
                ),
              Divider(height: 1, color: p.line),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chat.accountName?.isNotEmpty == true
                            ? chat.accountName!
                            : chat.accountEmail?.isNotEmpty == true
                            ? chat.accountEmail!
                            : tr(context, 'account'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: p.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr(context, 'accountSettings'),
                      onPressed: () {
                        final preferences = PreferencesScope.maybeOf(context);
                        unawaited(
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => SettingsPage(
                                controller: chat,
                                onLogout: logout,
                                preferences: preferences,
                              ),
                            ),
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.settings_outlined,
                        size: 17,
                        color: p.secondary,
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
  }

  Widget desktopHeader() {
    final p = MobilePalette.of(context);
    final current = chat.current;
    final existing = current != null && current.revision > 0;
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            if (!_sidebarVisible) ...[
              MobileIconButton(
                label: tr(context, 'history'),
                icon: Icons.view_sidebar_outlined,
                onPressed: () => setState(() => _sidebarVisible = true),
                glass: true,
              ),
              const SizedBox(width: 8),
              MobileIconButton(
                label: tr(context, 'new'),
                icon: Icons.edit_square,
                onPressed: chat.busy || chat.pending != null || voice.active
                    ? null
                    : chat.newConversation,
                glass: true,
              ),
              const SizedBox(width: 8),
            ],
            if (existing)
              Flexible(
                child: MobileGlass(
                  radius: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          current.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
                      ),
                      if (current.run != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: current.active
                                ? p.accent
                                : current.status == 'completed'
                                ? p.green
                                : p.muted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          tr(
                            context,
                            current.active
                                ? 'running'
                                : current.status == 'completed'
                                ? 'completed'
                                : 'interrupted',
                          ),
                          style: TextStyle(fontSize: 11, color: p.secondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const Spacer(),
            if (existing)
              MobileIconButton(
                label: tr(context, 'delete'),
                icon: Icons.delete_outline,
                onPressed: current.active || chat.busy || chat.pending != null
                    ? null
                    : delete,
                glass: true,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final platform = Theme.of(context).platform;
      final mobile =
          platform == TargetPlatform.iOS || platform == TargetPlatform.android;
      final wide = !mobile && size.maxWidth >= 800;
      if (!wide) {
        return MobileChat(
          controller: chat,
          composer: composer,
          scrollController: scroll,
          attachments: attachments,
          onAttach: attach,
          onSend: send,
          onLogout: logout,
          onDelete: delete,
          onRemove: (item) => setState(() => attachments.remove(item)),
          picking: picking,
          error: uiError ?? voice.error,
          onVoice:
              voice.phase == VoicePhase.starting ||
                  voice.phase == VoicePhase.finishing
              ? null
              : toggleVoice,
          recording: voice.active,
          voiceFailed: voice.phase == VoicePhase.failed,
          voicePartial: voice.phase == VoicePhase.starting
              ? tr(context, 'starting')
              : voice.phase == VoicePhase.finishing
              ? tr(context, 'finishing')
              : voice.transcript.text,
          onShare: shareReply,
          onRetry: () {
            final localFailure = uiError != null || voice.error != null;
            setState(() {
              uiError = null;
              voice.error = null;
            });
            if (!localFailure) unawaited(chat.initialize());
          },
        );
      }
      return Scaffold(
        backgroundColor: MobilePalette.of(context).bg,
        body: SafeArea(
          child: Row(
            children: [
              if (_sidebarVisible) sidebar(),
              Expanded(
                child: Column(
                  children: [
                    desktopHeader(),
                    if (chat.loading || chat.busy)
                      const LinearProgressIndicator(minHeight: 2),
                    if (chat.reconnecting) banner(tr(context, 'reconnecting')),
                    if (chat.error != null || uiError != null)
                      banner(
                        friendlyError(context, uiError ?? chat.error!),
                        action: chat.pending == null
                            ? () {
                                setState(() => uiError = null);
                                unawaited(chat.initialize());
                              }
                            : null,
                      ),
                    if (chat.pending != null)
                      banner(
                        tr(context, 'pending'),
                        action: chat.busy ? null : chat.retryPending,
                      ),
                    if (chat.current?.needsDevice == true)
                      banner(tr(context, 'deviceNeeded')),
                    if (hotkey)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Text(
                          tr(context, 'hotkeyOn'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Expanded(child: messages()),
                    if (chat.pending != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          chat.pending!['request']['text'] as String? ?? '',
                          maxLines: 3,
                        ),
                      ),
                    composerView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget banner(String text, {VoidCallback? action}) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.secondaryContainer
        .withValues(alpha: .45),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(text)),
        if (action != null)
          TextButton(onPressed: action, child: Text(tr(context, 'retry'))),
      ],
    ),
  );
  Widget messages() {
    final item = chat.current;
    final p = MobilePalette.of(context);
    if ((item?.messages.isEmpty ?? true) && item?.active != true) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (constraints.maxHeight > 280) const ConversationOrb(),
                    const SizedBox(height: 20),
                    Text(
                      tr(context, 'mobileWelcome'),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      tr(context, 'subtitle'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: p.secondary),
                    ),
                    const SizedBox(height: 26),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: desktopSuggestion(
                              Icons.photo_outlined,
                              'suggestImage',
                              'suggestImageHint',
                              attach,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: desktopSuggestion(
                              Icons.translate,
                              'suggestTranslate',
                              'suggestTranslateHint',
                              () {
                                composer.text = tr(context, 'translateDraft');
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: desktopSuggestion(
                              Icons.language,
                              'suggestWeb',
                              'suggestWebHint',
                              () {
                                composer.text = tr(context, 'webDraft');
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: MobileTranscript(
          controller: chat,
          scrollController: scroll,
          onShare: shareReply,
          onQuote: (text) {
            composer.text = '> ${text.replaceAll('\n', '\n> ')}\n\n';
            composer.selection = TextSelection.collapsed(
              offset: composer.text.length,
            );
            setState(() {});
          },
        ),
      ),
    );
  }

  Widget desktopSuggestion(
    IconData icon,
    String title,
    String caption,
    VoidCallback action,
  ) {
    final p = MobilePalette.of(context);
    return Material(
      color: p.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: chat.busy || chat.pending != null ? null : action,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: p.accent),
              ),
              const SizedBox(height: 9),
              Text(
                tr(context, title),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(context, caption),
                style: TextStyle(fontSize: 11, color: p.secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget composerView() => Align(
    alignment: Alignment.bottomCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 804),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
        child: MobileGlass(
          radius: 27,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (voice.active || voice.phase == VoicePhase.failed)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        voice.error != null
                            ? friendlyError(context, voice.error!)
                            : tr(
                                context,
                                voice.phase == VoicePhase.starting
                                    ? 'starting'
                                    : voice.phase == VoicePhase.finishing
                                    ? 'finishing'
                                    : 'recording',
                              ),
                      ),
                      if (voice.transcript.text.isNotEmpty)
                        SelectableText(voice.transcript.text, maxLines: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (voice.transcript.text.isNotEmpty)
                            TextButton(
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: voice.transcript.text),
                              ),
                              child: Text(tr(context, 'copy')),
                            ),
                          TextButton(
                            onPressed: () async {
                              await voice.cancel();
                              await bridge.reset();
                              desktopRecording = false;
                            },
                            child: Text(tr(context, 'cancel')),
                          ),
                          if (voice.phase == VoicePhase.recording)
                            FilledButton(
                              onPressed: () =>
                                  toggleVoice(desktop: desktopRecording),
                              child: Text(tr(context, 'finish')),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (attachments.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final item in attachments)
                        InputChip(
                          label: Text(item['name'] as String),
                          onDeleted: chat.busy
                              ? null
                              : () => setState(() => attachments.remove(item)),
                        ),
                    ],
                  ),
                ),
              TextField(
                key: const ValueKey('desktop-composer'),
                controller: composer,
                enabled: !chat.busy && chat.pending == null,
                minLines: 1,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: tr(
                    context,
                    chat.current?.messages.isNotEmpty == true
                        ? 'followupPlaceholder'
                        : 'askPlaceholder',
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: MobilePalette.of(context).ink,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: tr(context, 'attach'),
                    onPressed: picking || chat.busy || chat.pending != null
                        ? null
                        : attach,
                    icon: const Icon(Icons.add, size: 20),
                  ),
                  IconButton(
                    tooltip: tr(context, 'record'),
                    onPressed: voice.active || chat.busy ? null : toggleVoice,
                    icon: const Icon(Icons.mic_none, size: 20),
                  ),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: MobilePalette.of(context).ink,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        iconSize: 16,
                        value: chat.selectedModel?.reference,
                        hint: Text(tr(context, 'default')),
                        items: [
                          for (final model in chat.modelOptions)
                            DropdownMenuItem(
                              value: model.reference,
                              child: Text(
                                model.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged:
                            chat.current?.active == true ||
                                chat.busy ||
                                attachments.isNotEmpty
                            ? null
                            : (value) => chat.changeModel(value ?? ''),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (chat.current?.active == true)
                    IconButton.filled(
                      tooltip: tr(context, 'stop'),
                      onPressed: chat.busy
                          ? null
                          : () => chat.runAction('cancel'),
                      icon: const Icon(Icons.stop),
                    )
                  else
                    IconButton.filled(
                      tooltip: tr(context, 'send'),
                      onPressed:
                          chat.busy ||
                              chat.loading ||
                              chat.pending != null ||
                              voice.active ||
                              (composer.text.trim().isEmpty &&
                                  attachments.isEmpty)
                          ? null
                          : send,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
