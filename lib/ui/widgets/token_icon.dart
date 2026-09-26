import 'package:flutter/widgets.dart';

import '../../game/token_painter.dart';
import '../../rules_engine/models/player.dart';

/// The board's pawn as a Flutter widget — same painter, any size.
class TokenIcon extends StatelessWidget {
  const TokenIcon({super.key, required this.color, this.size = 32});

  final PlayerColor color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PawnPainter(color)),
    );
  }
}

class _PawnPainter extends CustomPainter {
  _PawnPainter(this.color);

  final PlayerColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / (pawnHeight + 6);
    canvas.translate(size.width / 2, size.height - 3 * scale);
    canvas.scale(scale);
    paintPawn(canvas, color);
  }

  @override
  bool shouldRepaint(_PawnPainter oldDelegate) => oldDelegate.color != color;
}
