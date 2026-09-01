import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../rules_engine/models/player.dart';
import '../../state/game_controller.dart';
import '../ludi_theme.dart';
import 'path_waypoints.dart';

/// Renders the static board — yards, the 52-square shared track, home
/// lanes, the center wedge, and all 8 real safe squares (4 colored start
/// squares + 4 star squares, matching capture_logic.dart's isSafeSquare)
/// — plus a live highlight on whichever squares are legal destinations
/// this turn.
///
/// Reads [controller].state fresh every frame (Flame re-renders every
/// frame regardless), so it needs no manual invalidation when the
/// GameController notifies listeners.
class BoardComponent extends PositionComponent {
  BoardComponent({required this.controller})
      : super(size: Vector2.all(boardSize));

  final GameController controller;

  static const Map<String, PlayerColor> _armHome = {
    'top': PlayerColor.green,
    'right': PlayerColor.yellow,
    'bottom': PlayerColor.blue,
    'left': PlayerColor.red,
  };

  /// The 4 mid-arm star squares — additional safe squares beyond each
  /// color's own start (see capture_logic.dart's `starSquares`, abs
  /// indices 9/22/35/48). Four-fold rotationally symmetric around the
  /// board center, same relative spot in every arm.
  static const List<List<int>> _starCells = [
    [6, 2], [12, 6], [8, 12], [2, 8],
  ];

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, boardSize, boardSize),
      Paint()..color = LudiNeutral.boardBackground,
    );
    _paintArmCells(canvas);
    _paintCenterWedges(canvas);
    _paintStarSquares(canvas);
    _paintYards(canvas);
    _paintLegalMoveHighlights(canvas);
  }

  void _drawCell(Canvas canvas, int col, int row, Color fill) {
    final rect = Rect.fromLTWH(
      col * cellSize,
      row * cellSize,
      cellSize,
      cellSize,
    );
    canvas.drawRect(rect, Paint()..color = fill);
    canvas.drawRect(
      rect,
      Paint()
        ..color = LudiNeutral.gridLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// Home lane: 6 cells (edge -> center); the 5 nearest the center are
  /// tinted, the outermost (distance 52, still mid-transition) stays
  /// plain. Solid safe square: NOT the home lane — the outer track lane
  /// bordering that color's own yard, one cell in from the board edge.
  void _paintArmCells(Canvas canvas) {
    for (int r = 0; r < 6; r++) {
      for (int c = 6; c <= 8; c++) {
        var fill = LudiNeutral.trackSquare;
        if (c == 7 && r != 0) fill = playerPalette[_armHome['top']]!.light;
        if (c == 8 && r == 1) fill = playerPalette[_armHome['top']]!.base;
        _drawCell(canvas, c, r, fill);
      }
    }
    for (int r = 9; r < 15; r++) {
      for (int c = 6; c <= 8; c++) {
        var fill = LudiNeutral.trackSquare;
        if (c == 7 && r != 14) fill = playerPalette[_armHome['bottom']]!.light;
        if (c == 6 && r == 13) fill = playerPalette[_armHome['bottom']]!.base;
        _drawCell(canvas, c, r, fill);
      }
    }
    for (int c = 0; c < 6; c++) {
      for (int r = 6; r <= 8; r++) {
        var fill = LudiNeutral.trackSquare;
        if (r == 7 && c != 0) fill = playerPalette[_armHome['left']]!.light;
        if (r == 6 && c == 1) fill = playerPalette[_armHome['left']]!.base;
        _drawCell(canvas, c, r, fill);
      }
    }
    for (int c = 9; c < 15; c++) {
      for (int r = 6; r <= 8; r++) {
        var fill = LudiNeutral.trackSquare;
        if (r == 7 && c != 14) fill = playerPalette[_armHome['right']]!.light;
        if (r == 8 && c == 13) fill = playerPalette[_armHome['right']]!.base;
        _drawCell(canvas, c, r, fill);
      }
    }
  }

  /// The center pinwheel — 4 triangles spanning the full center 3x3
  /// corner-to-corner, meeting at the board's center point. This covers
  /// the 3x3's 4 corner cells entirely (matching A1's design and how
  /// classic Ludo boards render it): those corners ARE real, landable
  /// track squares underneath — tokens still render on top of the wedge
  /// when passing through — they're just not drawn as a separate visible
  /// square the way ordinary track cells are.
  void _paintCenterWedges(Canvas canvas) {
    const cx = boardSize / 2;
    const cy = boardSize / 2;
    const half = 1.5 * cellSize; // half the center 3x3's width

    final wedges = <PlayerColor, Path>{
      _armHome['top']!: Path()
        ..moveTo(cx - half, cy - half)
        ..lineTo(cx + half, cy - half)
        ..lineTo(cx, cy)
        ..close(),
      _armHome['right']!: Path()
        ..moveTo(cx + half, cy - half)
        ..lineTo(cx + half, cy + half)
        ..lineTo(cx, cy)
        ..close(),
      _armHome['bottom']!: Path()
        ..moveTo(cx + half, cy + half)
        ..lineTo(cx - half, cy + half)
        ..lineTo(cx, cy)
        ..close(),
      _armHome['left']!: Path()
        ..moveTo(cx - half, cy + half)
        ..lineTo(cx - half, cy - half)
        ..lineTo(cx, cy)
        ..close(),
    };
    for (final entry in wedges.entries) {
      canvas.drawPath(
        entry.value,
        Paint()..color = playerPalette[entry.key]!.base,
      );
    }
  }

  /// The 4 star squares (see [_starCells]) — plain track cells otherwise,
  /// marked safe with a small star icon, same treatment as classic Ludo.
  void _paintStarSquares(Canvas canvas) {
    final paint = Paint()
      ..color = LudiNeutral.textPrimary.withValues(alpha: 0.4);
    for (final cr in _starCells) {
      final center = Offset(
        (cr[0] + 0.5) * cellSize,
        (cr[1] + 0.5) * cellSize,
      );
      canvas.drawPath(_starPath(center, outerRadius: 7, innerRadius: 3), paint);
    }
  }

  Path _starPath(Offset center, {required double outerRadius, required double innerRadius}) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final radius = i.isEven ? outerRadius : innerRadius;
      final angle = -pi / 2 + (pi / 5) * i;
      final point = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    path.close();
    return path;
  }

  void _paintYards(Canvas canvas) {
    final currentColor =
        controller.state.players[controller.state.currentPlayerIndex].color;

    for (final color in PlayerColor.values) {
      final origin = yardOrigin[color]!;
      final palette = playerPalette[color]!;

      final panelRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.x, origin.y, 6 * cellSize, 6 * cellSize),
        const Radius.circular(16),
      );
      canvas.drawRRect(panelRRect, Paint()..color = palette.light);

      final trayRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.x + 18, origin.y + 18, 108, 108),
        const Radius.circular(10),
      );
      canvas.drawRRect(trayRRect, Paint()..color = LudiNeutral.trackSquare);

      if (color == currentColor) {
        canvas.drawRRect(
          panelRRect,
          Paint()
            ..color = palette.deep
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }
    }
  }

  /// Live from GameController.currentLegalMoves — a subtle ring on every
  /// square the current player could move to this turn.
  void _paintLegalMoveHighlights(Canvas canvas) {
    for (final move in controller.currentLegalMoves) {
      final pos = positionForDistance(move.token.color, move.newDistance);
      final palette = playerPalette[move.token.color]!;
      canvas.drawCircle(
        Offset(pos.x, pos.y),
        cellSize * 0.42,
        Paint()
          ..color = palette.deep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }
}
