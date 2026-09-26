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
/// may land here safely. Each sits 8 squares past a start square, on the
/// cells the board draws its stars on (design/canvas/SquareMap.dc.html:
/// c6r2, c12r6, c8r12, c2r8).
const List<int> starSquares = [8, 21, 34, 47];

/// True when [distance] is on the shared 52-square loop (1-51) rather than
/// in the yard (0) or the private home stretch (52+).
bool isOnSharedTrack(int distance) =>
    distance >= 1 && distance < homeStretchStart;

/// Maps a token's private [distance] (1-51, shared-track range) to its
/// absolute index on the shared 52-square track (0-51).
int toSharedSquare(PlayerColor color, int distance) {
  assert(isOnSharedTrack(distance), 'distance $distance is off the track');
  final start = startSquares[color]!;
  return (start + distance - 1) % trackLength;
}

/// Safe squares: each color's start square, plus the 4 star squares.
/// No capture happens here.
bool isSafeSquare(int square) {
  return startSquares.values.contains(square) || starSquares.contains(square);
}

/// Every opponent token a [movingColor] token landing on [destSquare] would
/// send back to the yard — empty on a safe square. Normally at most one
/// color occupies a non-safe square, but that color may have several
/// tokens stacked there; all of them are captured together.
List<Token> capturableTokensAt(
  int destSquare,
  PlayerColor movingColor,
  GameState state,
) {
  if (isSafeSquare(destSquare)) return const [];
  return [
    for (final player in state.players)
      if (player.color != movingColor)
        for (final t in player.tokens)
          if (t.state == TokenState.active &&
              isOnSharedTrack(t.distance) &&
              toSharedSquare(t.color, t.distance) == destSquare)
            t,
  ];
}

/// Direction-agnostic capture check — same function serves forward and
/// backward moves. Excludes safe squares. Returns an opponent token
/// occupying [destSquare], or null if none / safe / own color.
Token? checkCapture(int destSquare, PlayerColor movingColor, GameState state) {
  final captured = capturableTokensAt(destSquare, movingColor, state);
  return captured.isEmpty ? null : captured.first;
}
