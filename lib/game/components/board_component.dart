import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../../rules_engine/models/move.dart';
import '../../rules_engine/models/player.dart';
import '../ludi_game.dart';
import '../ludi_theme.dart';
import '../token_painter.dart';
import 'path_waypoints.dart';

/// Renders the board — yards, the 52-square shared track, home columns,
/// the center wedges, and all 8 safe squares (4 colored start squares + 4
/// stars, matching capture_logic.dart's isSafeSquare) — plus the live
/// layer under the tokens: a glow on the active player's yard and the
/// dotted route of a picked token. The markers on reachable squares are
/// MoveHintsComponent children.
///
/// The static board is painted once into a Picture; only the live layer
/// is redrawn each frame. Board-local units: one cell = [cellSize].
///
/// Also the tap target for choosing a move — it hands the tap position to
/// LudiGame, which decides what was meant.
class BoardComponent extends PositionComponent
    with TapCallbacks, HasGameReference<LudiGame> {
  BoardComponent({required this.seated}) : super(size: Vector2.all(boardSize));

  /// Colors with a player this game — the rest get a muted, empty yard.
  final Set<PlayerColor> seated;

  /// Where the layout wants the board; shake offsets are applied on top.
  Vector2 basePosition = Vector2.zero();

  late final Picture _board = _paintStaticBoard();

  /// [_board] rasterized at the current on-screen size. Replaying it as
  /// vectors meant redrawing its blurred drop shadow and ~200 cells every
  /// frame — the biggest avoidable per-frame GPU cost.
  Image? _baked;
  double _bakedPixels = 0;

  /// Room around the board for its drop shadow, board units.
  static const double _shadowMargin = 24;
  double _time = 0;
  double _shake = 0;
  final Random _rng = Random();

  static const Map<String, PlayerColor> _armHome = {
    'top': PlayerColor.green,
    'right': PlayerColor.yellow,
    'bottom': PlayerColor.blue,
    'left': PlayerColor.red,
  };

  /// Start squares (solid) and the direction of travel leaving them.
  static const Map<PlayerColor, (int, int, double)> _startCells = {
    PlayerColor.red: (1, 6, 0),
    PlayerColor.green: (8, 1, pi / 2),
    PlayerColor.yellow: (13, 8, pi),
    PlayerColor.blue: (6, 13, -pi / 2),
  };

  /// Each color's last shared square — the turn into its home column —
  /// and the direction it turns.
  static const Map<PlayerColor, (int, int, double)> _homeEntryCells = {
    PlayerColor.red: (0, 7, 0),
    PlayerColor.green: (7, 0, pi / 2),
    PlayerColor.yellow: (14, 7, pi),
    PlayerColor.blue: (7, 14, -pi / 2),
  };

  /// The 4 mid-arm star squares — additional safe squares beyond each
  /// color's own start (see capture_logic.dart's `starSquares`, abs
  /// indices 8/21/34/47). Four-fold rotationally symmetric around the
  /// board center, same relative spot in every arm.
  static const List<(int, int)> _starCells = [(6, 2), (12, 6), (8, 12), (2, 8)];

  /// Knocks the board (and every token on it) around briefly — capture
  /// impact.
  void shake([double strength = 1]) => _shake = max(_shake, strength);

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    _shake = max(0, _shake - dt * 5);
    final amplitude = 3.2 * _shake * _shake;
    position.setValues(
      basePosition.x + (_rng.nextDouble() - 0.5) * 2 * amplitude,
      basePosition.y + (_rng.nextDouble() - 0.5) * 2 * amplitude,
    );
  }

  // Acts where the finger lifts; a drag or a slide off the board cancels.
  @override
  void onTapUp(TapUpEvent event) => game.onBoardTap(event.localPosition);

  @override
  void render(Canvas canvas) {
    _paintBaked(canvas);
    _paintActiveYard(canvas);
    _paintRoutes(canvas);
  }

  @override
  void onRemove() {
    _baked?.dispose();
    _baked = null;
    super.onRemove();
  }

  // ---------------------------------------------------------------------
  // Static board

  void _paintBaked(Canvas canvas) {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    final pixels = scale.x * (view?.devicePixelRatio ?? 1); // device px per unit
    const extent = boardSize + 2 * _shadowMargin;
    if (_baked == null || (pixels - _bakedPixels).abs() > 0.001) {
      final recorder = PictureRecorder();
      Canvas(recorder)
        ..scale(pixels)
        ..translate(_shadowMargin, _shadowMargin)
        ..drawPicture(_board);
      final picture = recorder.endRecording();
      final side = (extent * pixels).ceil();
      _baked?.dispose();
      _baked = picture.toImageSync(side, side);
      picture.dispose();
      _bakedPixels = pixels;
    }
    final image = _baked!;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(-_shadowMargin, -_shadowMargin, image.width / pixels, image.height / pixels),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  Picture _paintStaticBoard() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final boardRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, boardSize, boardSize),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      boardRRect.shift(const Offset(0, 5)),
      Paint()
        ..color = LudiNeutral.textPrimary.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(boardRRect, Paint()..color = LudiNeutral.boardBase);

    _paintArmCells(canvas);
    _paintCenter(canvas);
    for (final color in PlayerColor.values) {
      _paintYard(canvas, color);
    }
    return recorder.endRecording();
  }

  void _cell(Canvas canvas, int col, int row, Color fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize).deflate(1.1),
        const Radius.circular(4),
      ),
      Paint()..color = fill,
    );
  }

  /// Home lane: the 5 cells nearest the center are tinted (distances
  /// 52-56); the outermost edge cell stays plain — it's shared track (the
  /// color's last shared square, distance 51) and carries an arrow in that
  /// color pointing into its column. Solid safe square: NOT the home
  /// lane — the outer track lane bordering that color's own yard, one cell
  /// in from the board edge, with an arrow along the direction of travel.
  void _paintArmCells(Canvas canvas) {
    for (var r = 0; r < 15; r++) {
      for (var c = 0; c < 15; c++) {
        final inVertical = c >= 6 && c <= 8;
        final inHorizontal = r >= 6 && r <= 8;
        if (inVertical == inHorizontal) continue; // yard corner or center
        _cell(canvas, c, r, _cellFill(c, r));
      }
    }
    for (final entry in _startCells.entries) {
      final (c, r, angle) = entry.value;
      _cell(canvas, c, r, playerPalette[entry.key]!.base);
      _arrow(canvas, c, r, angle, const Color(0xFFFFFFFF));
    }
    for (final entry in _homeEntryCells.entries) {
      final (c, r, angle) = entry.value;
      _arrow(canvas, c, r, angle, playerPalette[entry.key]!.base);
    }
    for (final (c, r) in _starCells) {
      canvas.drawPath(
        starPath(
          Offset((c + 0.5) * cellSize, (r + 0.5) * cellSize),
          outerRadius: 8,
          innerRadius: 3.6,
        ),
        Paint()..color = LudiNeutral.textPrimary.withValues(alpha: 0.28),
      );
    }
  }

  Color _cellFill(int c, int r) {
    PlayerColor? lane;
    if (c == 7 && r >= 1 && r <= 5) lane = _armHome['top'];
    if (c == 7 && r >= 9 && r <= 13) lane = _armHome['bottom'];
    if (r == 7 && c >= 1 && c <= 5) lane = _armHome['left'];
    if (r == 7 && c >= 9 && c <= 13) lane = _armHome['right'];
    return lane == null ? LudiNeutral.trackSquare : playerPalette[lane]!.light;
  }

  /// A chevron arrow centred in cell ([c], [r]) pointing along [angle].
  void _arrow(Canvas canvas, int c, int r, double angle, Color color) {
    canvas.save();
    canvas.translate((c + 0.5) * cellSize, (r + 0.5) * cellSize);
    canvas.rotate(angle);
    canvas.drawPath(
      Path()
        ..moveTo(-3.5, -6)
        ..lineTo(3.5, 0)
        ..lineTo(-3.5, 6),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  /// The center pinwheel — 4 triangles spanning the full center 3x3,
  /// meeting at the board's center point, where finished tokens rest.
  void _paintCenter(Canvas canvas) {
    const cx = boardSize / 2;
    const cy = boardSize / 2;
    const half = 1.5 * cellSize - 1.1;
    const corners = [
      Offset(cx - half, cy - half),
      Offset(cx + half, cy - half),
      Offset(cx + half, cy + half),
      Offset(cx - half, cy + half),
    ];
    const order = [PlayerColor.green, PlayerColor.yellow, PlayerColor.blue, PlayerColor.red];
    for (var i = 0; i < 4; i++) {
      final path = Path()
        ..moveTo(corners[i].dx, corners[i].dy)
        ..lineTo(corners[(i + 1) % 4].dx, corners[(i + 1) % 4].dy)
        ..lineTo(cx, cy)
        ..close();
      canvas.drawPath(path, Paint()..color = playerPalette[order[i]]!.base);
      canvas.drawPath(
        path,
        Paint()
          ..color = LudiNeutral.boardBase
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  /// Yard: a Base-colored panel holding a white tray with 4 sockets —
  /// where tokens wait and where captured tokens fly back to.
  void _paintYard(Canvas canvas, PlayerColor color) {
    final origin = yardOrigin[color]!;
    final palette = playerPalette[color]!;
    final isSeated = seated.contains(color);
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.x, origin.y, 6 * cellSize, 6 * cellSize).deflate(3),
      const Radius.circular(16),
    );
    canvas.drawRRect(panel, Paint()..color = isSeated ? palette.base : LudiNeutral.emptyYard);
    final tray = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.x + 17, origin.y + 17, 110, 110),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      tray.shift(const Offset(0, 1.5)),
      Paint()..color = (isSeated ? palette.deep : LudiNeutral.gridLine).withValues(alpha: 0.5),
    );
    canvas.drawRRect(tray, Paint()..color = LudiNeutral.surface);
    for (var slot = 0; slot < 4; slot++) {
      final center = yardSlotPosition(color, slot).toOffset();
      canvas.drawCircle(
        center,
        14,
        Paint()..color = isSeated ? palette.light : LudiNeutral.boardBackground,
      );
      // The color's mark, faint, so an empty yard still says whose it is
      // without relying on hue.
      if (isSeated) {
        canvas.drawPath(
          markPath(color, center, 5),
          Paint()..color = palette.base.withValues(alpha: 0.45),
        );
      }
      canvas.drawCircle(
        center,
        14,
        Paint()
          ..color = isSeated ? palette.base.withValues(alpha: 0.55) : LudiNeutral.gridLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  // ---------------------------------------------------------------------
  // Live layer

  /// Breathing glow around the yard of whoever's turn it is.
  void _paintActiveYard(Canvas canvas) {
    final color = game.activeColor;
    final origin = yardOrigin[color]!;
    final palette = playerPalette[color]!;
    final pulse = 0.5 + 0.5 * sin(_time * 3.2);
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.x, origin.y, 6 * cellSize, 6 * cellSize).deflate(3),
      const Radius.circular(16),
    );
    // Soft halo from two wide translucent strokes — a blurred stroke looks
    // the same but costs a blur pass every frame.
    for (final (width, alpha) in [(11.0, 0.12), (6.0, 0.22)]) {
      canvas.drawRRect(
        panel,
        Paint()
          ..color = palette.base.withValues(alpha: alpha * (1 + pulse))
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }
    canvas.drawRRect(
      panel,
      Paint()
        ..color = palette.deep
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  /// With a token picked, dots on every square between it and each of its
  /// options.
  void _paintRoutes(Canvas canvas) {
    final picked = game.selectedToken;
    if (!game.canSelect || picked == null) return;
    for (final move in game.controller.currentLegalMoves) {
      if (move.token == picked) _paintRoute(canvas, move);
    }
  }

  /// Dots on every square between a picked token and one of its options.
  void _paintRoute(Canvas canvas, Move move) {
    final from = move.token.distance;
    if (from == 0) return; // leaving the yard is a single jump
    final dot = Paint()..color = playerPalette[move.token.color]!.deep.withValues(alpha: 0.55);
    final route = stepDistances(from, move.newDistance);
    for (final d in route.sublist(1, route.length - 1)) {
      canvas.drawCircle(positionForDistance(move.token.color, d).toOffset(), 2.2, dot);
    }
  }
}
