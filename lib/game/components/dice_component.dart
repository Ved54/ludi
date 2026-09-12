import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../rules_engine/models/game_state.dart' show GamePhase;
import '../../state/game_controller.dart';
import '../ludi_theme.dart';

/// The flat isometric cube from the A1 style guide — white body, dark
/// pips, two shaded faces faking depth, one soft contact shadow. Tap to
/// roll (only responds during GamePhase.rolling); the real result comes
/// back instantly from GameController.rollDice(), but the display holds
/// off revealing it — flickering through random faces for ~600ms with a
/// tumble effect — before locking onto the true value.
///
/// The rolled number is read from GameState.lastRoll (a display-only value
/// that survives the turn auto-skipping), not lastDiceValue — so a non-6
/// roll in a fresh game still shows what came up before the turn passes.
class DiceComponent extends PositionComponent with TapCallbacks {
  DiceComponent({required this.controller})
      : super(size: Vector2(_faceSize + _depth, _faceSize + _depth + 12));

  final GameController controller;

  static const double _faceSize = 36;
  static const double _depth = 10;
  static const Duration _rollDuration = Duration(milliseconds: 600);
  static const Duration _flickerInterval = Duration(milliseconds: 90);

  /// How long the result stays at full brightness after the tumble ends,
  /// before dimming to invite the next tap — long enough to read it even
  /// when the turn skipped straight past.
  static const double _resultHoldSeconds = 1.2;

  final Random _random = Random();
  bool _isRolling = false;
  int _displayPips = 1;
  double _flickerElapsed = 0;
  double _resultHold = 0;

  static const Map<int, List<List<double>>> _pipLayout = {
    1: [[0.5, 0.5]],
    2: [[0.28, 0.28], [0.72, 0.72]],
    3: [[0.28, 0.28], [0.5, 0.5], [0.72, 0.72]],
    4: [[0.28, 0.28], [0.72, 0.28], [0.28, 0.72], [0.72, 0.72]],
    5: [[0.28, 0.28], [0.72, 0.28], [0.5, 0.5], [0.28, 0.72], [0.72, 0.72]],
    6: [[0.28, 0.22], [0.72, 0.22], [0.28, 0.5], [0.72, 0.5], [0.28, 0.78], [0.72, 0.78]],
  };

  @override
  void update(double dt) {
    super.update(dt);
    if (_isRolling) {
      _flickerElapsed += dt;
      if (_flickerElapsed >= _flickerInterval.inMilliseconds / 1000) {
        _flickerElapsed = 0;
        _displayPips = 1 + _random.nextInt(6);
      }
    } else {
      if (_resultHold > 0) _resultHold -= dt;
      if (controller.state.lastRoll > 0) {
        _displayPips = controller.state.lastRoll;
      }
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (_isRolling || controller.state.phase != GamePhase.rolling) return;
    _isRolling = true;
    controller.rollDice();

    final seconds = _rollDuration.inMilliseconds / 1000;
    add(
      RotateEffect.by(
        2 * pi,
        EffectController(duration: seconds, curve: Curves.easeOut),
        onComplete: () {
          _isRolling = false;
          _displayPips = controller.state.lastRoll;
          _resultHold = _resultHoldSeconds;
        },
      ),
    );
    add(
      ScaleEffect.by(
        Vector2.all(1.18),
        EffectController(
          duration: seconds / 4,
          reverseDuration: seconds / 4,
          repeatCount: 2,
          curve: Curves.easeInOut,
        ),
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    final neverRolled = controller.state.lastRoll == 0;
    // Dimmed while waiting for a tap — but not right after a roll (hold
    // the result bright long enough to read), and not mid-tumble.
    final prompting = !_isRolling &&
        _resultHold <= 0 &&
        controller.state.phase == GamePhase.rolling;
    final dim = neverRolled || prompting;
    final opacity = dim ? 0.55 : 1.0;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(_faceSize / 2, _faceSize + _depth + 6),
        width: _faceSize * 0.8,
        height: 6,
      ),
      Paint()..color = LudiNeutral.textPrimary.withValues(alpha: 0.12 * opacity),
    );

    final topFace = Path()
      ..moveTo(0, _depth)
      ..lineTo(_depth, 0)
      ..lineTo(_depth + _faceSize, 0)
      ..lineTo(_faceSize, _depth)
      ..close();
    canvas.drawPath(
      topFace,
      Paint()..color = const Color(0xFFF3EFE7).withValues(alpha: opacity),
    );

    final sideFace = Path()
      ..moveTo(_faceSize, _depth)
      ..lineTo(_faceSize + _depth, 0)
      ..lineTo(_faceSize + _depth, _faceSize)
      ..lineTo(_faceSize, _faceSize + _depth)
      ..close();
    canvas.drawPath(
      sideFace,
      Paint()..color = const Color(0xFFE6E0D4).withValues(alpha: opacity),
    );

    final frontRect = Rect.fromLTWH(0, _depth, _faceSize, _faceSize);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frontRect, const Radius.circular(6)),
      Paint()..color = LudiNeutral.trackSquare.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frontRect, const Radius.circular(6)),
      Paint()
        ..color = LudiNeutral.gridLine.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Pips show while tumbling and any time a value has ever been rolled —
    // dimmed with the rest of the cube when waiting for the next tap.
    if (_isRolling || !neverRolled) {
      final pipPaint = Paint()..color = LudiNeutral.textPrimary.withValues(alpha: opacity);
      for (final p in _pipLayout[_displayPips]!) {
        canvas.drawCircle(
          Offset(p[0] * _faceSize, _depth + p[1] * _faceSize),
          2.6,
          pipPaint,
        );
      }
    }
  }
}
