import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/game/components/path_waypoints.dart';
import 'package:ludi/rules_engine/capture_logic.dart';
import 'package:ludi/rules_engine/legal_moves.dart';
import 'package:ludi/rules_engine/models/player.dart';

/// Board cell (col, row) under a waypoint.
List<int> cellOf(Vector2 p) => [p.x ~/ cellSize, p.y ~/ cellSize];

/// Neighbouring cells — orthogonal, or diagonal at the track's inner corners.
bool adjacent(Vector2 a, Vector2 b) {
  final ca = cellOf(a);
  final cb = cellOf(b);
  final dc = (ca[0] - cb[0]).abs();
  final dr = (ca[1] - cb[1]).abs();
  return dc <= 1 && dr <= 1 && dc + dr > 0;
}

/// Guards the seam between the rules engine's square numbering and the
/// board drawing — the two drifted apart once already.
void main() {
  test('the shared track is 52 distinct cells in one unbroken loop', () {
    expect(sharedTrackWaypoints.length, trackLength);
    expect(sharedTrackWaypoints.map(cellOf).map((c) => '$c').toSet().length, trackLength);
    for (var i = 0; i < trackLength; i++) {
      final next = (i + 1) % trackLength;
      expect(
        adjacent(sharedTrackWaypoints[i], sharedTrackWaypoints[next]),
        isTrue,
        reason: 'square $i -> $next',
      );
    }
  });

  test('start squares sit on the solid colored cells', () {
    const expected = {
      PlayerColor.red: [1, 6],
      PlayerColor.green: [8, 1],
      PlayerColor.yellow: [13, 8],
      PlayerColor.blue: [6, 13],
    };
    for (final color in PlayerColor.values) {
      expect(cellOf(positionForDistance(color, 1)), expected[color]);
    }
  });

  test('star squares sit on the starred cells', () {
    final cells = starSquares.map((s) => cellOf(sharedTrackWaypoints[s])).toList();
    expect(cells, [
      [6, 2],
      [12, 6],
      [8, 12],
      [2, 8],
    ]);
  });

  test("each color's route runs track -> home column -> finish without jumps", () {
    final trackCells = sharedTrackWaypoints.map(cellOf).map((c) => '$c').toSet();
    for (final color in PlayerColor.values) {
      for (var d = 1; d < maxDistance; d++) {
        expect(
          adjacent(positionForDistance(color, d), positionForDistance(color, d + 1)),
          isTrue,
          reason: '$color $d -> ${d + 1}',
        );
      }
      for (var d = homeStretchStart; d <= maxDistance; d++) {
        expect(
          trackCells.contains('${cellOf(positionForDistance(color, d))}'),
          isFalse,
          reason: '$color home cell $d overlaps the shared track',
        );
      }
    }
  });
}
