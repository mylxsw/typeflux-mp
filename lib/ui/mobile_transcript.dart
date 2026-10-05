import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../chat/chat_controller.dart';
import '../chat/conversation.dart';
import 'message_details.dart';
import 'mobile_design.dart';
import 'strings.dart';

/// Mobile reading layout from the approved v4 design.
class MobileTranscript extends StatelessWidget {
  const MobileTranscript({
    super.key,
    required this.controller,
    required this.scrollController,
    this.onQuote,
    this.onShare,
    this.bottomPadding = 20,
  });

  final ChatController controller;
  final ScrollController scrollController;
  final ValueChanged<String>? onQuote;
  final Future<void> Function(String text)? onShare;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final conversation = controller.current;
    if (conversation == null) return const SizedBox();
    final entries = transcriptEntries(
      conversation,
      queued: controller.queuedMessages,
    );
    final assistantMessages = conversation.messages.where(
      (m) => m['role'] == 'assistant',
    );
    final latestId = assistantMessages.lastOrNull?['id'];
    final palette = MobilePalette.of(context);
    return SelectionArea(
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(22, 4, 22, bottomPadding),
        children: [
          for (final entry in entries)
            if (entry.isActivity)
              _ToolActivity(
                key: ValueKey('tools:${entry.activity.first['id']}'),
                messages: entry.activity,
                conversation: conversation,
              )
            else if (entry.message!['role'] == 'user')
              _UserMessage(
                message: entry.message!,
                onRetryQueued:
                    entry.message!['queued'] == true &&
                        entry.message!['local_only'] != true &&
                        !conversation.active &&
                        !controller.busy &&
                        !controller.loading &&
                        controller.pending == null
                    ? () => controller.retryQueuedMessage(
                        entry.message!['id'] as String,
                      )
                    : null,
              )
            else
              _AssistantMessage(
                key: ValueKey(entry.message!['id']),
                message: entry.message!,
                conversation: conversation,
                controller: controller,
                onShare: onShare,
                canRegenerate:
                    entry.message!['id'] == latestId &&
                    conversation.run != null &&
                    !conversation.active &&
                    !controller.busy &&
                    controller.pending == null,
              ),
          if (conversation.active &&
              conversation.preview.isEmpty &&
              messageString(conversation.run?['reasoning']).isEmpty &&
              messageMaps(conversation.run?['preview_tools']).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                tr(context, 'answering'),
                style: TextStyle(fontSize: 13, color: palette.secondary),
              ),
            ),
          if (conversation.needsDevice)
            _RunNotice(text: tr(context, 'deviceNeeded')),
          if (conversation.status == 'failed' ||
              conversation.status == 'cancelled')
            _RunNotice(text: tr(context, 'failedRun')),
        ],
      ),
    );
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.message, this.onRetryQueued});
  final Map<String, dynamic> message;
  final VoidCallback? onRetryQueued;

  @override
  Widget build(BuildContext context) {
    final palette = MobilePalette.of(context);
    final text = messageString(message['text']);
    final attachments = messageMaps(message['attachments']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (messageString(message['image']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: 176,
                child: _AttachmentPreview(
                  attachment: {'kind': 'image', 'image': message['image']},
                  height: 132,
                ),
              ),
            ),
          for (final attachment in attachments.where(
            (a) => a['kind'] == 'image',
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: 176,
                child: _AttachmentPreview(attachment: attachment, height: 132),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .8,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.bubble,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (text.isNotEmpty)
                            Text(
                              text,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                color: palette.bubbleInk,
                              ),
                            ),
                          for (final attachment in attachments.where(
                            (a) => a['kind'] != 'image',
                          ))
                            _AttachmentPreview(attachment: attachment),
                          if (message['queued'] == true)
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  tr(
                                    context,
                                    message['local_only'] == true
                                        ? 'localQueued'
                                        : 'queued',
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.secondary,
                                  ),
                                ),
                                if (message['local_only'] == true)
                                  TextButton(
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: text),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  tr(context, 'copied'),
                                                ),
                                              ),
                                            );
                                      }
                                    },
                                    child: Text(tr(context, 'copy')),
                                  ),
                                if (onRetryQueued != null)
                                  TextButton(
                                    onPressed: onRetryQueued,
                                    child: Text(tr(context, 'resumeQueued')),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment, this.height = 140});
  final Map<String, dynamic> attachment;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = MobilePalette.of(context);
    final name = messageString(attachment['name']);
    final data = messageString(attachment['image']);
    Widget? image;
    if (data.startsWith('data:image/') && data.length < 3000000) {
      try {
        final bytes = UriData.parse(data).contentAsBytes();
        image = Image.memory(
          bytes,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          semanticLabel: name.isEmpty ? tr(context, 'attachment') : name,
          errorBuilder: (_, _, _) => const SizedBox(),
        );
      } on FormatException {
        // The filename remains available if a historical image is malformed.
      }
    }
    return Padding(
      padding: EdgeInsets.only(top: height == 132 ? 0 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null)
            ClipRRect(borderRadius: BorderRadius.circular(18), child: image),
          if (image == null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.attach_file_rounded,
                  size: 14,
                  color: palette.secondary,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    name.isEmpty ? tr(context, 'attachment') : name,
                    style: TextStyle(fontSize: 11, color: palette.secondary),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({
    super.key,
    required this.message,
    required this.conversation,
    required this.controller,
    this.onShare,
    required this.canRegenerate,
  });
  final Map<String, dynamic> message;
  final Conversation conversation;
  final ChatController controller;
  final Future<void> Function(String text)? onShare;
  final bool canRegenerate;

  @override
  Widget build(BuildContext context) {
    final text = messageString(message['text']);
    final preview = message['preview'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (messageString(message['reasoning']).isNotEmpty)
            _Reasoning(message: message, active: preview),
          if (text.isNotEmpty) _Prose(text: text, streaming: preview),
          if (!preview && text.isNotEmpty)
            Transform.translate(
              offset: const Offset(-8, -4),
              child: Row(
                children: [
                  _Action(
                    label: tr(context, 'copy'),
                    icon: Icons.copy_outlined,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr(context, 'copied'))),
                        );
                      }
                    },
                  ),
                  if (canRegenerate)
                    _Action(
                      label: tr(context, 'regenerate'),
                      icon: Icons.refresh_rounded,
                      onPressed: () => controller.runAction('regenerate'),
                    ),
                  _Action(
                    label: tr(context, 'share'),
                    icon: Icons.ios_share,
                    onPressed: onShare == null ? null : () => onShare!(text),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Prose extends StatelessWidget {
  const _Prose({required this.text, this.streaming = false});
  final String text;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final palette = MobilePalette.of(context);
    return MarkdownBody(
      data: streaming ? '$text \uE000' : text,
      blockSyntaxes: const [_MobileTableSyntax()],
      inlineSyntaxes: [
        _CitationSyntax(),
        if (streaming) _StreamingCaretSyntax(),
      ],
      builders: {
        'stream-caret': _StreamingCaretBuilder(),
        'pre': _CodeBlockBuilder(),
        'citation': _CitationBuilder(),
        'mobile-table': _MobileTableBuilder(),
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          fontSize: 16,
          height: 1.62,
          letterSpacing: .08,
          color: palette.ink,
        ),
        a: TextStyle(color: palette.accent),
        h1: TextStyle(
          fontSize: 22,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: palette.ink,
        ),
        h2: TextStyle(
          fontSize: 19,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: palette.ink,
        ),
        h3: TextStyle(
          fontSize: 17,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: palette.ink,
        ),
        h4: TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: palette.ink,
        ),
        strong: const TextStyle(fontWeight: FontWeight.w600),
        blockSpacing: 10,
        listIndent: 20,
        listBullet: TextStyle(fontSize: 16, height: 1.62, color: palette.muted),
        code: TextStyle(
          fontSize: 13.5,
          fontFamily: 'monospace',
          fontFamilyFallback: [
            ?Theme.of(context).textTheme.bodyMedium?.fontFamily,
            ...?Theme.of(context).textTheme.bodyMedium?.fontFamilyFallback,
          ],
          color: palette.ink,
          backgroundColor: palette.fill,
        ),
        codeblockDecoration: BoxDecoration(
          color: palette.code,
          border: Border.all(color: palette.line, width: .5),
          borderRadius: BorderRadius.circular(14),
        ),
        codeblockPadding: EdgeInsets.zero,
        blockquote: TextStyle(
          fontSize: 13,
          height: 1.65,
          color: palette.secondary,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: palette.line, width: 2)),
        ),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableBorder: TableBorder(
          top: BorderSide(color: palette.line, width: .5),
          bottom: BorderSide(color: palette.line, width: .5),
          left: BorderSide(color: palette.line, width: .5),
          right: BorderSide(color: palette.line, width: .5),
          horizontalInside: BorderSide(color: palette.line, width: .5),
          borderRadius: BorderRadius.circular(14),
        ),
        tableHead: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: palette.secondary,
        ),
        tableBody: TextStyle(fontSize: 13.5, height: 1.5, color: palette.ink),
        tableCellsDecoration: BoxDecoration(color: palette.surface),
        tableHeadCellsDecoration: BoxDecoration(
          color: Color.alphaBlend(palette.fill, palette.surface),
        ),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        tableHeadAlign: TextAlign.left,
      ),
      onTapLink: (_, href, _) => _openWebLink(context, href),
      imageBuilder: (uri, title, alt) {
        // Do not read local files or request model-provided image URLs before
        // the user chooses to view them. Uploaded attachment previews are local.
        if (!_isWebUri(uri)) return Text(alt ?? '');
        return _RemoteImage(key: ValueKey(uri), uri: uri, alt: alt);
      },
    );
  }
}

bool _isWebUri(Uri uri) =>
    ['https', 'http'].contains(uri.scheme) &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

Future<void> _openWebLink(BuildContext context, String? href) async {
  final uri = href == null ? null : Uri.tryParse(href);
  if (uri == null || !_isWebUri(uri)) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr(context, 'linkUnsupported'))));
    return;
  }
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } on PlatformException {
    // Platform launch can fail even when a URL has a supported scheme.
  } on MissingPluginException {
    // Desktop plugin loading or unsupported development hosts may fail.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(tr(context, 'linkOpenFailed')),
      action: SnackBarAction(
        label: tr(context, 'copyLink'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: uri.toString()));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(tr(context, 'linkCopied'))));
        },
      ),
    ),
  );
}

class _RemoteImage extends StatefulWidget {
  const _RemoteImage({super.key, required this.uri, this.alt});
  final Uri uri;
  final String? alt;
  @override
  State<_RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<_RemoteImage> {
  bool requested = false;
  @override
  Widget build(BuildContext context) {
    if (!requested) {
      return OutlinedButton.icon(
        onPressed: () => setState(() => requested = true),
        icon: const Icon(Icons.image_outlined, size: 18),
        label: Text(
          widget.alt?.isNotEmpty == true
              ? '${tr(context, 'viewImage')} · ${widget.alt}'
              : tr(context, 'viewImage'),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        widget.uri.toString(),
        fit: BoxFit.contain,
        semanticLabel: widget.alt,
        errorBuilder: (_, _, _) => TextButton(
          onPressed: () async {
            await NetworkImage(widget.uri.toString()).evict();
            if (mounted) setState(() => requested = false);
          },
          child: Text(tr(context, 'imageLoadFailed')),
        ),
      ),
    );
  }
}

class _Reasoning extends StatefulWidget {
  const _Reasoning({required this.message, required this.active});
  final Map<String, dynamic> message;
  final bool active;
  @override
  State<_Reasoning> createState() => _ReasoningState();
}

class _ReasoningState extends State<_Reasoning> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final palette = MobilePalette.of(context);
    final milliseconds = widget.message['reasoning_milliseconds'];
    final label = widget.active
        ? tr(context, 'thinking')
        : milliseconds is num && milliseconds > 0
        ? tr(
            context,
            'thoughtSeconds',
          ).replaceAll('{seconds}', '${(milliseconds / 1000).ceil()}')
        : tr(context, 'thought');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            expanded: expanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => expanded = !expanded),
              child: SizedBox(
                height: 20,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DesignIcon(
                      Icons.auto_awesome_outlined,
                      size: 15,
                      color: widget.active ? palette.accent : palette.muted,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: widget.active
                          ? _ThinkingLabel(text: label)
                          : Text(
                              label,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: palette.secondary,
                              ),
                            ),
                    ),
                    const SizedBox(width: 5),
                    if (!widget.active)
                      DesignIcon(
                        expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.chevron_right,
                        size: 11,
                        color: palette.muted,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Container(
              margin: const EdgeInsets.only(left: 5, bottom: 8),
              padding: const EdgeInsets.only(left: 12, right: 10),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(width: 2, color: palette.line)),
              ),
              child: Text(
                messageString(widget.message['reasoning']),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.65,
                  color: palette.secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolActivity extends StatefulWidget {
  const _ToolActivity({
    super.key,
    required this.messages,
    required this.conversation,
  });
  final List<Map<String, dynamic>> messages;
  final Conversation conversation;
  @override
  State<_ToolActivity> createState() => _ToolActivityState();
}

class _ToolActivityState extends State<_ToolActivity> {
  bool? userExpanded;
  @override
  Widget build(BuildContext context) {
    final palette = MobilePalette.of(context);
    final calls = widget.messages
        .expand((m) => messageMaps(m['tool_calls']))
        .toList();
    final webOnly = calls.every((call) {
      final function = call['function'];
      return function is Map &&
          [
            'web_search',
            'search_web',
            'web_fetch',
            'read_url',
            'fetch_url',
          ].contains(function['name']);
    });
    final run = widget.conversation.run;
    final results = <String, Map<String, dynamic>>{
      for (final message in widget.conversation.messages)
        if (message['role'] == 'tool' && message['tool_call_id'] is String)
          message['tool_call_id'] as String: message,
    };
    final running =
        widget.conversation.active &&
        calls.any((call) => results[call['id']] == null) &&
        widget.messages.any(
          (m) => m['run_id'] == run?['id'] || m['id'] == run?['assistant_id'],
        );
    final expanded = userExpanded ?? running;
    final step = run?['steps'];
    final detail = running && step is int && step > 0
        ? tr(context, 'runningStep').replaceAll('{count}', '$step')
        : webOnly
        ? tr(context, 'webTools')
        : '';
    final hasFailure = calls.any((c) => results[c['id']]?['is_error'] == true);
    final complete =
        calls.every((c) => results[c['id']] != null) && !hasFailure;
    final lead = widget.messages.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (messageString(lead['reasoning']).isNotEmpty)
            _Reasoning(message: lead, active: false),
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.line, width: .5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Semantics(
                  expanded: expanded,
                  child: InkWell(
                    onTap: () => setState(() => userExpanded = !expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(
                          children: [
                            if (running)
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  value: MediaQuery.disableAnimationsOf(context)
                                      ? .75
                                      : null,
                                  strokeWidth: 2,
                                  color: palette.accent,
                                ),
                              )
                            else
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: complete
                                      ? palette.green
                                      : palette.secondary,
                                ),
                                child: DesignIcon(
                                  complete
                                      ? Icons.check_rounded
                                      : Icons.remove_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 5,
                              child: Text(
                                running
                                    ? tr(context, 'toolsRunning')
                                    : tr(context, 'toolsCount').replaceAll(
                                        '{count}',
                                        '${calls.length}',
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: palette.ink,
                                ),
                              ),
                            ),
                            if (detail.isNotEmpty)
                              Flexible(
                                flex: 5,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 8,
                                    right: 8,
                                  ),
                                  child: Text(
                                    detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: palette.muted,
                                    ),
                                  ),
                                ),
                              ),
                            RotatedBox(
                              quarterTurns: expanded ? 2 : 0,
                              child: DesignIcon(
                                Icons.keyboard_arrow_down,
                                size: 15,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (expanded)
                  Container(
                    margin: const EdgeInsets.fromLTRB(40, 4, 14, 12),
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: palette.line, width: 1.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        for (final message in widget.messages) ...[
                          if (messageString(message['text']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  messageString(message['text']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.65,
                                    color: palette.secondary,
                                  ),
                                ),
                              ),
                            ),
                          for (final call in messageMaps(message['tool_calls']))
                            _ToolStep(
                              call: call,
                              result: results[call['id']],
                              running: running,
                              needsDevice: widget.conversation.needsDevice,
                            ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolStep extends StatefulWidget {
  const _ToolStep({
    required this.call,
    this.result,
    required this.running,
    required this.needsDevice,
  });
  final Map<String, dynamic> call;
  final Map<String, dynamic>? result;
  final bool running;
  final bool needsDevice;
  @override
  State<_ToolStep> createState() => _ToolStepState();
}

class _ToolStepState extends State<_ToolStep> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final palette = MobilePalette.of(context);
    final function = widget.call['function'];
    final name = function is Map ? messageString(function['name']) : '';
    final arguments = function is Map
        ? messageString(function['arguments'])
        : '';
    String detail = '';
    try {
      final args = jsonDecode(arguments);
      if (args is Map) {
        detail = messageString(args['query']);
        if (detail.isEmpty) {
          final url = messageString(args['url']);
          detail = Uri.tryParse(url)?.host ?? url;
        }
      }
    } on FormatException {
      // Stream previews may contain incomplete JSON; display only known facts.
    }
    final isSearch = name == 'web_search' || name == 'search_web';
    final isRead =
        name == 'web_fetch' || name == 'read_url' || name == 'fetch_url';
    final label = isSearch
        ? tr(context, 'toolSearch')
        : isRead
        ? tr(context, 'toolRead')
        : name.isEmpty
        ? tr(context, 'toolAction')
        : name;
    final statusKey = widget.result != null
        ? widget.result!['is_error'] == true
              ? 'toolFailed'
              : 'toolCompleted'
        : widget.running
        ? widget.needsDevice
              ? 'toolWaiting'
              : 'toolRunning'
        : 'toolInterrupted';
    final resultText = messageString(widget.result?['text']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: arguments.isEmpty && resultText.isEmpty
              ? null
              : () => setState(() => expanded = !expanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Row(
              children: [
                if (widget.result != null && widget.result!['is_error'] != true)
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: palette.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: DesignIcon(
                        Icons.check,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                  )
                else if (widget.running)
                  SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      value: MediaQuery.disableAnimationsOf(context)
                          ? .75
                          : null,
                      strokeWidth: 2,
                      color: palette.accent,
                    ),
                  )
                else
                  DesignIcon(
                    isSearch
                        ? Icons.search_rounded
                        : isRead
                        ? Icons.language
                        : Icons.build_outlined,
                    size: 14,
                    color: palette.secondary,
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    detail.isEmpty ? label : '$label · $detail',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: palette.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.result?['result_count'] is int
                      ? tr(context, 'toolResultCount').replaceAll(
                          '{count}',
                          '${widget.result!['result_count']}',
                        )
                      : tr(context, statusKey),
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 0, 10),
            child: Text(
              resultText.isNotEmpty ? resultText : arguments,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: palette.secondary,
                fontFamily: 'monospace',
                fontFamilyFallback: [
                  ?Theme.of(context).textTheme.bodyMedium?.fontFamily,
                  ...?Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.fontFamilyFallback,
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 32,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      iconSize: 15,
      color: MobilePalette.of(context).muted,
      icon: DesignIcon(icon),
    ),
  );
}

class _RunNotice extends StatelessWidget {
  const _RunNotice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.6,
        color: MobilePalette.of(context).secondary,
      ),
    ),
  );
}

class _StreamingCaretSyntax extends md.InlineSyntax {
  _StreamingCaretSyntax() : super('\uE000');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('stream-caret'));
    return true;
  }
}

class _StreamingCaretBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => Text.rich(
    TextSpan(
      style: parentStyle,
      children: [
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _StreamingCaret(),
        ),
      ],
    ),
  );
}

class _StreamingCaret extends StatefulWidget {
  const _StreamingCaret();
  @override
  State<_StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<_StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    value: .5,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
      animation.value = .5;
    } else if (!animation.isAnimating) {
      animation.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: 16,
        height: 16,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) => Center(
            child: Opacity(
              opacity: .55 + .45 * animation.value,
              child: Container(
                key: const ValueKey('streaming-caret'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: p.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: p.accent.withValues(alpha: .18),
                      spreadRadius: 4,
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

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children
        ?.whereType<md.Element>()
        .where((e) => e.tag == 'code')
        .firstOrNull;
    final language = (code?.attributes['class'] ?? '')
        .replaceFirst('language-', '')
        .trim();
    return _CodeBlock(
      code: element.textContent.replaceFirst(RegExp(r'\n$'), ''),
      language: language,
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.language});
  final String code, language;
  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.line, width: .5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  language.isEmpty ? tr(context, 'code') : language,
                  style: TextStyle(fontSize: 12, color: p.secondary),
                ),
              ),
              SizedBox(
                height: 34,
                width: 44,
                child: IconButton(
                  tooltip: tr(context, 'copyCode'),
                  padding: EdgeInsets.zero,
                  icon: DesignIcon(
                    Icons.copy_outlined,
                    size: 15,
                    color: p.secondary,
                  ),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr(context, 'copied'))),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Text.rich(
            TextSpan(children: _highlight(code, p)),
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: [
                ?Theme.of(context).textTheme.bodyMedium?.fontFamily,
                ...?Theme.of(context).textTheme.bodyMedium?.fontFamilyFallback,
              ],
              fontSize: 12.5,
              height: 1.6,
              color: p.ink,
            ),
          ),
        ),
      ],
    );
  }

  List<InlineSpan> _highlight(String source, MobilePalette palette) {
    final pattern = RegExp(
      r'''("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|//[^\n]*|#[^\n]*|\b(?:let|var|func|class|struct|enum|return|if|else|for|while|switch|case|break|const|final|def|import|async|await|void|true|false|null|nil)\b|\b[A-Z][A-Za-z0-9_]*\b|\b\d+(?:\.\d+)?\b|[\u4e00-\u9fff]+(?=\s*[≈=:]))''',
    );
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in pattern.allMatches(source)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: source.substring(offset, match.start)));
      }
      final token = match.group(0)!;
      final comment = token.startsWith('//') || token.startsWith('#');
      final type = RegExp(r'^(?:[A-Z]|[0-9])').hasMatch(token);
      spans.add(
        TextSpan(
          text: token,
          style: TextStyle(
            color: comment
                ? palette.muted
                : type
                ? Color(palette.dark ? 0xff79b8ff : 0xff2563eb)
                : Color(palette.dark ? 0xffff9f6b : 0xffc2410c),
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < source.length) {
      spans.add(TextSpan(text: source.substring(offset)));
    }
    return spans;
  }
}

class _CitationSyntax extends md.InlineSyntax {
  _CitationSyntax() : super(r'\[([0-9]+)\]\((https?://[^\s)]+)\)');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element('citation', [md.Text(match.group(1)!)])
        ..attributes['href'] = match.group(2)!,
    );
    return true;
  }
}

class _CitationBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (!RegExp(r'^\d+$').hasMatch(element.textContent)) return null;
    final p = MobilePalette.of(context);
    return Text.rich(
      TextSpan(
        style: parentStyle,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              key: ValueKey('citation-${element.attributes['href']}'),
              padding: const EdgeInsets.only(left: 3),
              child: Semantics(
                link: true,
                label: tr(
                  context,
                  'citation',
                ).replaceAll('{number}', element.textContent),
                child: InkWell(
                  onTap: () =>
                      _openWebLink(context, element.attributes['href']),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 17 + (element.textContent.length - 1) * 6.0,
                    height: 17,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: p.fill,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      element.textContent,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: p.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keep the Markdown parser's escaping/alignment rules while giving tables a
/// full-width card. Wide columns retain their intrinsic width and can scroll.
class _MobileTableSyntax extends md.TableSyntax {
  const _MobileTableSyntax();
  @override
  md.Node? parse(md.BlockParser parser) {
    final table = super.parse(parser);
    if (table is! md.Element) return table;
    final rows = <List<Map<String, String>>>[];
    for (final section
        in table.children?.whereType<md.Element>() ?? <md.Element>[]) {
      for (final row
          in section.children?.whereType<md.Element>() ?? <md.Element>[]) {
        rows.add([
          for (final cell
              in row.children?.whereType<md.Element>() ?? <md.Element>[])
            {
              'text': cell.textContent,
              'align': cell.attributes['align'] ?? 'left',
            },
        ]);
      }
    }
    return md.Element.empty('mobile-table')
      ..attributes['rows'] = jsonEncode(rows);
  }
}

class _MobileTableBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final rows = (jsonDecode(element.attributes['rows']!) as List)
        .cast<List<dynamic>>();
    final p = MobilePalette.of(context);
    return LayoutBuilder(
      builder: (context, bounds) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: bounds.maxWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                top: BorderSide(color: p.line, width: .5),
                bottom: BorderSide(color: p.line, width: .5),
                left: BorderSide(color: p.line, width: .5),
                right: BorderSide(color: p.line, width: .5),
                horizontalInside: BorderSide(color: p.line, width: .5),
                borderRadius: BorderRadius.circular(14),
              ),
              children: [
                for (var index = 0; index < rows.length; index++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: index == 0
                          ? Color.alphaBlend(p.fill, p.surface)
                          : p.surface,
                    ),
                    children: [
                      for (final cell in rows[index])
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: MarkdownBody(
                            data: cell['text'] as String,
                            fitContent: true,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                fontSize: index == 0 ? 12.5 : 13.5,
                                height: 1.2,
                                fontWeight: index == 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: index == 0 ? p.secondary : p.ink,
                              ),
                              a: TextStyle(color: p.accent),
                              strong: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              code: TextStyle(
                                fontFamily: 'monospace',
                                fontFamilyFallback: [
                                  ?Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.fontFamily,
                                  ...?Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.fontFamilyFallback,
                                ],
                                fontSize: 12.5,
                                backgroundColor: p.fill,
                                color: p.ink,
                              ),
                              textAlign: switch (cell['align']) {
                                'center' => WrapAlignment.center,
                                'right' => WrapAlignment.end,
                                _ => WrapAlignment.start,
                              },
                            ),
                            onTapLink: (_, href, _) =>
                                _openWebLink(context, href),
                            imageBuilder: (uri, title, alt) => Text(alt ?? ''),
                          ),
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
}

class _ThinkingLabel extends StatefulWidget {
  const _ThinkingLabel({required this.text});
  final String text;
  @override
  State<_ThinkingLabel> createState() => _ThinkingLabelState();
}

class _ThinkingLabelState extends State<_ThinkingLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
    value: .4,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.stop();
      motion.value = .4;
    } else if (!motion.isAnimating) {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return AnimatedBuilder(
      animation: motion,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-3 + motion.value * 4, 0),
          end: Alignment(-1 + motion.value * 4, 0),
          colors: [p.secondary, p.ink, p.secondary],
          stops: const [.2, .45, .7],
        ).createShader(bounds),
        child: child,
      ),
      child: Text(
        widget.text,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }
}
