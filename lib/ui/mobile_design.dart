import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Exact color tokens from docs/design/mobile-v4-reference.html.
class MobilePalette {
  const MobilePalette(this.dark);
  factory MobilePalette.of(BuildContext context) =>
      MobilePalette(Theme.of(context).brightness == Brightness.dark);
  final bool dark;
  Color get bg => Color(dark ? 0xff0f0f12 : 0xfff5f5f7);
  Color get ink =>
      dark ? Colors.white.withValues(alpha: .93) : const Color(0xff1d1d1f);
  Color get secondary =>
      Color(dark ? 0xffebebf5 : 0xff3c3c43).withValues(alpha: dark ? .60 : .62);
  Color get muted =>
      Color(dark ? 0xffebebf5 : 0xff3c3c43).withValues(alpha: dark ? .30 : .34);
  Color get line =>
      (dark ? Colors.white : Colors.black).withValues(alpha: dark ? .09 : .08);
  Color get fill => const Color(0xff787880).withValues(alpha: dark ? .20 : .10);
  Color get fill2 =>
      const Color(0xff787880).withValues(alpha: dark ? .28 : .16);
  Color get hover => fill;
  Color get glass => dark
      ? const Color(0xff2c2c34).withValues(alpha: .72)
      : Colors.white.withValues(alpha: .74);
  Color get surface => Color(dark ? 0xff1c1c21 : 0xffffffff);
  Color get panel => surface;
  Color get tool => surface;
  Color get code => Color(dark ? 0xff18181d : 0xfff2f3f6);
  Color get accent => Color(dark ? 0xff178cff : 0xff2e6df0);
  Color get accentText => Color(dark ? 0xff8ebdff : 0xff1b57d6);
  Color get accentSoft => Color(dark ? 0xff15263e : 0xffe6eefd);
  Color get purple => Color(dark ? 0xffb58cff : 0xff7d40f0);
  Color get bubble => Color(dark ? 0xff1e3357 : 0xffe4edfd);
  Color get bubbleInk => Color(dark ? 0xffe1ebff : 0xff10234d);
  Color get green => Color(dark ? 0xff32d74b : 0xff30b158);
  Color get red => Color(dark ? 0xffff453a : 0xffe5352b);
  Color get cardBorder => Colors.white.withValues(alpha: dark ? .12 : .9);
  Color get track => fill;
}

/// The three CSS radial gradients, scaled to their authored pixel radii.
class MobileAmbient extends StatelessWidget {
  const MobileAmbient({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _AmbientPainter(MobilePalette.of(context)),
    child: child,
  );
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.palette);
  final MobilePalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.bg);
    void glow(Offset center, Size radius, Color color) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(radius.width, radius.height);
      canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, .7],
          ).createShader(const Rect.fromLTWH(-1, -1, 2, 2)),
      );
      canvas.restore();
    }

    glow(
      Offset(size.width * .2, 0),
      const Size(360, 260),
      Color(palette.dark ? 0xff178cff : 0xff2e6df0)
          .withValues(alpha: palette.dark ? .20 : .13),
    );
    glow(
      Offset(size.width * .92, size.height * .08),
      const Size(320, 240),
      Color(palette.dark ? 0xff7c3aed : 0xff8c5cf5)
          .withValues(alpha: palette.dark ? .16 : .10),
    );
    glow(
      Offset(size.width * .5, size.height * 1.08),
      const Size(420, 280),
      Color(palette.dark ? 0xfff97316 : 0xffffb347)
          .withValues(alpha: palette.dark ? .06 : .08),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.palette.dark != palette.dark;
}

class MobileGlass extends StatelessWidget {
  const MobileGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.panel = false,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final double radius;
  final bool panel;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final p = MobilePalette.of(context);
    final rounding = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: rounding,
        boxShadow: [
          BoxShadow(
            color: p.dark ? const Color(0x80000000) : const Color(0x1a1a2040),
            blurRadius: p.dark ? 30 : 28,
            offset: Offset(0, p.dark ? 10 : 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? .4 : .08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: rounding,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: const ColorFilter.matrix([
              1.551,
              -.5005,
              -.0505,
              0,
              0,
              -.149,
              1.1995,
              -.0505,
              0,
              0,
              -.149,
              -.5005,
              1.6495,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            inner: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: panel ? p.surface : p.glass,
              borderRadius: rounding,
              border: Border.all(color: p.cardBorder, width: .5),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class MobileIconButton extends StatelessWidget {
  const MobileIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.glass = false,
    this.color,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool glass;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: label,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        iconSize: 20,
        color: color ?? MobilePalette.of(context).secondary,
        icon: DesignIcon(icon),
      ),
    );
    return glass ? MobileGlass(radius: 22, child: button) : button;
  }
}

/// SVG geometry is extracted verbatim from the user's final v4 HTML.
class DesignIcon extends StatelessWidget {
  const DesignIcon(this.icon, {super.key, this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;
  static final assets = <IconData, String>{
    Icons.view_sidebar_outlined: 'side',
    Icons.edit_square: 'compose',
    Icons.chevron_left: 'left',
    Icons.chevron_right: 'right',
    Icons.keyboard_arrow_down: 'down',
    Icons.add: 'plus',
    Icons.check: 'check',
    Icons.check_rounded: 'check',
    Icons.arrow_upward_rounded: 'up',
    Icons.language: 'globe',
    Icons.translate: 'trans',
    Icons.image_outlined: 'photo',
    Icons.restart_alt: 'reset',
    Icons.mic_none: 'mic',
    Icons.auto_awesome_outlined: 'spark',
    Icons.copy_outlined: 'copy',
    Icons.content_copy: 'copy',
    Icons.refresh_rounded: 'retry',
    Icons.refresh: 'retry',
    Icons.ios_share: 'share',
    Icons.search_rounded: 'search',
    Icons.search: 'search',
    Icons.settings_outlined: 'gear',
    Icons.settings: 'gear',
    Icons.mail_outline: 'mail',
    Icons.dark_mode_outlined: 'moon',
    Icons.nightlight_round: 'moon',
    Icons.shield_outlined: 'hand',
    Icons.privacy_tip_outlined: 'hand',
    Icons.info_outline: 'info',
    Icons.apple: 'apple',
    Icons.front_hand_outlined: 'hand',
  };
  @override
  Widget build(BuildContext context) {
    final asset = assets[icon];
    if (asset == null) return Icon(icon, size: size, color: color);
    final theme = IconTheme.of(context);
    final dimension = size ?? theme.size ?? 20;
    final variant = asset == 'apple'
        ? ''
        : dimension <= 11
        ? '-xs'
        : dimension <= 15
        ? '-sm'
        : '';
    return SvgPicture.asset(
      'assets/design/v4/$asset$variant.svg',
      width: dimension,
      height: dimension,
      colorFilter: ColorFilter.mode(
        color ?? theme.color ?? MobilePalette.of(context).secondary,
        BlendMode.srcIn,
      ),
    );
  }
}
