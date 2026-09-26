import 'dart:math';

import 'package:ludi/rules_engine/capture_logic.dart';
import 'package:ludi/rules_engine/legal_moves.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';

/// Deterministic dice: yields [rolls] in order (cycling), so a test states
/// exactly what was rolled instead of hunting for a lucky seed.
class ScriptedRandom implements Random {
  ScriptedRandom(this.rolls);

  final List<int> rolls;
  int _next = 0;

  @override
  int nextInt(int max) => rolls[_next++ % rolls.length] - 1;

  @override
  double nextDouble() => throw UnsupportedError('dice only use nextInt');

  @override
  bool nextBool() => throw UnsupportedError('dice only use nextInt');
}

/// A token of [color] at [distance], with the matching state.
Token tokenAt(PlayerColor color, int distance, {String? id}) => Token(
  id: id ?? '${color.name}-$distance',
  color: color,
  distance: distance,
  state: stateForDistance(distance),
);

Player playerWith(PlayerColor color, List<Token> tokens) =>
    Player(color: color, startSquare: startSquares[color]!, tokens: tokens);

GameState stateWith(List<Player> players, {int currentPlayerIndex = 0}) =>
    GameState(players: players, currentPlayerIndex: currentPlayerIndex);

/// The distance a [color] token has when it stands on absolute shared
/// [square] — inverse of toSharedSquare.
int distanceOn(PlayerColor color, int square) =>
    (square - startSquares[color]! + trackLength) % trackLength + 1;
