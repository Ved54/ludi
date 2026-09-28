import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../ludi_theme.dart';

/// Short callout — "Captured!", "Home!", "Red wins!". Pops in, holds long
/// enough to read, fades out; a new message replaces whatever is showing.
///
/// Shown at [home] (the board's center) unless given a spot, and kept
/// horizontally inside [bounds] so a callout near the edge isn't cut off.
class ToastComponent extends PositionComponent {
  ToastComponent() : super(anchor: Anchor.center, priority: 50);

  static const double _in = 0.22;
  static const double _hold = 1.0;
  static const double _out = 0.3;

  String _text = '';
  Color _accent = LudiNeutral.textPrimary;
  double _age = -1;

  /// Default spot for a callout, in game coordinates.
  Vector2 home = Vector2.zero();

  /// Area a callout must stay inside horizontally.
  Rect bounds = Rect.largest;

  void show(String text, {required Color accent, double hold = _hold, Vector2? at}) {
    _text = text;
    _accent = accent;
    _age = 0;
    _holdFor = hold;
    position.setFrom(at ?? home);
  }

  double _holdFor = _hold;

  /// The message on screen, or null when nothing is showing.
  String? get text => _age >= 0 ? _text : null;

  /// Seconds since [text] was shown — restarts on every [show].
  double get age => _age;

  @override
  void update(double dt) {
    super.update(dt);
    if (_age >= 0) {
      _age += dt;
      if (_age > _in + _holdFor + _out) _age = -1;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_age < 0) return;
    final double appear;
    if (_age < _in) {
      final t = _age / _in;
      appear = 1 + 2.2 * pow(t - 1, 3) + 1.2 * pow(t - 1, 2); // ease-out-back
    } else if (_age < _in + _holdFor) {
      appear = 1;
    } else {
      appear = 1 - (_age - _in - _holdFor) / _out;
    }
    final opacity = appear.clamp(0.0, 1.0);

    final painter = _style.toTextPainter(_text);
    final width = painter.width + 44;
    const height = 42.0;
    final left = bounds.left + width / 2;
    final right = bounds.right - width / 2;
    final nudge = left <= right ? position.x.clamp(left, right) - position.x : 0.0;
    canvas.save();
    canvas.translate(nudge, 0);
    canvas.scale(0.7 + 0.3 * appear, 0.7 + 0.3 * appear);
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      const Radius.circular(height / 2),
    );
    canvas.drawRRect(
      pill.shift(const Offset(0, 4)),
      Paint()
        ..color = LudiNeutral.textPrimary.withValues(alpha: 0.25 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(pill, Paint()..color = LudiNeutral.textPrimary.withValues(alpha: 0.94 * opacity));
    canvas.drawRRect(
      pill.deflate(1.5),
      Paint()
        ..color = _accent.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
    canvas.restore();
  }

  static final TextPaint _style = TextPaint(
    style: const TextStyle(
      fontFamily: ludiFontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w900,
      color: LudiNeutral.surface,
      letterSpacing: 0.3,
    ),
  );
}
