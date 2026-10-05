import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_controller.dart';
import '../chat/model_options.dart';
import 'mobile_design.dart';
import 'strings.dart';

class MobileModelPicker extends StatelessWidget {
  const MobileModelPicker({
    super.key,
    required this.controller,
    required this.modelsPage,
    required this.onPageChanged,
    required this.hasImages,
  });
  final ChatController controller;
  final bool modelsPage, hasImages;
  final ValueChanged<bool> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: modelsPage ? 100 : 92,
          bottom: -7,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: p.glass,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        MobileGlass(
          radius: 26,
          child: modelsPage ? _models(context) : _effort(context),
        ),
      ],
    );
  }

  Widget _effort(BuildContext context) {
    final p = MobilePalette.of(context), model = controller.selectedModel;
    final effort = controller.reasoningEffort;
    final offered = model?.reasoningEfforts ?? <String>[];
    final top =
        effort.isNotEmpty && offered.isNotEmpty && effort == offered.last;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 30),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        offered.isEmpty
                            ? model?.name ?? tr(context, 'default')
                            : tr(
                                context,
                                'effort_${effort.isEmpty ? 'auto' : effort}',
                              ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: top ? p.purple : p.accentText,
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: tr(context, 'changeModel'),
                        child: InkWell(
                          onTap: () => onPageChanged(true),
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 22),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    offered.isEmpty
                                        ? tr(context, 'changeModel')
                                        : model!.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.2,
                                      color: p.secondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                DesignIcon(
                                  Icons.chevron_right,
                                  size: 11,
                                  color: p.secondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    tooltip: tr(context, 'resetEffort'),
                    padding: EdgeInsets.zero,
                    onPressed: effort.isEmpty
                        ? null
                        : () => controller.setReasoningEffort(''),
                    icon: DesignIcon(
                      Icons.restart_alt,
                      size: 15,
                      color: p.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (offered.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: EffortSlider(
                levels: offered,
                value: effort,
                onChanged: controller.setReasoningEffort,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final labels = [
                    for (final level in offered)
                      Text(
                        tr(context, 'effort_$level'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.2,
                          color: effort == level
                              ? (top ? p.purple : p.accentText)
                              : p.muted,
                          fontWeight: effort == level
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                  ];
                  var intrinsicWidth = 0.0;
                  for (final label in labels) {
                    final painter = TextPainter(
                      text: TextSpan(
                        text: label.data,
                        style: DefaultTextStyle.of(context).style
                            .merge(label.style),
                      ),
                      textScaler: MediaQuery.textScalerOf(context),
                      textDirection: Directionality.of(context),
                    )..layout();
                    intrinsicWidth += painter.width;
                    painter.dispose();
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children:
                        intrinsicWidth + (labels.length - 1) * 8 <
                            constraints.maxWidth
                        ? labels
                        : [for (final label in labels) Expanded(child: label)],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Text(
                tr(
                  context,
                  'effortCaption_${effort.isEmpty ? 'auto' : effort}',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: p.secondary,
                ),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Text(
                tr(context, model == null ? 'modelsLoading' : 'noReasoning'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: p.secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _models(BuildContext context) {
    final p = MobilePalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: p.secondary,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              minimumSize: const Size(44, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => onPageChanged(false),
            icon: const DesignIcon(Icons.chevron_left, size: 11),
            label: Text(
              tr(context, 'reasoning'),
              style: const TextStyle(fontSize: 13.5, height: 1.2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Typeflux Cloud',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: p.muted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  tr(context, 'multiplier'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: p.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (final model in controller.modelOptions)
                _model(context, model),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(18, 11, 18, 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.line, width: .5)),
          ),
          child: Text(
            tr(context, 'cloudModelsOnly'),
            style: TextStyle(fontSize: 12, height: 1.2, color: p.muted),
          ),
        ),
      ],
    );
  }

  Widget _model(BuildContext context, ModelOption model) {
    final p = MobilePalette.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(15) > 18;
    final disabled = hasImages && model.vision != true;
    final selected = controller.selectedModel?.reference == model.reference;
    final details = <String>[
      if (model.contextWindowTokens != null)
        '${_tokens(model.contextWindowTokens!)} ${tr(context, 'context')}',
      if (model.maxOutputTokens != null)
        '${_tokens(model.maxOutputTokens!)} ${tr(context, 'output')}',
    ].join(' · ');
    return Semantics(
      selected: selected,
      enabled: !disabled,
      child: Opacity(
        opacity: disabled ? .4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Material(
            color: selected ? p.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: ValueKey('model-${model.reference}'),
              borderRadius: BorderRadius.circular(14),
              onTap: disabled
                  ? null
                  : () {
                      final before = controller.reasoningEffort;
                      controller.changeModel(model.reference);
                      onPageChanged(false);
                      if (before != controller.reasoningEffort) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(tr(context, 'effortAdjusted')),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    _ModelMark(name: model.name),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: selected ? p.accentText : p.ink,
                            ),
                          ),
                          if (disabled || details.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                disabled
                                    ? tr(context, 'imageModelDisabled')
                                    : details,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.2,
                                  color: p.secondary,
                                ),
                              ),
                            ),
                          if (compact && model.vision == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: _visionBadge(context, p),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (!compact && model.vision == true)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _visionBadge(context, p),
                      ),
                    if (model.multiplierLabel != null)
                      Text(
                        model.multiplierLabel!.replaceAll('X', '×'),
                        style: TextStyle(
                          fontSize: 13,
                          color: p.secondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 15,
                      child: selected
                          ? DesignIcon(Icons.check, size: 15, color: p.accent)
                          : null,
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

  Widget _visionBadge(BuildContext context, MobilePalette p) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: p.muted, width: .8),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      tr(context, 'vision'),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: p.secondary,
      ),
    ),
  );

  String _tokens(int count) => count >= 1000000
      ? '${(count / 1000000).toStringAsFixed(count % 1000000 == 0 ? 0 : 1)}M'
      : count >= 1000
      ? '${(count / 1000).round()}K'
      : '$count';
}

/// The supplied design uses colored initials, not vendor trademark images.
class _ModelMark extends StatelessWidget {
  const _ModelMark({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final n = name.toLowerCase();
    final (letter, colors) = n.contains('minimax')
        ? ('M', const [Color(0xffff5f6d), Color(0xffffb347)])
        : n.contains('claude')
        ? ('C', const [Color(0xffd97757), Color(0xffc15f3c)])
        : n.contains('gpt')
        ? ('G', const [Color(0xff10a37f), Color(0xff0b7a5e)])
        : n.contains('deepseek')
        ? ('D', const [Color(0xff4d6bfe), Color(0xff2f48c9)])
        : (
            name.isEmpty ? 'T' : name.characters.first.toUpperCase(),
            [
              MobilePalette.of(context).accent,
              MobilePalette.of(context).purple,
            ],
          );
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class EffortSlider extends StatelessWidget {
  const EffortSlider({
    super.key,
    required this.levels,
    required this.value,
    required this.onChanged,
  });
  final List<String> levels;
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) return const SizedBox.shrink();
    final index = value.isEmpty
        ? ((levels.length - 1) / 2).floor()
        : math.max(0, levels.indexOf(value));
    void step(int delta) =>
        onChanged(levels[(index + delta).clamp(0, levels.length - 1)]);
    return Semantics(
      label: tr(context, 'reasoning'),
      value: tr(context, 'effort_${value.isEmpty ? 'auto' : value}'),
      increasedValue: tr(
        context,
        'effort_${levels[(index + 1).clamp(0, levels.length - 1)]}',
      ),
      decreasedValue: tr(
        context,
        'effort_${levels[(index - 1).clamp(0, levels.length - 1)]}',
      ),
      onIncrease: () => step(1),
      onDecrease: () => step(-1),
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            step(1);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            step(-1);
          } else if (event.logicalKey == LogicalKeyboardKey.home) {
            onChanged(levels.first);
          } else if (event.logicalKey == LogicalKeyboardKey.end) {
            onChanged(levels.last);
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: LayoutBuilder(
          builder: (context, size) {
            void pick(double x) => onChanged(
              levels[((x - 16) /
                      math.max(1, size.maxWidth - 32) *
                      (levels.length - 1))
                  .round()
                  .clamp(0, levels.length - 1)],
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (e) => pick(e.localPosition.dx),
              onHorizontalDragUpdate: (e) => pick(e.localPosition.dx),
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: CustomPaint(
                  painter: _EffortPainter(
                    MobilePalette.of(context),
                    levels.length,
                    index,
                    value.isEmpty,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EffortPainter extends CustomPainter {
  const _EffortPainter(this.palette, this.count, this.index, this.auto);
  final MobilePalette palette;
  final int count, index;
  final bool auto;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 6, size.width, 32);
    final round = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    canvas.drawRRect(round, Paint()..color = palette.track);
    double center(int i) =>
        count == 1 ? size.width / 2 : 16 + i * (size.width - 32) / (count - 1);
    final x = center(index);
    for (var i = 0; i < count; i++) {
      if (auto || i > index) {
        canvas.drawCircle(
          Offset(center(i), 22),
          2,
          Paint()..color = palette.muted.withValues(alpha: .6),
        );
      }
    }
    if (!auto) {
      final top = index == count - 1;
      canvas.save();
      canvas.clipRRect(round);
      final fill = Rect.fromLTRB(0, 6, math.min(size.width, x + 16), 38);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, const Radius.circular(16)),
        Paint()
          ..shader = LinearGradient(
            colors: top
                ? const [
                    Color(0xff8f9cff),
                    Color(0xff9c6bff),
                    Color(0xff8a40f0),
                  ]
                : const [Color(0xff2663eb), Color(0xff3b82ff)],
          ).createShader(fill),
      );
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(fill, const Radius.circular(16)),
      );
      canvas.drawRect(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: top ? .30 : .28),
              Colors.white.withValues(alpha: 0),
              Colors.black.withValues(alpha: .08),
            ],
            stops: const [0, .52, 1],
          ).createShader(fill),
      );
      for (var i = 0; i < 14; i++) {
        canvas.drawCircle(
          Offset(
            8 + (i * 37) % math.max(10, fill.width - 34),
            12 + (i * 13) % 20,
          ),
          1.25,
          Paint()
            ..color = Colors.white.withValues(
              alpha: .75 * (.35 + (i % 4) * .15),
            ),
        );
      }
      canvas.restore();
      canvas.restore();
      final knob = Path()
        ..addOval(Rect.fromCircle(center: Offset(x, 22), radius: 13));
      canvas.drawShadow(knob, Colors.black38, 3, true);
      canvas.drawCircle(
        Offset(x, 22),
        13,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, -.4),
            radius: .72,
            colors: [Colors.white, Color(0xfff0f0f0), Color(0xffe0e0e0)],
            stops: [0, .55, 1],
          ).createShader(Rect.fromCircle(center: Offset(x, 22), radius: 13)),
      );
    } else {
      for (var i = 0; i < 12; i++) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset(x, 22), radius: 12.5),
          i * math.pi / 6,
          math.pi / 10,
          false,
          Paint()
            ..color = palette.muted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EffortPainter old) =>
      old.index != index ||
      old.count != count ||
      old.auto != auto ||
      old.palette.dark != palette.dark;
}
