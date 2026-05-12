import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────
// PRESSROOM PRIMITIVES
// Card stock with hairline borders, hard offset shadows, mono badges,
// bracket-corner stamps, registration crosshairs, ruled section markers.
// ─────────────────────────────────────────────────────────────────────

/// Bracket corner — small L-shaped marks at corners (lab/stamp feel).
class BracketCorners extends StatelessWidget {
  final double size;
  final double thickness;
  final Color color;
  final EdgeInsets inset;
  const BracketCorners({
    super.key,
    this.size = 10,
    this.thickness = 1.2,
    this.color = AppTheme.ink,
    this.inset = const EdgeInsets.all(6),
  });

  @override
  Widget build(BuildContext context) {
    Widget bracket(AlignmentGeometry alignment) {
      final isTop = alignment == Alignment.topLeft ||
          alignment == Alignment.topRight;
      final isLeft = alignment == Alignment.topLeft ||
          alignment == Alignment.bottomLeft;
      return Align(
        alignment: alignment,
        child: Padding(
          padding: inset,
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _BracketPainter(
                color: color,
                thickness: thickness,
                top: isTop,
                left: isLeft,
              ),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            bracket(Alignment.topLeft),
            bracket(Alignment.topRight),
            bracket(Alignment.bottomLeft),
            bracket(Alignment.bottomRight),
          ],
        ),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top;
  final bool left;
  _BracketPainter({
    required this.color,
    required this.thickness,
    required this.top,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.square;
    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    canvas.drawLine(Offset(x, y), Offset(left ? size.width : 0, y), p);
    canvas.drawLine(Offset(x, y), Offset(x, top ? size.height : 0), p);
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Registration crosshair (printer's mark).
class CrosshairMark extends StatelessWidget {
  final double size;
  final Color color;
  const CrosshairMark({super.key, this.size = 14, this.color = AppTheme.ink});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CrosshairPainter(color)),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Color color;
  _CrosshairPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), p);
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), p);
    canvas.drawCircle(
      c,
      size.width * 0.22,
      Paint()
        ..color = color
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Index counter — "N° 04" style label, mono.
class FolioTag extends StatelessWidget {
  final String number;
  final String? label;
  final Color color;
  const FolioTag({
    super.key,
    required this.number,
    this.label,
    this.color = AppTheme.textTertiary,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('N\u00B0', style: AppTheme.label(color: color, size: 9)),
        const SizedBox(width: 4),
        Text(
          number,
          style: AppTheme.mono(
            size: 11,
            color: color,
            weight: FontWeight.w600,
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 8),
          Container(width: 12, height: 1, color: color),
          const SizedBox(width: 8),
          Text(label!.toUpperCase(), style: AppTheme.label(color: color)),
        ],
      ],
    );
  }
}

/// Card — paper stock with hairline border, optional thick top rule.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? accentColor;
  final Gradient? accentGradient;
  final bool showBorder;
  final VoidCallback? onTap;
  final bool elevated;

  const SurfaceCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.borderRadius = AppTheme.radiusMd,
    this.backgroundColor,
    this.accentColor,
    this.accentGradient,
    this.showBorder = true,
    this.onTap,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasAccent = accentColor != null || accentGradient != null;
    final accent =
        accentColor ?? (accentGradient?.colors.first ?? AppTheme.ink);

    Widget card = Container(
      width: width,
      height: height,
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.paperLight,
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder ? Border.all(color: AppTheme.hairline) : null,
        boxShadow: elevated ? AppTheme.softShadowList() : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAccent)
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: accent,
                gradient: accentGradient,
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: card,
      );
    }
    return card;
  }
}

/// Press button — solid ink fill, hard offset shadow, mono small caps text.
class ActionButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Gradient? gradient;
  final Color? backgroundColor;
  final double width;
  final double height;
  final double borderRadius;
  final bool secondary;

  const ActionButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.gradient,
    this.backgroundColor,
    this.width = double.infinity,
    this.height = 50,
    this.borderRadius = AppTheme.radiusMd,
    this.secondary = false,
  });

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final isSecondary = widget.secondary;

    final fill = widget.backgroundColor ??
        (widget.gradient?.colors.first) ??
        (isSecondary ? AppTheme.paperLight : AppTheme.ink);
    final fg = isSecondary
        ? AppTheme.ink
        : (fill == AppTheme.paperLight ? AppTheme.ink : AppTheme.paperLight);
    final disabled = !enabled;

    final pressOffset = disabled || _pressed ? 0.0 : 2.0;

    return GestureDetector(
      onTap: enabled ? widget.onPressed : null,
      onTapDown: (_) {
        if (enabled) setState(() => _pressed = true);
      },
      onTapUp: (_) {
        if (enabled) setState(() => _pressed = false);
      },
      onTapCancel: () {
        if (enabled) setState(() => _pressed = false);
      },
      child: SizedBox(
        width: widget.width,
        height: widget.height + 3,
        child: Stack(
          children: [
            if (!disabled)
              Positioned(
                left: 2,
                top: 2,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.ink,
                    borderRadius:
                        BorderRadius.circular(widget.borderRadius),
                  ),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 80),
              curve: Curves.easeOut,
              left: 0,
              top: 0,
              right: 2 - pressOffset,
              bottom: 2 - pressOffset,
              child: Container(
                decoration: BoxDecoration(
                  color: disabled ? AppTheme.paperInk : fill,
                  borderRadius:
                      BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: disabled ? AppTheme.hairline : AppTheme.ink,
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: widget.isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: fg,
                            strokeWidth: 1.8,
                          ),
                        )
                      : Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(widget.icon, color: fg, size: 16),
                                const SizedBox(width: 10),
                              ],
                              Flexible(
                                child: Text(
                                  widget.text.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: AppTheme.mono(
                                    size: 11,
                                    color: disabled
                                        ? AppTheme.textTertiary
                                        : fg,
                                    weight: FontWeight.w600,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text field — underline only, mono floating label, ink caret.
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.maxLines = 1,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 160),
          style: AppTheme.label(
            color: _focused ? AppTheme.persimmon : AppTheme.textSecondary,
            size: 10,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: _focused ? 12 : 8,
                height: 1,
                color: _focused ? AppTheme.persimmon : AppTheme.ink,
              ),
              const SizedBox(width: 8),
              Text(widget.label.toUpperCase()),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.prefixIcon != null) ...[
              Icon(
                widget.prefixIcon,
                size: 18,
                color: _focused ? AppTheme.ink : AppTheme.textTertiary,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                obscureText: widget.obscureText,
                keyboardType: widget.keyboardType,
                maxLines: widget.maxLines,
                autofocus: widget.autofocus,
                onSubmitted: widget.onSubmitted,
                cursorColor: AppTheme.persimmon,
                cursorWidth: 2,
                style: AppTheme.body(
                  size: 15,
                  color: AppTheme.ink,
                  height: 1.3,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: widget.hint,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (widget.suffixIcon != null) widget.suffixIcon!,
          ],
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: _focused ? 2 : 1,
          color: _focused ? AppTheme.ink : AppTheme.hairline,
        ),
      ],
    );
  }
}

/// Status badge — small stamp, mono small caps, hairline border, slight tilt.
class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool showPulse;
  final bool stamp;

  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
    this.icon,
    this.showPulse = false,
    this.stamp = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showPulse) ...[
            _PulseDot(color: color),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, color: color, size: 11),
            const SizedBox(width: 5),
          ],
          Text(
            text.toUpperCase(),
            style: AppTheme.mono(
              size: 9.5,
              weight: FontWeight.w700,
              color: color,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
    if (!stamp) return content;
    return Transform.rotate(angle: -0.05, child: content);
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final pulse = (math.sin(_ctrl.value * math.pi * 2) + 1) / 2;
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.rectangle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.5 * pulse),
                blurRadius: 4 * pulse,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Icon button — square, hairline, hover ink fill.
class AppIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final String? tooltip;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.size = 38,
    this.tooltip,
  });

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.color ?? AppTheme.ink;
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: _hover
                ? AppTheme.ink
                : (widget.backgroundColor ?? AppTheme.paperLight),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.ink, width: 1),
          ),
          child: Icon(
            widget.icon,
            color: _hover ? AppTheme.paperLight : iconColor,
            size: widget.size * 0.45,
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// Section header — small caps title with rule, optional index.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? index;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (index != null) ...[
                Text(
                  index!,
                  style: AppTheme.mono(
                    size: 10,
                    color: AppTheme.persimmon,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                '\u2014',
                style: AppTheme.mono(size: 11, color: AppTheme.textTertiary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: AppTheme.mono(
                    size: 11,
                    color: AppTheme.ink,
                    weight: FontWeight.w700,
                    letterSpacing: 2.4,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: AppTheme.hairline),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: AppTheme.body(
                size: 13,
                color: AppTheme.textSecondary,
                style: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stat tile — large mono numeral with serif label + corner crosshair.
class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: AppTheme.paperLight,
          border: Border.all(color: AppTheme.hairline),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 8),
                    Text(
                      label.toUpperCase(),
                      style: AppTheme.label(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(width: 24, height: 2, color: color),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: AppTheme.display(
                    size: 30,
                    weight: FontWeight.w600,
                    color: AppTheme.ink,
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
            Positioned(
              right: -2,
              top: -2,
              child: CrosshairMark(size: 10, color: color.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paper background with dotted grid, registration marks and a rotated rule.
class NexusBackground extends StatelessWidget {
  final Widget child;
  const NexusBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: AppTheme.paper),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _PaperGridPainter()),
          ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: CrosshairMark(size: 12, color: AppTheme.persimmon),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: CrosshairMark(size: 12, color: AppTheme.ink),
        ),
        Positioned(
          bottom: 10,
          left: 10,
          child: CrosshairMark(size: 12, color: AppTheme.ink),
        ),
        Positioned(
          bottom: 10,
          right: 10,
          child: CrosshairMark(size: 12, color: AppTheme.persimmon),
        ),
        child,
      ],
    );
  }
}

class _PaperGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()
      ..color = AppTheme.hairline.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    const step = 28.0;
    for (double x = step / 2; x < size.width; x += step) {
      for (double y = step / 2; y < size.height; y += step) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), dot);
      }
    }
    // Diagonal hairline rule
    final rule = Paint()
      ..color = AppTheme.hairline.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    canvas.save();
    canvas.translate(-30, size.height * 0.55);
    canvas.rotate(-0.06);
    canvas.drawLine(Offset.zero, Offset(size.width * 0.5, 0), rule);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_) => false;
}

// Legacy aliases (used by old imports).
typedef GlassContainer = SurfaceCard;
typedef GlassButton = ActionButton;
typedef GlassTextField = AppTextField;
