import 'capture_logic.dart';
import 'models/game_state.dart';
import 'models/move.dart';
import 'models/token.dart';

/// Last valid distance — the 6th (final) home-stretch square. Reaching it
/// exactly finishes the token; anything past it is an invalid destination
/// (no overshoot, must land exactly).
const int maxDistance = 58;

/// Forward is always evaluated. Backward is only added to the returned list
/// if it lands exactly on a capturable opponent token (see README Section 4).
List<Move> getLegalMoves(Token token, int diceValue, GameState state) {
  final moves = <Move>[];

  // Forward — always allowed if the destination is valid.
  final forwardDist = token.distance + diceValue;
  if (isValidDestination(forwardDist)) {
    moves.add(buildMove(token, forwardDist, isBackward: false, state: state));
  }

  // Backward — ONLY legal if it lands exactly on an opponent token (a kill).
  // No capturable opponent at that square -> backward is not offered at all.
  if (token.state != TokenState.yard) {
    final backwardDist = token.distance - diceValue;
    if (backwardDist >= 1) {
      // can't retreat into yard
      final destSquare = toSharedSquare(token.color, backwardDist);
      final wouldCapture = checkCapture(destSquare, token.color, state);
      if (wouldCapture != null) {
        moves.add(
          buildMove(token, backwardDist, isBackward: true, state: state),
        );
      }
    }
  }

  return moves;
}

/// 1-51 = shared track, 52-57 = private home stretch, 58 = finished exactly.
/// No overshoot past 58 — a roll that would exceed it yields no valid
/// destination.
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
  Token? captured;
  if (newDistance < homeStretchStart) {
    final destSquare = toSharedSquare(token.color, newDistance);
    captured = checkCapture(destSquare, token.color, state);
  }
  return Move(
    token: token,
    newDistance: newDistance,
    isBackward: isBackward,
    capturedToken: captured,
  );
}
