import 'dart:ui';

import 'package:flame/components.dart';

import '../../rules_engine/models/token.dart';
import '../ludi_theme.dart';
import 'path_waypoints.dart';

/// Renders one token as a flat, two-tone pawn (A1's shape, reused
/// verbatim) at its current board position. Add as a child of
/// BoardComponent so [positionFor]'s board-local coordinates line up
/// directly with no extra offset math.
///
/// Position is recomputed from [token] every frame rather than cached —
/// there's no move/capture animation yet (that's A4); this just always
/// snaps to wherever the token's current distance/state says it is.
class TokenComponent extends PositionComponent {
  TokenComponent({required this.token})
      : super(size: Vector2(20, 30), anchor: Anchor.center);

  final Token token;

  @override
  void update(double dt) {
    super.update(dt);
    position.setFrom(positionFor(token));
  }

  @override
  void render(Canvas canvas) {
    final palette = playerPalette[token.color]!;
    final body = Paint()..color = palette.base;

    canvas.drawOval(
      const Rect.fromLTWH(2, 25.5, 16, 5),
      Paint()..color = palette.deep.withValues(alpha: 0.35),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 19, 16, 8),
        const Radius.circular(4),
      ),
      body,
    );

    canvas.drawPath(
      Path()
        ..moveTo(6, 19)
        ..lineTo(8, 11)
        ..lineTo(12, 11)
        ..lineTo(14, 19)
        ..close(),
      body,
    );

    canvas.drawCircle(const Offset(10, 8), 6, body);
  }
}
