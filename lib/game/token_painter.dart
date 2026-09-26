import 'dart:math';
import 'dart:ui';

import '../rules_engine/models/player.dart';
import 'ludi_theme.dart';

/// The one pawn silhouette (style guide section 4), drawn standing on the
/// origin — the "ground point" — and about [pawnHeight] units tall. Shared
/// by the Flame board and Flutter widgets so the token looks identical
/// everywhere.
const double pawnHeight = 24;

final Path _silhouette = _buildSilhouette();

Path _buildSilhouette() {
  final base = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-8, -6.5, 16, 7),
        const Radius.circular(3.5),
      ),
    );
  final body = Path()
    ..moveTo(-5, -6)
    ..quadraticBezierTo(-3.4, -10.5, -2.6, -14.5)
    ..lineTo(2.6, -14.5)
    ..quadraticBezierTo(3.4, -10.5, 5, -6)
    ..close();
  final collar = Path()
    ..addOval(Rect.fromCenter(center: const Offset(0, -14.5), width: 10, height: 3.4));
  final head = Path()
    ..addOval(Rect.fromCircle(center: const Offset(0, -18.2), radius: 5.8));
  return [body, collar, head].fold(
    base,
    (merged, part) => Path.combine(PathOperation.union, merged, part),
  );
}

/// Paints a pawn of [color]. [lift] raises the body off its ground shadow
/// (hops), [squashX]/[squashY] deform it around the ground point (landing
/// squash, take-off stretch), and [spin] rotates it (knocked tokens).
void paintPawn(
  Canvas canvas,
  PlayerColor color, {
  double lift = 0,
  double squashX = 1,
  double squashY = 1,
  double spin = 0,
  double opacity = 1,
  bool shadow = true,
}) {
  final palette = playerPalette[color]!;

  if (shadow) {
    final shrink = 1 - (lift / 60).clamp(0.0, 0.6);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 17 * shrink, height: 5.5 * shrink),
      Paint()
        ..color = LudiNeutral.textPrimary.withValues(alpha: 0.22 * shrink * opacity),
    );
  }

  canvas.save();
  canvas.translate(0, -lift);
  if (spin != 0) {
    canvas.translate(0, -pawnHeight / 2);
    canvas.rotate(spin);
    canvas.translate(0, pawnHeight / 2);
  }
  canvas.scale(squashX, squashY);

  // White halo keeps the pawn readable on any cell, including its own
  // color's start square and home column.
  canvas.drawPath(
    _silhouette,
    Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawPath(_silhouette, Paint()..color = palette.base.withValues(alpha: opacity));

  // Deep-colored skirt and a small specular dot — depth without gradients.
  canvas.save();
  canvas.clipPath(_silhouette);
  canvas.drawRect(
    const Rect.fromLTWH(-9, -3.2, 18, 4),
    Paint()..color = palette.deep.withValues(alpha: 0.9 * opacity),
  );
  canvas.restore();
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(-2, -20.2), width: 3.6, height: 2.6),
    Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55 * opacity),
  );

  canvas.drawPath(
    _silhouette,
    Paint()
      ..color = palette.deep.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.restore();
}

/// A 5-point star centred on [center] — safe-square marker.
Path starPath(Offset center, {required double outerRadius, required double innerRadius}) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final radius = i.isEven ? outerRadius : innerRadius;
    final angle = -pi / 2 + (pi / 5) * i;
    final point = Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));
    i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
  }
  return path..close();
}
