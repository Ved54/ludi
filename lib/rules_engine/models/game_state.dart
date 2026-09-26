import 'move.dart';
import 'player.dart';

enum GamePhase { rolling, selecting, animating, gameOver }

class GameState {
  GameState({
    required this.players,
    this.currentPlayerIndex = 0,
    this.lastDiceValue = 0,
    List<Move>? legalMoves,
    this.phase = GamePhase.rolling,
    this.bonusRollsRemaining = 0,
    this.lastRoll = 0,
  }) : legalMoves = legalMoves ?? [];

  final List<Player> players;
  int currentPlayerIndex;

  Player get currentPlayer => players[currentPlayerIndex];

  /// The die value driving the *current pending decision* — zeroed when
  /// the turn ends or auto-skips. Game logic reads this.
  int lastDiceValue;

  /// The die face to *display* — set on every roll, never cleared, so the
  /// number a player just rolled stays on screen even when the turn
  /// immediately passes (e.g. a non-6 with every token still in the yard).
  /// UI only; game logic must use [lastDiceValue].
  int lastRoll;

  /// Recalculated each turn.
  List<Move> legalMoves;

  GamePhase phase;

  /// How many extra rolls the current player still has coming before their
  /// turn actually passes — rolling a 6 (even one with no legal move),
  /// capturing, and finishing a token each independently grant one (see
  /// turn_manager.dart), and they stack: a single move can trigger more
  /// than one at once.
  int bonusRollsRemaining;
}
