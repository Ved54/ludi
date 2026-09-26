import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart' show Curves;

import '../ludi_game.dart';
import '../ludi_theme.dart';

/// The die from the A1 style guide — off-white body, dark pips, a shaded
/// side faking depth, one soft contact shadow. It lives in the active
/// player's HUD pod and travels to the next pod when the turn passes.
///
/// Tapping asks LudiGame for a roll. The die only *tumbles* here: the real
/// value comes from GameController once the tumble ends, and [land] shows
/// it — so the number never appears before the die has stopped.
class DiceComponent extends PositionComponent
    with TapCallbacks, HasGameReference<LudiGame> {
  DiceComponent() : super(size: Vector2.all(_side + 8), anchor: Anchor.center);

  static const double _side = 42;
  static const double _depth = 5;

  final Random _random = Random();
  int _face = 6;
  bool _hasRolled = false;

  double _tumble = -1; // seconds into the tumble, -1 when still
  Completer<void>? _tumbled;
  double _flicker = 0;
  double _spinDirection = 1;
  double _lift = 0;
  double _pop = 0;
  double _time = 0;

  static const Map<int, List<(double, double)>> _pips = {
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [(0.27, 0.24), (0.73, 0.24), (0.27, 0.5), (0.73, 0.5), (0.27, 0.76), (0.73, 0.76)],
  };

  bool get _rolling => _tumble >= 0;

  /// Throws the die: spins, hops, and flickers through random faces.
  /// Completes when it comes to rest; call [land] with the real value.
  Future<void> tumble() {
    _tumble = 0;
    _flicker = 0;
    _spinDirection = _random.nextBool() ? 1 : -1;
    _tumbled = Completer<void>();
    return _tumbled!.future;
  }

  /// Shows the rolled [value] with a little pop.
  void land(int value) {
    _face = value;
    _hasRolled = true;
    _pop = 1;
  }

  /// Slides over to [target] (a HUD pod's dice slot), arriving blank —
  /// the last player's number shouldn't read as the next player's roll.
  Future<void> travelTo(Vector2 target) {
    _hasRolled = false;
    final arrived = Completer<void>();
    add(
      MoveToEffect(
        target,
        EffectController(duration: LudiMotion.diceTravel, curve: Curves.easeInOutCubic),
        onComplete: arrived.complete,
      ),
    );
    add(
      RotateEffect.by(
        2 * pi * (_random.nextBool() ? 1 : -1),
        EffectController(duration: LudiMotion.diceTravel, curve: Curves.easeInOutCubic),
      ),
    );
    return arrived.future;
  }

  @override
  void onTapDown(TapDownEvent event) => game.requestRoll();

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    _pop = max(0, _pop - dt * 3.5);

    if (_rolling) {
      _tumble += dt;
      final t = min(1.0, _tumble / LudiMotion.diceTumble);
      final settle = 1 - pow(1 - t, 3).toDouble(); // ease-out
      angle = _spinDirection * 3.4 * pi * (1 - settle);
      _lift = sin(pi * min(1, t * 1.15)) * 16;
      _flicker += dt;
      // Faces change fast at first, slowing as the die settles.
      if (_flicker > 0.045 + 0.12 * t) {
        _flicker = 0;
        _face = 1 + (_face + _random.nextInt(5)) % 6;
      }
      if (t >= 1) {
        _tumble = -1;
        angle = 0;
        _lift = 0;
        final done = _tumbled;
        _tumbled = null;
        done?.complete();
      }
    } else if (game.canRoll && children.isEmpty) {
      // Waiting for a tap: a small wiggle every couple of seconds.
      final cycle = _time % 2.2;
      angle = cycle < 0.4 ? sin(cycle / 0.4 * 3 * pi) * 0.12 : 0;
    }

    final breathe = game.canRoll ? 0.035 * sin(_time * 4) : 0;
    scale.setAll(1 + breathe + 0.22 * sin(pi * _pop) * _pop);
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    final accent = playerPalette[game.activeColor]!;

    // Contact shadow stays on the table while the die is in the air.
    final shrink = 1 - _lift / 40;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-angle); // keep the shadow flat under the spin
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, _side / 2 + 3), width: _side * 0.9 * shrink, height: 7 * shrink),
      Paint()..color = LudiNeutral.textPrimary.withValues(alpha: 0.18 * shrink),
    );
    canvas.restore();

    canvas.save();
    canvas.translate(0, -_lift);
    final face = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: _side, height: _side),
      const Radius.circular(11),
    );
    if (game.canRoll) {
      final pulse = 0.5 + 0.5 * sin(_time * 4);
      canvas.drawRRect(
        face.inflate(3 + 2 * pulse),
        Paint()
          ..color = accent.base.withValues(alpha: 0.35 + 0.35 * pulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    canvas.drawRRect(face.shift(const Offset(0, _depth)), Paint()..color = LudiNeutral.diceSide);
    canvas.drawRRect(face, Paint()..color = LudiNeutral.surface);
    canvas.drawRRect(
      face,
      Paint()
        ..color = LudiNeutral.gridLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    if (_hasRolled || _rolling) {
      final pip = Paint()
        ..color = _face == 6 && !_rolling ? accent.deep : LudiNeutral.textPrimary;
      final origin = face.outerRect.topLeft;
      for (final (x, y) in _pips[_face]!) {
        canvas.drawCircle(origin + Offset(x * _side, y * _side), 4, pip);
      }
    } else {
      _paintRollHint(canvas, center, accent.deep);
    }
    canvas.restore();
  }

  /// Before the first roll: a circular-arrow glyph instead of pips.
  void _paintRollHint(Canvas canvas, Offset center, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const r = 10.0;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -pi * 0.35, pi * 1.6, false, paint);
    final tip = center + Offset(cos(-pi * 0.35) * r, sin(-pi * 0.35) * r);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - 6, tip.dy - 3)
        ..lineTo(tip.dx + 1, tip.dy + 1)
        ..lineTo(tip.dx - 1, tip.dy - 7),
      paint..strokeJoin = StrokeJoin.round,
    );
  }
}
