import 'models/game_state.dart';
import 'models/move.dart';
import 'models/token.dart';

/// Forward is always evaluated. Backward is only added to the returned list
/// if it lands exactly on a capturable opponent token (see README Section 4).
///
/// TODO(Vedant): implement in V3.
List<Move> getLegalMoves(Token token, int diceValue, GameState state) {
  throw UnimplementedError('V3 — legal move calculation not yet implemented');
}
