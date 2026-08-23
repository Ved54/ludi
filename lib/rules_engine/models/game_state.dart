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
  }) : legalMoves = legalMoves ?? [];

  final List<Player> players;
  int currentPlayerIndex;
  int lastDiceValue;

  /// Recalculated each turn.
  List<Move> legalMoves;

  GamePhase phase;
}
