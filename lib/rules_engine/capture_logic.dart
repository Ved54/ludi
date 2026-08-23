import 'models/game_state.dart';
import 'models/player.dart';
import 'models/token.dart';

/// Direction-agnostic capture check. Excludes safe squares.
///
/// TODO(Vedant): implement in V4.
Token? checkCapture(int destSquare, PlayerColor movingColor, GameState state) {
  throw UnimplementedError('V4 — capture logic not yet implemented');
}

/// TODO(Vedant): implement in V4.
bool isSafeSquare(int square) {
  throw UnimplementedError('V4 — capture logic not yet implemented');
}
