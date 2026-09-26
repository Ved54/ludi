import 'capture_logic.dart';
import 'models/game_state.dart';
import 'models/move.dart';
import 'models/player.dart';
import 'models/token.dart';

/// Finish distance — the home triangle, one step past the last of the 5
/// home-column squares (52-56). Reaching it exactly finishes the token;
/// anything past it is an invalid destination (no overshoot, must land
/// exactly). README Section 3: the private stretch is 52-57, 6 steps.
const int maxDistance = 57;

/// The [TokenState] a token at [distance] is in: 0 = yard, 1-51 = shared
/// track, 52-56 = home column, 57 = finished.
TokenState stateForDistance(int distance) {
  if (distance <= 0) return TokenState.yard;
  if (distance >= maxDistance) return TokenState.finished;
  if (distance >= homeStretchStart) return TokenState.homeStretch;
  return TokenState.active;
}

/// Every legal move [player] has for a roll of [diceValue], across all
/// of their tokens.
List<Move> legalMovesFor(Player player, int diceValue, GameState state) => [
  for (final token in player.tokens) ...getLegalMoves(token, diceValue, state),
];

/// Forward is always evaluated (except a yard token, which only ever gets
/// ONE possible move — see below). Backward is only added to the returned
/// list if it lands exactly on a capturable opponent token (see README
/// Section 4).
List<Move> getLegalMoves(Token token, int diceValue, GameState state) {
  if (token.state == TokenState.finished) return const [];

  // A yard token can only leave on a roll of exactly 6 — entering places it
  // on its own start square (distance 1, the color's safe square), using
  // the whole roll; it does not also advance further that same turn. No
  // other move (forward-by-N, backward) exists for a yard token.
  if (token.state == TokenState.yard) {
    if (diceValue == 6) {
      return [buildMove(token, 1, isBackward: false, state: state)];
    }
    return const [];
  }

  final moves = <Move>[];

  // Forward — always allowed if the destination is valid.
  final forwardDist = token.distance + diceValue;
  if (isValidDestination(forwardDist)) {
    moves.add(buildMove(token, forwardDist, isBackward: false, state: state));
  }

  // Backward — ONLY legal if it lands exactly on an opponent token (a kill).
  // No capturable opponent at that square -> backward is not offered at all.
  // The destination must be on the shared track: distance 0 is the yard
  // (can't retreat into it), and a home-stretch square can never hold an
  // opponent, so a backward step that stays inside the home column is
  // never a kill.
  final backwardDist = token.distance - diceValue;
  if (isOnSharedTrack(backwardDist)) {
    final backward = buildMove(
      token,
      backwardDist,
      isBackward: true,
      state: state,
    );
    if (backward.capturedToken != null) moves.add(backward);
  }

  return moves;
}

/// 1-51 = shared track, 52-56 = private home column, 57 = finished
/// exactly. No overshoot past 57 — a roll that would exceed it yields no
/// valid destination.
bool isValidDestination(int distance) {
  return distance >= 1 && distance <= maxDistance;
}

/// Builds a [Move] for [token] moving to [newDistance]. Populates
/// [Move.capturedToken] for either direction — a forward move can land on
/// and capture an opponent same as backward can.
Move buildMove(
  Token token,
  int newDistance, {
  required bool isBackward,
  required GameState state,
}) {
  final captured = isOnSharedTrack(newDistance)
      ? checkCapture(toSharedSquare(token.color, newDistance), token.color, state)
      : null;
  return Move(
    token: token,
    newDistance: newDistance,
    isBackward: isBackward,
    capturedToken: captured,
  );
}
