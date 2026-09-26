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
/// Classic Ludo loop, clockwise: 13 cells per arm (outer lane in, the
/// arm's outer-edge middle cell, outer lane out), with a diagonal hop at
/// each inner corner — the center 3x3 is purely the decorative wedge, no
/// token stands on it until it finishes. Each color's last shared square
/// (distance 51) is the outer-edge middle cell of its own arm, straight
/// in front of its home column. Start squares land on the solid cells
/// (0 c1r6, 13 c8r1, 26 c13r8, 39 c6r13) and star squares on the starred
/// cells (8 c6r2, 21 c12r6, 34 c8r12, 47 c2r8) — see
/// design/canvas/SquareMap.dc.html and test/game/path_waypoints_test.dart.
//
// TODO(Aditi): rewritten by Vedant's rules fix — the previous table
// U-turned inside each arm and jumped between arms (and overlapped the home
// lanes) to fit the old engine constants (star squares at start+9, 7-step
// home stretch). The engine now matches the drawn board (stars at start+8,
// home column 52-56 + finish 57), so this is the plain classic loop.
const List<List<int>> _sharedTrackCells = [
  // Left arm, top lane -> diagonal into the top arm.
  [1, 6], [2, 6], [3, 6], [4, 6], [5, 6],
  // Top arm: up the left lane, across the top edge, down the right lane.
  [6, 5], [6, 4], [6, 3], [6, 2], [6, 1], [6, 0], [7, 0],
  [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5],
  // Right arm: out along the top lane, down the edge, back along the bottom.
  [9, 6], [10, 6], [11, 6], [12, 6], [13, 6], [14, 6], [14, 7],
  [14, 8], [13, 8], [12, 8], [11, 8], [10, 8], [9, 8],
  // Bottom arm: down the right lane, across the bottom edge, up the left.
  [8, 9], [8, 10], [8, 11], [8, 12], [8, 13], [8, 14], [7, 14],
  [6, 14], [6, 13], [6, 12], [6, 11], [6, 10], [6, 9],
  // Left arm: out along the bottom lane, up the edge.
  [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8], [0, 7],
  [0, 6],
];

final List<Vector2> sharedTrackWaypoints = _sharedTrackCells
    .map((cr) => _cellCenter(cr[0], cr[1]))
    .toList(growable: false);

/// distance 52 (index 0, first tinted home-column cell) -> distance 56
/// (index 4, touching the center) — 5 cells per color, entirely private.
final Map<PlayerColor, List<Vector2>> homeStretchWaypoints = {
  PlayerColor.red: [for (int c = 1; c <= 5; c++) _cellCenter(c, 7)],
  PlayerColor.green: [for (int r = 1; r <= 5; r++) _cellCenter(7, r)],
  PlayerColor.yellow: [for (int c = 13; c >= 9; c--) _cellCenter(c, 7)],
  PlayerColor.blue: [for (int r = 13; r >= 9; r--) _cellCenter(7, r)],
};

/// Resting spot once a token reaches TokenState.finished (distance 57) —
/// the center-facing tip of that color's own wedge.
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

/// Board-local pixel position for [color] at [distance] (1-57) — the same
/// state-boundary logic as legal_moves.dart's `stateForDistance`, so a
/// hypothetical destination (e.g. a Move.newDistance the token hasn't
/// actually reached yet) can be positioned without a live Token object.
Vector2 positionForDistance(PlayerColor color, int distance) {
  if (distance >= maxDistance) return finishedPosition[color]!;
  if (distance >= homeStretchStart) {
    return homeStretchWaypoints[color]![distance - homeStretchStart];
  }
  return sharedTrackWaypoints[toSharedSquare(color, distance)];
}

/// Which of its yard's 4 slots [token] lives in. Token ids are generated
/// as '${color.name}$i', i in 0-3 — see newGame(). A single trailing digit
/// is a safe assumption given exactly 4 tokens per player.
int yardSlotOf(Token token) => int.parse(token.id.substring(token.id.length - 1));

/// Board-local pixel position for [token], driven entirely by its current
/// distance/state — call this fresh every frame rather than caching it.
Vector2 positionFor(Token token) {
  if (token.state == TokenState.yard) {
    return yardSlotPosition(token.color, yardSlotOf(token));
  }
  return positionForDistance(token.color, token.distance);
}

/// Every distance a token steps on going [from] -> [to], both ends
/// included — one entry per hop, in either direction. Leaving the yard
/// (0 -> 1) is a single jump.
List<int> stepDistances(int from, int to) {
  final step = to >= from ? 1 : -1;
  return [for (var d = from; d != to + step; d += step) d];
}
