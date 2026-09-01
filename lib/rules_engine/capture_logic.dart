import 'models/game_state.dart';
import 'models/player.dart';
import 'models/token.dart';

const int trackLength = 52;

/// Token.distance >= this is private home stretch — off the shared track,
/// never capturable.
const int homeStretchStart = 52;

/// Fixed board offsets — each color's entry point into the shared track,
/// spaced a quarter of the track apart (classic Ludo layout).
const Map<PlayerColor, int> startSquares = {
  PlayerColor.red: 0,
  PlayerColor.green: 13,
  PlayerColor.yellow: 26,
  PlayerColor.blue: 39,
};

/// The 4 additional safe squares beyond each color's own start — classic
/// Ludo's 8-safe-square board (A1 design: design/visual_style_guide.md).
/// Unlike [startSquares], these aren't tied to any one color; any token
/// may land here safely. Spaced a quarter of the track apart, offset 9
/// ahead of each start square (see board/A2 for the visual layout).
const List<int> starSquares = [9, 22, 35, 48];

/// Maps a token's private [distance] (1-51, shared-track range) to its
/// absolute index on the shared 52-square track (0-51).
int toSharedSquare(PlayerColor color, int distance) {
  final start = startSquares[color]!;
  return (start + distance - 1) % trackLength;
}

/// Safe squares: each color's start square, plus the 4 star squares.
/// No capture happens here.
bool isSafeSquare(int square) {
  return startSquares.values.contains(square) || starSquares.contains(square);
}

/// Direction-agnostic capture check — same function serves forward and
/// backward moves. Excludes safe squares. Returns the opponent token
/// occupying [destSquare], or null if none / safe / own color.
Token? checkCapture(int destSquare, PlayerColor movingColor, GameState state) {
  if (isSafeSquare(destSquare)) return null;
  for (final player in state.players) {
    if (player.color == movingColor) continue;
    for (final t in player.tokens) {
      if (t.state == TokenState.active &&
          t.distance >= 1 &&
          t.distance < homeStretchStart &&
          toSharedSquare(t.color, t.distance) == destSquare) {
        return t; // gets sent back to yard
      }
    }
  }
  return null;
}
