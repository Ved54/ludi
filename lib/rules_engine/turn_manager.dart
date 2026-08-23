import 'dart:math';

import 'capture_logic.dart';
import 'dice.dart';
import 'legal_moves.dart';
import 'models/game_state.dart';
import 'models/move.dart';
import 'models/player.dart';
import 'models/token.dart';

/// Rolls the die for the current player, gathers legal moves across all
/// their (non-finished) tokens, and transitions the phase accordingly.
///
/// If no token has a legal move for this roll, the roll is wasted — same as
/// classic Ludo — and the turn is skipped automatically via [advanceTurn].
void rollDice(GameState state, {Random? random}) {
  final player = state.players[state.currentPlayerIndex];
  final diceValue = rollDie(random);
  state.lastDiceValue = diceValue;

  final moves = <Move>[];
  for (final token in player.tokens) {
    if (token.state == TokenState.finished) continue;
    moves.addAll(getLegalMoves(token, diceValue, state));
  }
  state.legalMoves = moves;

  if (moves.isEmpty) {
    advanceTurn(state);
  } else {
    state.phase = GamePhase.selecting;
  }
}

/// Applies [move]: updates the moving token's distance/state, sends a
/// captured opponent token back to its yard, and moves the phase to
/// animating — GameController (V6) reacts to this via its
/// onMoveAnimated/onCapture callbacks before calling [completeTurn].
void applyMove(GameState state, Move move) {
  final token = move.token;
  token.distance = move.newDistance;
  token.state = _stateForDistance(move.newDistance);

  final captured = move.capturedToken;
  if (captured != null) {
    captured.distance = 0;
    captured.state = TokenState.yard;
  }

  state.phase = GamePhase.animating;
}

/// Ends the current player's turn: declares a win if all of their tokens
/// have finished, otherwise clears the roll/legal-moves and hands play to
/// the next player.
void completeTurn(GameState state) {
  final player = state.players[state.currentPlayerIndex];
  if (_hasWon(player)) {
    state.phase = GamePhase.gameOver;
    return;
  }
  advanceTurn(state);
}

/// Advances to the next player in turn order, resetting per-turn state.
void advanceTurn(GameState state) {
  state.currentPlayerIndex =
      (state.currentPlayerIndex + 1) % state.players.length;
  state.lastDiceValue = 0;
  state.legalMoves = [];
  state.phase = GamePhase.rolling;
}

TokenState _stateForDistance(int distance) {
  if (distance <= 0) return TokenState.yard;
  if (distance >= maxDistance) return TokenState.finished;
  if (distance >= homeStretchStart) return TokenState.homeStretch;
  return TokenState.active;
}

bool _hasWon(Player player) {
  return player.tokens.every((t) => t.state == TokenState.finished);
}
