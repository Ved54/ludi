import 'dart:math';

import 'capture_logic.dart';
import 'dice.dart';
import 'legal_moves.dart';
import 'models/game_state.dart';
import 'models/move.dart';
import 'models/player.dart';
import 'models/token.dart';

/// Rolling this many 6s back to back in one turn forfeits it — classic
/// Ludo's brake on a lucky streak.
const int sixesToForfeit = 3;

/// Rolls the die for the current player, gathers legal moves across all
/// their tokens, and transitions the phase accordingly. Only valid in
/// [GamePhase.rolling].
///
/// If no token has a legal move for this roll, the roll is wasted — same as
/// classic Ludo. A wasted 6 still earns its re-roll, and any bonus rolls
/// already owed are kept; only once none remain does the turn pass.
///
/// The [sixesToForfeit]th 6 in a row doesn't count at all: no move, every
/// bonus roll still owed is lost, and play passes to the next player.
/// Moves made with the earlier 6s stand. (A 6 is the only roll that can
/// both be rolled and pass the turn at once, so the UI can tell a forfeit
/// from `lastRoll == 6` and a change of player.)
void rollDice(GameState state, {Random? random}) {
  _expectPhase(state, GamePhase.rolling, 'roll');

  final diceValue = rollDie(random);
  state.lastDiceValue = diceValue;
  state.lastRoll = diceValue; // display value — survives an auto-skip below
  state.sixesInARow = diceValue == 6 ? state.sixesInARow + 1 : 0;
  if (state.sixesInARow >= sixesToForfeit) {
    advanceTurn(state);
    return;
  }
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
/// a token with a roll of 6 grants two). A streak is only cut short by a
/// third 6 in a row (see [rollDice]).
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

/// Ends the current move. A player whose last token just came home takes
/// the next place in [GameState.finishOrder] and sits out the rest of the
/// game (any bonus rolls they were owed go with them); once only one
/// player is left, they take last place and the game is over. Otherwise,
/// if any bonus rolls are owed, the same player goes again (consuming
/// one); only once none remain does play actually pass to the next
/// player.
void completeTurn(GameState state) {
  _expectPhase(state, GamePhase.animating, 'complete a turn');
  final player = state.currentPlayer;
  if (_allHome(player) && !state.finishOrder.contains(player.color)) {
    state.finishOrder.add(player.color);
    if (state.finishOrder.length >= state.players.length - 1) {
      state.finishOrder.addAll([
        for (final p in state.players)
          if (!state.finishOrder.contains(p.color)) p.color,
      ]);
      state.legalMoves = [];
      state.phase = GamePhase.gameOver;
      return;
    }
    advanceTurn(state);
    return;
  }
  _rollAgainOrPass(state);
}

/// Advances to the next player in turn order who is still playing,
/// resetting per-turn state.
void advanceTurn(GameState state) {
  do {
    state.currentPlayerIndex =
        (state.currentPlayerIndex + 1) % state.players.length;
  } while (state.finishOrder.contains(state.currentPlayer.color));
  state.lastDiceValue = 0;
  state.legalMoves = [];
  state.bonusRollsRemaining = 0;
  state.sixesInARow = 0;
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

bool _allHome(Player player) =>
    player.tokens.every((t) => t.state == TokenState.finished);

void _expectPhase(GameState state, GamePhase expected, String action) {
  if (state.phase != expected) {
    throw StateError('Cannot $action during ${state.phase.name}');
  }
}
