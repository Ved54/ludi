import 'package:flame/game.dart';

import '../../rules_engine/capture_logic.dart' show homeStretchStart, toSharedSquare;
import '../../rules_engine/legal_moves.dart' show maxDistance;
import '../../rules_engine/models/player.dart';
import '../../rules_engine/models/token.dart';

/// Board-local pixel geometry. One cell = [cellSize] logical px; the board
/// is a 15x15 grid, [boardSize] square — matches the A1 design canvas
/// exactly (design/canvas/Main.dc.html), so the visual direction carries
/// over unchanged.
const double cellSize = 24.0;
const double boardSize = 15 * cellSize;

Vector2 _cellCenter(int col, int row) =>
    Vector2((col + 0.5) * cellSize, (row + 0.5) * cellSize);

/// The 52 shared-track cells in board-grid (col, row), ordered by absolute
/// square index (0-51) exactly as `toSharedSquare` numbers them — index 0
/// is red's start (Token.distance 1), matching README/capture_logic.dart's
/// `startSquares[PlayerColor.red] == 0`.
///
/// Derived and verified (not eyeballed): the ring walks each arm's two
/// outer lanes plus the shared center-corner cell that joins them, with a
/// short two-cell hop at each yard corner (skipping over that color's own
/// private home-lane entrance, which is never part of the shared track).
/// See the branch's commit notes for the derivation/verification script.
const List<List<int>> _sharedTrackCells = [
  [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [6, 6], [6, 5], [6, 4], [6, 3],
  [6, 2], [6, 1], [6, 0], [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5],
  [8, 6], [9, 6], [10, 6], [11, 6], [12, 6], [13, 6], [14, 6], [14, 8],
  [13, 8], [12, 8], [11, 8], [10, 8], [9, 8], [8, 8], [8, 9], [8, 10],
  [8, 11], [8, 12], [8, 13], [8, 14], [6, 14], [6, 13], [6, 12], [6, 11],
  [6, 10], [6, 9], [6, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8],
  [0, 6],
];

final List<Vector2> sharedTrackWaypoints = _sharedTrackCells
    .map((cr) => _cellCenter(cr[0], cr[1]))
    .toList(growable: false);

/// distance 52 (index 0, just off the shared loop) -> distance 57 (index 5,
/// touching the center) — 6 cells per color, entirely private.
final Map<PlayerColor, List<Vector2>> homeStretchWaypoints = {
  PlayerColor.red: [for (int c = 0; c <= 5; c++) _cellCenter(c, 7)],
  PlayerColor.green: [for (int r = 0; r <= 5; r++) _cellCenter(7, r)],
  PlayerColor.yellow: [for (int c = 14; c >= 9; c--) _cellCenter(c, 7)],
  PlayerColor.blue: [for (int r = 14; r >= 9; r--) _cellCenter(7, r)],
};

/// Resting spot once a token reaches TokenState.finished — the center-facing
/// tip of that color's own wedge.
final Map<PlayerColor, Vector2> finishedPosition = {
  PlayerColor.red: _cellCenter(6, 7),
  PlayerColor.green: _cellCenter(7, 6),
  PlayerColor.yellow: _cellCenter(8, 7),
  PlayerColor.blue: _cellCenter(7, 8),
};

/// Top-left corner (in board-local px) of each color's 6x6 yard panel.
final Map<PlayerColor, Vector2> yardOrigin = {
  PlayerColor.red: Vector2(0, 0),
  PlayerColor.green: Vector2(9 * cellSize, 0),
  PlayerColor.blue: Vector2(0, 9 * cellSize),
  PlayerColor.yellow: Vector2(9 * cellSize, 9 * cellSize),
};

final List<Vector2> _yardSlotOffsets = [
  Vector2(42, 42),
  Vector2(102, 42),
  Vector2(42, 102),
  Vector2(102, 102),
];

/// One of the 4 token-holding slots inside [color]'s yard panel.
Vector2 yardSlotPosition(PlayerColor color, int slotIndex) {
  final origin = yardOrigin[color]!;
  final offset = _yardSlotOffsets[slotIndex % _yardSlotOffsets.length];
  return origin + offset;
}

/// Board-local pixel position for [color] at [distance] (1-58) — the same
/// state-boundary logic as turn_manager.dart's `_stateForDistance`, so a
/// hypothetical destination (e.g. a Move.newDistance the token hasn't
/// actually reached yet) can be positioned without a live Token object.
Vector2 positionForDistance(PlayerColor color, int distance) {
  if (distance >= maxDistance) return finishedPosition[color]!;
  if (distance >= homeStretchStart) {
    return homeStretchWaypoints[color]![distance - homeStretchStart];
  }
  return sharedTrackWaypoints[toSharedSquare(color, distance)];
}

/// Board-local pixel position for [token], driven entirely by its current
/// distance/state — call this fresh every frame rather than caching it.
Vector2 positionFor(Token token) {
  if (token.state == TokenState.yard) {
    // Token ids are generated as '${color.name}$i', i in 0-3 — see
    // GameController.newGame(). A single trailing digit is a safe
    // assumption given exactly 4 tokens per player.
    final slot = int.parse(token.id.substring(token.id.length - 1));
    return yardSlotPosition(token.color, slot);
  }
  return positionForDistance(token.color, token.distance);
}
