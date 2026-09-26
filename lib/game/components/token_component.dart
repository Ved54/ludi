import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../rules_engine/models/token.dart';
import '../effects/move_tween.dart';
import '../ludi_game.dart';
import '../ludi_theme.dart';
import '../token_painter.dart';

/// Renders one token (A1's pawn) and animates it. Add as a child of
/// BoardComponent so board-local coordinates line up directly.
///
/// The rules engine moves a token instantly; this component shows it
/// arriving. [shownDistance] is where the token *appears* to be — it only
/// catches up with the engine's distance when LudiGame plays the move, so
/// a captured token keeps standing on its square until it is actually hit.
/// At rest the token eases toward [restPosition]/[restScale], which
/// LudiGame recomputes each frame so tokens sharing a square fan out
/// instead of hiding each other.
class TokenComponent extends PositionComponent with HasGameReference<LudiGame> {
  TokenComponent({required this.token})
    : shownDistance = token.distance,
      super(size: Vector2(24, 30), anchor: const Anchor(0.5, 0.8));

  final Token token;

  /// Distance currently on screen (see class doc).
  int shownDistance;

  Vector2 restPosition = Vector2.zero();
  double restScale = 1;

  HopPath? _hop;
  Completer<void>? _hopDone;
  void Function()? _onLand;
  double _spinTurns = 0;

  double _lift = 0;
  double _spin = 0;
  double _impact = 0; // landing squash, decays to 0
  double _selectable = 0; // eased 0-1
  final double _phase = Random().nextDouble() * 2 * pi;
  double _time = 0;
  bool _placed = false;

  bool get isAnimating => _hop != null;

  /// Draw order while in the air — above every token on the ground (which
  /// LudiGame layers by screen depth, 100 + y) and the capture burst, so a
  /// hop or a knock-home never passes *under* a token it flies over.
  static const int airbornePriority = 1000;

  /// The pawn's visual middle, for hit-testing taps.
  Vector2 get bodyCenter => position - Vector2(0, 10 * scale.y);

  /// Hops through [points] (ground positions, starting at the next square)
  /// one square per [step] seconds, calling [onLand] after each landing.
  /// [spinTurns] tumbles the pawn on the way (a knocked-out token).
  Future<void> hopThrough(
    List<Vector2> points, {
    double step = LudiMotion.hopStep,
    double height = LudiMotion.hopHeight,
    double spinTurns = 0,
    void Function()? onLand,
  }) {
    _hopDone?.complete();
    priority = airbornePriority;
    _hop = HopPath([position.clone(), ...points], stepDuration: step, height: height);
    _hopDone = Completer<void>();
    _onLand = onLand;
    _spinTurns = spinTurns;
    return _hopDone!.future;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (!_placed) {
      position.setFrom(restPosition);
      scale.setAll(restScale);
      _placed = true;
    }

    final selectable = game.movableTokens.contains(token);
    _selectable += ((selectable ? 1 : 0) - _selectable) * min(1, dt * 10);
    _impact = max(0, _impact - dt * 7);

    final hop = _hop;
    if (hop != null) {
      final landings = hop.advance(dt);
      position.setFrom(hop.position);
      _lift = hop.lift;
      _spin = _spinTurns * 2 * pi * hop.progress;
      if (landings > 0) {
        _impact = 1;
        _onLand?.call();
      }
      // Grow back to full size in flight, even if it left a stack.
      scale.setAll(scale.x + (1 - scale.x) * min(1, dt * 12));
      if (hop.isDone) {
        _hop = null;
        _spin = 0;
        final done = _hopDone;
        _hopDone = null;
        done?.complete();
      }
      return;
    }

    final ease = min(1.0, dt * 14);
    position.add((restPosition - position) * ease);
    scale.setAll(scale.x + (restScale - scale.x) * ease);
    // Movable tokens bob gently — "pick me".
    final bob = (1.5 + 1.5 * sin(_time * 6.5 + _phase)) * _selectable;
    _lift += (bob - _lift) * min(1, dt * 16);
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(size.x * anchor.x, size.y * anchor.y); // ground point

    if (_selectable > 0.01) _paintSelectableRing(canvas);
    if (game.selectedToken == token) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 24, height: 9),
        Paint()
          ..color = playerPalette[token.color]!.deep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }

    final airborne = _hop?.airborne ?? 0;
    paintPawn(
      canvas,
      token.color,
      lift: _lift,
      squashX: 1 - 0.06 * airborne + 0.14 * _impact,
      squashY: 1 + 0.08 * airborne - 0.16 * _impact,
      spin: _spin,
    );
    canvas.restore();
  }

  /// Expanding, fading ellipse under a movable token, looping.
  void _paintSelectableRing(Canvas canvas) {
    final deep = playerPalette[token.color]!.deep;
    final t = (_time * 1.1 + _phase / (2 * pi)) % 1;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 18 + 12 * t, height: 7 + 4.5 * t),
      Paint()
        ..color = deep.withValues(alpha: (1 - t) * 0.85 * _selectable)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 20, height: 7.5),
      Paint()..color = playerPalette[token.color]!.base.withValues(alpha: 0.35 * _selectable),
    );
  }
}
