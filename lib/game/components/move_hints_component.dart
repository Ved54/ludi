import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../ludi_game.dart';
import '../ludi_theme.dart';
import 'path_waypoints.dart';

/// Markers on the squares the current roll can reach. When a token with
/// several options is picked, only its options show; a marker being
/// previewed (tapped once, see LudiGame.armedMove) is drawn larger.
///
/// Two layers on the board, either side of the tokens:
///
/// - [MoveHintsComponent.landings] — a dot ring on each plain landing
///   square, *under* the tokens. A token already standing there (your
///   own, or anyone's on a safe square) covers it rather than wearing a
///   target it can't be.
/// - [MoveHintsComponent.targets] — a rotating crosshair on each capture,
///   *over* the tokens: the victim really is the target.
class MoveHintsComponent extends Component with HasGameReference<LudiGame> {
  MoveHintsComponent.landings() : _captures = false, super(priority: 50);
  MoveHintsComponent.targets() : _captures = true, super(priority: 700);

  final bool _captures;
  double _time = 0;

  @override
  void update(double dt) => _time += dt;

  @override
  void render(Canvas canvas) {
    if (!game.canSelect) return;
    final picked = game.selectedToken;
    for (final move in game.controller.currentLegalMoves) {
      if (picked != null && move.token != picked) continue;
      if ((move.capturedToken != null) != _captures) continue;
      final at = positionForDistance(move.token.color, move.newDistance).toOffset();
      final palette = playerPalette[move.token.color]!;
      final armed = move == game.armedMove;
      _captures
          ? _paintCrosshair(canvas, at, palette.deep, armed: armed)
          : _paintMarker(canvas, at, palette, armed: armed);
    }
  }

  void _paintMarker(Canvas canvas, Offset at, PlayerPalette palette, {required bool armed}) {
    final pulse = 0.5 + 0.5 * sin(_time * 5);
    final radius = armed ? 10.5 + 1.5 * pulse : 7.5 + pulse;
    canvas.drawCircle(at, radius, Paint()..color = palette.base.withValues(alpha: armed ? 0.55 : 0.25));
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..color = palette.deep
        ..style = PaintingStyle.stroke
        ..strokeWidth = armed ? 2.4 : 1.8,
    );
    canvas.drawCircle(at, armed ? 3 : 2.4, Paint()..color = palette.deep);
  }

  /// Rotating crosshair — this move lands a kill (forward or backward).
  void _paintCrosshair(Canvas canvas, Offset at, Color color, {required bool armed}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = armed ? 2.6 : 2
      ..strokeCap = StrokeCap.round;
    final pulse = 0.5 + 0.5 * sin(_time * 6);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (armed) canvas.drawCircle(Offset.zero, 12, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawCircle(Offset.zero, (armed ? 15 : 13) + 1.5 * pulse, paint..color = color.withValues(alpha: 0.35));
    paint.color = color;
    canvas.rotate(_time * 1.6);
    canvas.drawCircle(Offset.zero, 10, paint);
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(const Offset(0, -13.5), const Offset(0, -7), paint);
      canvas.rotate(pi / 2);
    }
    canvas.restore();
  }
}
