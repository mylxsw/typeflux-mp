import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Direct port of the design's AskConversationOrb spline and gradient.
class ConversationOrb extends StatefulWidget {
  const ConversationOrb({
    super.key,
    this.size = 96,
    this.listening = false,
    this.phase = .62,
  });
  final double size, phase;
  final bool listening;
  @override
  State<ConversationOrb> createState() => _ConversationOrbState();
}

class _ConversationOrbState extends State<ConversationOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
    value: widget.phase,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.stop();
      motion.value = widget.phase;
    } else if (!motion.isAnimating) {
      motion.repeat(period: Duration(seconds: widget.listening ? 3 : 8));
    }
  }

  @override
  void didUpdateWidget(ConversationOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listening != widget.listening &&
        !MediaQuery.disableAnimationsOf(context)) {
      motion.repeat(period: Duration(seconds: widget.listening ? 3 : 8));
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: motion,
        builder: (_, _) => CustomPaint(painter: _OrbPainter(motion.value)),
      ),
    ),
  );
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.phase);
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width, mid = Offset(size.width / 2, size.height / 2);
    final turn = math.pi * 2 * phase;
    final points = List.generate(96, (i) {
      final a = math.pi * 2 * i / 96;
      final r =
          s /
          2 /
          1.07 *
          (1 +
              .07 *
                  (.55 * math.sin(2 * a + turn) +
                      .3 * math.sin(3 * a - 2 * turn + 1.3) +
                      .15 * math.sin(5 * a + 3 * turn + .4)));
      return mid + Offset(r * math.cos(a), r * math.sin(a));
    });
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    final angle = math.pi / 6 + math.pi / 12 * math.sin(turn);
    final direction = Offset(math.cos(angle), math.sin(angle));
    final start = mid - direction * (2.4 * (.5 + phase) * s);
    const colors = [
      Color(0xff2e6bff),
      Color(0xff8c5cf5),
      Color(0xffff4d8c),
      Color(0xffffb347),
      Color(0xff2ee6d6),
    ];
    final shader = ui.Gradient.linear(start, start + direction * (4.8 * s), [
      ...colors,
      ...colors,
      colors.first,
    ], List.generate(11, (i) => i / 10));
    final scale = 1 + .0175 * (1 - math.cos(turn * 2));
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.scale(scale);
    canvas.translate(-mid.dx, -mid.dy);
    canvas.save();
    canvas.translate(mid.dx, s * .56);
    canvas.scale(.9);
    canvas.translate(-mid.dx, -mid.dy);
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..color = const Color(0x9effffff)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .16),
    );
    canvas.restore();
    canvas.drawPath(path, Paint()..shader = shader);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(Offset(s * .34, s * .26), s * .3, [
          const Color(0xb3ffffff),
          const Color(0x00ffffff),
        ]),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          mid,
          s * .52,
          [const Color(0x00000000), const Color(0x29000000)],
          [.28 / .52, 1],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) => oldDelegate.phase != phase;
}
