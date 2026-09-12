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
  state.lastRoll = diceValue; // display value — survives an auto-skip below

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
///
/// Also tallies this move's bonus rolls onto state.bonusRollsRemaining:
/// rolling a 6, capturing, and finishing a token each grant one,
/// independently — a single move can stack more than one (e.g. finishing
/// a token with a roll of 6 grants two). No cap on chaining these; every
/// 6 grants its bonus regardless of how many were rolled in a row.
void applyMove(GameState state, Move move) {
  final token = move.token;
  token.distance = move.newDistance;
  token.state = _stateForDistance(move.newDistance);

  final captured = move.capturedToken;
  if (captured != null) {
    captured.distance = 0;
    captured.state = TokenState.yard;
  }

  var bonus = 0;
  if (state.lastDiceValue == 6) bonus++;
  if (captured != null) bonus++;
  if (token.state == TokenState.finished) bonus++;
  state.bonusRollsRemaining += bonus;

  state.phase = GamePhase.animating;
}

/// Ends the current player's turn: declares a win if all of their tokens
/// have finished. Otherwise, if this move earned any bonus rolls, the same
/// player goes again (consuming one); only once none remain does play
/// actually pass to the next player.
void completeTurn(GameState state) {
  final player = state.players[state.currentPlayerIndex];
  if (_hasWon(player)) {
    state.phase = GamePhase.gameOver;
    return;
  }
  if (state.bonusRollsRemaining > 0) {
    state.bonusRollsRemaining--;
    state.lastDiceValue = 0;
    state.legalMoves = [];
    state.phase = GamePhase.rolling;
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
  state.bonusRollsRemaining = 0;
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
