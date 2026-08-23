import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/move.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';
import 'package:ludi/state/game_controller.dart';

GameState buildState({
  required List<Player> players,
  int currentPlayerIndex = 0,
  GamePhase phase = GamePhase.rolling,
}) => GameState(
  players: players,
  currentPlayerIndex: currentPlayerIndex,
  phase: phase,
);

void main() {
  group('newGame', () {
    test('builds 4 players with 4 yard tokens each, red up first', () {
      final state = newGame();

      expect(state.players.length, 4);
      expect(state.players.every((p) => p.tokens.length == 4), isTrue);
      expect(
        state.players
            .expand((p) => p.tokens)
            .every((t) => t.state == TokenState.yard),
        isTrue,
      );
      expect(state.currentPlayerIndex, 0);
      expect(state.phase, GamePhase.rolling);
    });
  });

  group('GameController.rollDice', () {
    test('rolls, updates state, and notifies listeners', () {
      final controller = GameController();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.rollDice();

      expect(controller.state.lastDiceValue, inInclusiveRange(1, 6));
      expect(notified, 1);
    });
  });

  group('GameController.selectMove', () {
    test('applies the move, fires onMoveAnimated, and notifies', () {
      final token = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 10,
        state: TokenState.active,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [token]),
          Player(
            color: PlayerColor.green,
            startSquare: 13,
            tokens: [Token(id: 'g1', color: PlayerColor.green)],
          ),
        ],
      );
      final controller = GameController(initialState: state);
      Move? animated;
      controller.onMoveAnimated = (m) => animated = m;
      var notified = 0;
      controller.addListener(() => notified++);

      final move = Move(token: token, newDistance: 14, isBackward: false);
      controller.selectMove(move);

      expect(token.distance, 14);
      expect(animated, move);
      expect(notified, 2); // once after applyMove, once after completeTurn
      expect(controller.state.currentPlayerIndex, 1); // turn advanced
    });

    test('fires onCapture when the move captures an opponent', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 10,
        state: TokenState.active,
      );
      final greenToken = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 4,
        state: TokenState.active,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
          Player(
            color: PlayerColor.green,
            startSquare: 13,
            tokens: [greenToken],
          ),
        ],
      );
      final controller = GameController(initialState: state);
      Token? captured;
      controller.onCapture = (t) => captured = t;

      final move = Move(
        token: redToken,
        newDistance: 17,
        isBackward: false,
        capturedToken: greenToken,
      );
      controller.selectMove(move);

      expect(captured, greenToken);
      expect(greenToken.state, TokenState.yard);
      expect(greenToken.distance, 0);
    });

    test('fires onGameOver with the winner once all their tokens finish', () {
      final lastToken = Token(
        id: 'r4',
        color: PlayerColor.red,
        distance: 56,
        state: TokenState.homeStretch,
      );
      final finishedTokens = List.generate(
        3,
        (i) => Token(
          id: 'r$i',
          color: PlayerColor.red,
          distance: 58,
          state: TokenState.finished,
        ),
      );
      final state = buildState(
        players: [
          Player(
            color: PlayerColor.red,
            startSquare: 0,
            tokens: [...finishedTokens, lastToken],
          ),
        ],
      );
      final controller = GameController(initialState: state);
      PlayerColor? winner;
      controller.onGameOver = (c) => winner = c;

      final move = Move(token: lastToken, newDistance: 58, isBackward: false);
      controller.selectMove(move);

      expect(winner, PlayerColor.red);
      expect(controller.state.phase, GamePhase.gameOver);
    });
  });
}
