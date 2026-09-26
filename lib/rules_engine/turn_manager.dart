import 'dart:math';

import 'capture_logic.dart';
import 'dice.dart';
import 'legal_moves.dart';
import 'models/game_state.dart';
import 'models/move.dart';
import 'models/token.dart';

/// Rolls the die for the current player, gathers legal moves across all
/// their tokens, and transitions the phase accordingly. Only valid in
/// [GamePhase.rolling].
///
/// If no token has a legal move for this roll, the roll is wasted — same as
/// classic Ludo. A wasted 6 still earns its re-roll, and any bonus rolls
/// already owed are kept; only once none remain does the turn pass.
void rollDice(GameState state, {Random? random}) {
  _expectPhase(state, GamePhase.rolling, 'roll');

  final diceValue = rollDie(random);
  state.lastDiceValue = diceValue;
  state.lastRoll = diceValue; // display value — survives an auto-skip below
  state.legalMoves = legalMovesFor(state.currentPlayer, diceValue, state);

  if (state.legalMoves.isNotEmpty) {
    state.phase = GamePhase.selecting;
    return;
  }
  if (diceValue == 6) state.bonusRollsRemaining++;
  _rollAgainOrPass(state);
}

/// Applies [move], which must be one of `state.legalMoves`: updates the
/// moving token's distance/state, sends every opponent token on the
/// destination square back to its yard, and moves the phase to animating —
/// GameController (V6) reacts to this via its onMoveAnimated/onCapture
/// callbacks before calling [completeTurn].
///
/// Returns the captured tokens (empty if none). All opponent tokens on a
/// non-safe square are captured together, so no square is ever left
/// shared by two colors.
///
/// Also tallies this move's bonus rolls onto state.bonusRollsRemaining:
/// rolling a 6, capturing, and finishing a token each grant one,
/// independently — a single move can stack more than one (e.g. finishing
/// a token with a roll of 6 grants two). No cap on chaining these; every
/// 6 grants its bonus regardless of how many were rolled in a row.
List<Token> applyMove(GameState state, Move move) {
  _expectPhase(state, GamePhase.selecting, 'apply a move');
  if (!state.legalMoves.contains(move)) {
    throw ArgumentError.value(move, 'move', 'not one of the legal moves');
  }

  final token = move.token;
  final captured = isOnSharedTrack(move.newDistance)
      ? capturableTokensAt(
          toSharedSquare(token.color, move.newDistance),
          token.color,
          state,
        )
      : const <Token>[];

  token.distance = move.newDistance;
  token.state = stateForDistance(move.newDistance);
  for (final t in captured) {
    t.distance = 0;
    t.state = TokenState.yard;
  }

  if (state.lastDiceValue == 6) state.bonusRollsRemaining++;
  if (captured.isNotEmpty) state.bonusRollsRemaining++;
  if (token.state == TokenState.finished) state.bonusRollsRemaining++;

  state.phase = GamePhase.animating;
  return captured;
}

/// Ends the current move: declares a win if all of the current player's
/// tokens have finished. Otherwise, if any bonus rolls are owed, the same
/// player goes again (consuming one); only once none remain does play
/// actually pass to the next player.
void completeTurn(GameState state) {
  _expectPhase(state, GamePhase.animating, 'complete a turn');
  if (_hasWon(state)) {
    state.legalMoves = [];
    state.phase = GamePhase.gameOver;
    return;
  }
  _rollAgainOrPass(state);
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

void _rollAgainOrPass(GameState state) {
  if (state.bonusRollsRemaining == 0) {
    advanceTurn(state);
    return;
  }
  state.bonusRollsRemaining--;
  state.lastDiceValue = 0;
  state.legalMoves = [];
  state.phase = GamePhase.rolling;
}

bool _hasWon(GameState state) =>
    state.currentPlayer.tokens.every((t) => t.state == TokenState.finished);

void _expectPhase(GameState state, GamePhase expected, String action) {
  if (state.phase != expected) {
    throw StateError('Cannot $action during ${state.phase.name}');
  }
}
