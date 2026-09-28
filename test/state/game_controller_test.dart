import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/move.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';
import 'package:ludi/state/game_controller.dart';

import '../helpers/fixtures.dart';

/// Controller over red (index 0) vs green (index 1) with scripted [rolls].
GameController controllerFor(
  List<Token> red,
  List<Token> green, {
  required List<int> rolls,
}) => GameController(
  initialState: stateWith([
    playerWith(PlayerColor.red, red),
    playerWith(PlayerColor.green, green),
  ]),
  random: ScriptedRandom(rolls),
);

Move moveTo(GameController controller, Token token, int newDistance) =>
    controller.currentLegalMoves.singleWhere(
      (m) => m.token == token && m.newDistance == newDistance,
    );

void main() {
  group('newGame', () {
    test('builds 4 players with 4 yard tokens each, red up first', () {
      final state = newGame();

      expect(state.players.map((p) => p.color), PlayerColor.values);
      expect(state.players.every((p) => p.tokens.length == 4), isTrue);
      expect(
        state.players.expand((p) => p.tokens).every((t) => t.state == TokenState.yard),
        isTrue,
      );
      expect(state.currentPlayer.color, PlayerColor.red);
      expect(state.phase, GamePhase.rolling);
    });

    test('gives every token a unique id', () {
      final ids = newGame().players.expand((p) => p.tokens).map((t) => t.id);
      expect(ids.toSet().length, 16);
    });

    test('seats only the chosen colors, in clockwise board order', () {
      final state = newGame(colors: [PlayerColor.yellow, PlayerColor.red]);

      expect(state.players.map((p) => p.color), [PlayerColor.red, PlayerColor.yellow]);
      expect(state.currentPlayer.color, PlayerColor.red);
    });

    test('rejects fewer than 2 or duplicate colors', () {
      expect(() => newGame(colors: [PlayerColor.red]), throwsArgumentError);
      expect(
        () => newGame(colors: [PlayerColor.red, PlayerColor.red]),
        throwsArgumentError,
      );
    });
  });

  group('GameController.rollDice', () {
    test('rolls, updates state, and notifies listeners', () {
      final controller = controllerFor([tokenAt(PlayerColor.red, 5)], [], rolls: [4]);
      var notified = 0;
      controller.addListener(() => notified++);

      controller.rollDice();

      expect(controller.state.lastDiceValue, 4);
      expect(controller.state.phase, GamePhase.selecting);
      expect(notified, 1);
    });

    test('is ignored while a move is pending (no re-rolling for a better number)', () {
      final controller = controllerFor([tokenAt(PlayerColor.red, 5)], [], rolls: [2, 6]);
      controller.rollDice();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.rollDice();

      expect(controller.state.lastDiceValue, 2);
      expect(notified, 0);
    });

    test('is ignored once the game is over', () {
      final controller = controllerFor([tokenAt(PlayerColor.red, 5)], [], rolls: [2]);
      controller.state.phase = GamePhase.gameOver;

      controller.rollDice();

      expect(controller.state.lastRoll, 0);
    });
  });

  group('GameController.selectMove', () {
    test('applies the move, fires onMoveAnimated, and notifies', () {
      final token = tokenAt(PlayerColor.red, 10);
      final controller = controllerFor(
        [token],
        [Token(id: 'g1', color: PlayerColor.green)],
        rolls: [4],
      );
      Move? animated;
      controller.onMoveAnimated = (m) => animated = m;
      controller.rollDice();
      var notified = 0;
      controller.addListener(() => notified++);

      final move = moveTo(controller, token, 14);
      controller.selectMove(move);

      expect(token.distance, 14);
      expect(animated, move);
      expect(notified, 2); // once after applyMove, once after completeTurn
      expect(controller.state.currentPlayerIndex, 1); // turn advanced
    });

    test('rolling a 6 keeps the turn with the same player (bonus roll)', () {
      final token = tokenAt(PlayerColor.red, 10);
      final controller = controllerFor([token], [], rolls: [6]);
      controller.rollDice();

      controller.selectMove(moveTo(controller, token, 16));

      expect(controller.state.currentPlayerIndex, 0); // still red
      expect(controller.state.phase, GamePhase.rolling); // ready to roll again
    });

    test('ignores a double tap — the same move only applies once', () {
      final token = tokenAt(PlayerColor.red, 10);
      final controller = controllerFor([token], [tokenAt(PlayerColor.green, 30)], rolls: [4]);
      controller.rollDice();
      final move = moveTo(controller, token, 14);

      controller.selectMove(move);
      controller.selectMove(move);

      expect(token.distance, 14);
      expect(controller.state.currentPlayerIndex, 1);
    });

    test('ignores a move that is not currently legal', () {
      final token = tokenAt(PlayerColor.red, 10);
      final controller = controllerFor([token], [], rolls: [4]);
      controller.rollDice();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.selectMove(Move(token: token, newDistance: 40, isBackward: false));

      expect(token.distance, 10);
      expect(controller.state.phase, GamePhase.selecting);
      expect(notified, 0);
    });

    test('fires onCapture for every captured opponent token', () {
      final redToken = tokenAt(PlayerColor.red, 12); // square 11
      final g1 = tokenAt(PlayerColor.green, 4, id: 'g1'); // square 16
      final g2 = tokenAt(PlayerColor.green, 4, id: 'g2');
      final controller = controllerFor([redToken], [g1, g2], rolls: [5]);
      final captured = <Token>[];
      controller.onCapture = captured.add;
      controller.rollDice();

      controller.selectMove(moveTo(controller, redToken, 17));

      expect(captured, [g1, g2]);
      expect([g1.state, g2.state], [TokenState.yard, TokenState.yard]);
      expect(controller.state.currentPlayerIndex, 0); // capture bonus roll
    });

    test('fires onGameOver with the winner once all their tokens finish', () {
      final lastToken = tokenAt(PlayerColor.red, 55, id: 'r3');
      final controller = controllerFor(
        [
          for (var i = 0; i < 3; i++) tokenAt(PlayerColor.red, 57, id: 'r$i'),
          lastToken,
        ],
        [Token(id: 'g1', color: PlayerColor.green)],
        rolls: [2],
      );
      PlayerColor? winner;
      controller.onGameOver = (c) => winner = c;
      controller.rollDice();

      controller.selectMove(moveTo(controller, lastToken, 57));

      expect(winner, PlayerColor.red);
      expect(controller.state.phase, GamePhase.gameOver);
      expect(controller.currentLegalMoves, isEmpty);
    });

    test('with three players, the first finisher is only announced once the game ends', () {
      final redLast = tokenAt(PlayerColor.red, 55, id: 'r3');
      final greenLast = tokenAt(PlayerColor.green, 55, id: 'g3');
      final controller = GameController(
        initialState: stateWith([
          playerWith(PlayerColor.red, [
            for (var i = 0; i < 3; i++) tokenAt(PlayerColor.red, 57, id: 'r$i'),
            redLast,
          ]),
          playerWith(PlayerColor.green, [
            for (var i = 0; i < 3; i++) tokenAt(PlayerColor.green, 57, id: 'g$i'),
            greenLast,
          ]),
          playerWith(PlayerColor.yellow, [Token(id: 'y0', color: PlayerColor.yellow)]),
        ]),
        random: ScriptedRandom([2]),
      );
      PlayerColor? winner;
      controller.onGameOver = (c) => winner = c;

      controller.rollDice();
      controller.selectMove(moveTo(controller, redLast, 57));
      expect(winner, isNull);
      expect(controller.state.phase, GamePhase.rolling);
      expect(controller.state.currentPlayer.color, PlayerColor.green);

      controller.rollDice();
      controller.selectMove(moveTo(controller, greenLast, 57));
      expect(winner, PlayerColor.red);
      expect(controller.state.finishOrder, [PlayerColor.red, PlayerColor.green, PlayerColor.yellow]);
    });
  });

  group('GameController with holdMovesForAnimation', () {
    GameController heldController(Token red, {required List<int> rolls}) =>
        GameController(
          initialState: stateWith([
            playerWith(PlayerColor.red, [red]),
            playerWith(PlayerColor.green, [tokenAt(PlayerColor.green, 30)]),
          ]),
          random: ScriptedRandom(rolls),
          holdMovesForAnimation: true,
        );

    test('selectMove applies the move but waits in animating', () {
      final token = tokenAt(PlayerColor.red, 10);
      final controller = heldController(token, rolls: [4]);
      controller.rollDice();

      controller.selectMove(moveTo(controller, token, 14));

      expect(token.distance, 14);
      expect(controller.state.phase, GamePhase.animating);
      expect(controller.state.currentPlayerIndex, 0);
    });

    test('ignores rolls and moves until completeMove', () {
      final token = tokenAt(PlayerColor.red, 10);
      final controller = heldController(token, rolls: [4, 2]);
      controller.rollDice();
      final move = moveTo(controller, token, 14);
      controller.selectMove(move);

      controller.rollDice();
      controller.selectMove(move);

      expect(controller.state.lastDiceValue, 4);
      expect(token.distance, 14);
    });

    test('completeMove resolves the turn and notifies', () {
      final token = tokenAt(PlayerColor.red, 10);
      final controller = heldController(token, rolls: [4]);
      controller.rollDice();
      controller.selectMove(moveTo(controller, token, 14));
      var notified = 0;
      controller.addListener(() => notified++);

      controller.completeMove();
      controller.completeMove(); // second call is a no-op

      expect(controller.state.currentPlayerIndex, 1);
      expect(controller.state.phase, GamePhase.rolling);
      expect(notified, 1);
    });
  });
}
