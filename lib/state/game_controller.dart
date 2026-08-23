import 'package:flutter/foundation.dart';

import '../rules_engine/capture_logic.dart';
import '../rules_engine/models/game_state.dart';
import '../rules_engine/models/move.dart';
import '../rules_engine/models/player.dart';
import '../rules_engine/models/token.dart';
import '../rules_engine/turn_manager.dart' as turn_manager;

/// Shared Contract (README Section 6). Vedant implements this for real;
/// Aditi's Flame/UI layers depend only on this shape.
///
/// Thin bridge over the rules engine — no game logic lives here, it all
/// delegates to `turn_manager.dart`. Notifies listeners after every
/// mutation so Flame components and Flutter widgets can both just listen.
class GameController extends ChangeNotifier {
  GameController({GameState? initialState}) : _state = initialState ?? newGame();

  final GameState _state;

  GameState get state => _state;

  List<Move> get currentLegalMoves => _state.legalMoves;

  /// Rolls the die for the current player and recalculates legal moves.
  /// If nothing is legal, the turn is auto-skipped by the engine.
  void rollDice() {
    turn_manager.rollDice(_state);
    notifyListeners();
  }

  /// Applies [move], fires the animation/capture callbacks for Aditi's
  /// Flame layer, then ends the turn — advancing to the next player or
  /// declaring a winner.
  void selectMove(Move move) {
    final captured = move.capturedToken;

    turn_manager.applyMove(_state, move);
    onMoveAnimated?.call(move);
    if (captured != null) {
      onCapture?.call(captured);
    }
    notifyListeners();

    turn_manager.completeTurn(_state);
    if (_state.phase == GamePhase.gameOver) {
      onGameOver?.call(_state.players[_state.currentPlayerIndex].color);
    }
    notifyListeners();
  }

  // Callbacks Aditi's Flame layer listens to, to trigger animation + sound.
  void Function(Move move)? onMoveAnimated;
  void Function(Token captured)? onCapture;
  void Function(PlayerColor winner)? onGameOver;
}

/// Builds a fresh 4-player game: every token starts in the yard, first
/// player up is red, phase is rolling.
GameState newGame() {
  final players = startSquares.entries
      .map(
        (entry) => Player(
          color: entry.key,
          startSquare: entry.value,
          tokens: List.generate(
            4,
            (i) => Token(id: '${entry.key.name}$i', color: entry.key),
          ),
        ),
      )
      .toList();
  return GameState(players: players);
}
