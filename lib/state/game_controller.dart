import 'dart:math';

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
///
/// UI input is untrusted: a roll outside the rolling phase, or a move that
/// isn't one of [currentLegalMoves] (a double tap, a stale move from an
/// earlier roll), is ignored rather than applied.
///
/// With [holdMovesForAnimation], a selected move stops in
/// [GamePhase.animating] — the board already reflects it, but the turn
/// doesn't resolve (bonus roll, next player, winner) and no new input is
/// accepted until the Flame layer calls [completeMove] once its hop and
/// capture animations have played out.
class GameController extends ChangeNotifier {
  GameController({
    GameState? initialState,
    this._random,
    this.holdMovesForAnimation = false,
  }) : _state = initialState ?? newGame();

  final GameState _state;

  /// Injectable dice source so tests can script exact rolls.
  final Random? _random;

  final bool holdMovesForAnimation;

  GameState get state => _state;

  List<Move> get currentLegalMoves => _state.legalMoves;

  /// Rolls the die for the current player and recalculates legal moves.
  /// If nothing is legal, the engine auto-skips (or grants the re-roll a
  /// 6 / pending bonus earns). No-op outside [GamePhase.rolling].
  void rollDice() {
    if (_state.phase != GamePhase.rolling) return;
    turn_manager.rollDice(_state, random: _random);
    notifyListeners();
  }

  /// Applies [move], fires the animation/capture callbacks for Aditi's
  /// Flame layer, then ends the turn — granting a bonus roll, advancing to
  /// the next player, or declaring a winner. No-op unless [move] is one of
  /// [currentLegalMoves] during [GamePhase.selecting].
  void selectMove(Move move) {
    if (_state.phase != GamePhase.selecting ||
        !_state.legalMoves.contains(move)) {
      return;
    }

    final captured = turn_manager.applyMove(_state, move);
    onMoveAnimated?.call(move);
    for (final token in captured) {
      onCapture?.call(token);
    }
    notifyListeners();

    if (!holdMovesForAnimation) completeMove();
  }

  /// Resolves the move left pending in [GamePhase.animating] — granting a
  /// bonus roll, advancing to the next player, or declaring a winner.
  /// Called automatically unless [holdMovesForAnimation] is set. No-op
  /// outside [GamePhase.animating].
  void completeMove() {
    if (_state.phase != GamePhase.animating) return;
    turn_manager.completeTurn(_state);
    if (_state.phase == GamePhase.gameOver) {
      onGameOver?.call(_state.currentPlayer.color);
    }
    notifyListeners();
  }

  // Callbacks Aditi's Flame layer listens to, to trigger animation + sound.
  void Function(Move move)? onMoveAnimated;
  void Function(Token captured)? onCapture;
  void Function(PlayerColor winner)? onGameOver;
}

/// Builds a fresh game for [colors] (2-4 distinct players, all 4 by
/// default): every token starts in the yard, phase is rolling. Turn order
/// always follows the board clockwise (red, green, yellow, blue) whatever
/// order [colors] is given in, starting from the first of them.
GameState newGame({List<PlayerColor> colors = PlayerColor.values}) {
  final playing = colors.toSet();
  if (playing.length < 2 || playing.length != colors.length) {
    throw ArgumentError.value(colors, 'colors', 'need 2-4 distinct colors');
  }
  final players = [
    for (final entry in startSquares.entries)
      if (playing.contains(entry.key))
        Player(
          color: entry.key,
          startSquare: entry.value,
          tokens: List.generate(
            4,
            (i) => Token(id: '${entry.key.name}$i', color: entry.key),
          ),
        ),
  ];
  return GameState(players: players);
}
