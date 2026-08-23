import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/turn_manager.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/move.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';

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
  group('rollDice', () {
    test('sets lastDiceValue and moves to selecting when a move exists', () {
      final yardToken = Token(id: 'r1', color: PlayerColor.red);
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [yardToken]),
        ],
      );

      rollDice(state);

      expect(state.lastDiceValue, inInclusiveRange(1, 6));
      expect(state.phase, GamePhase.selecting);
      expect(state.legalMoves, isNotEmpty);
    });

    test('auto-skips the turn when no token has a legal move', () {
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: []),
          Player(
            color: PlayerColor.green,
            startSquare: 13,
            tokens: [Token(id: 'g1', color: PlayerColor.green)],
          ),
        ],
      );

      rollDice(state);

      // No tokens at all for red -> no legal moves -> turn auto-advances.
      expect(state.currentPlayerIndex, 1);
      expect(state.phase, GamePhase.rolling);
      expect(state.legalMoves, isEmpty);
    });

    test('skips finished tokens when gathering legal moves', () {
      final finishedToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 58,
        state: TokenState.finished,
      );
      final state = buildState(
        players: [
          Player(
            color: PlayerColor.red,
            startSquare: 0,
            tokens: [finishedToken],
          ),
        ],
      );

      rollDice(state);

      expect(state.legalMoves, isEmpty);
      expect(state.phase, GamePhase.rolling); // auto-skipped
    });
  });

  group('applyMove', () {
    test('updates the token distance/state and moves phase to animating', () {
      final token = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 10,
        state: TokenState.active,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [token]),
        ],
      );
      final move = Move(token: token, newDistance: 14, isBackward: false);

      applyMove(state, move);

      expect(token.distance, 14);
      expect(token.state, TokenState.active);
      expect(state.phase, GamePhase.animating);
    });

    test('sends a captured token back to the yard', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 10,
        state: TokenState.active,
      );
      final capturedToken = Token(
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
            tokens: [capturedToken],
          ),
        ],
      );
      final move = Move(
        token: redToken,
        newDistance: 17,
        isBackward: false,
        capturedToken: capturedToken,
      );

      applyMove(state, move);

      expect(capturedToken.distance, 0);
      expect(capturedToken.state, TokenState.yard);
    });

    test('marks a token finished exactly at the last distance', () {
      final token = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 56,
        state: TokenState.homeStretch,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [token]),
        ],
      );
      final move = Move(token: token, newDistance: 58, isBackward: false);

      applyMove(state, move);

      expect(token.state, TokenState.finished);
    });
  });

  group('completeTurn', () {
    test('moves to gameOver when the current player has all tokens finished', () {
      final tokens = List.generate(
        4,
        (i) => Token(
          id: 'r$i',
          color: PlayerColor.red,
          distance: 58,
          state: TokenState.finished,
        ),
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: tokens),
        ],
      );

      completeTurn(state);

      expect(state.phase, GamePhase.gameOver);
    });

    test('advances to the next player when the current one has not won', () {
      final state = buildState(
        players: [
          Player(
            color: PlayerColor.red,
            startSquare: 0,
            tokens: [Token(id: 'r1', color: PlayerColor.red)],
          ),
          Player(
            color: PlayerColor.green,
            startSquare: 13,
            tokens: [Token(id: 'g1', color: PlayerColor.green)],
          ),
        ],
      );

      completeTurn(state);

      expect(state.currentPlayerIndex, 1);
      expect(state.phase, GamePhase.rolling);
    });
  });

  group('advanceTurn', () {
    test('wraps back to the first player after the last one', () {
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: []),
          Player(color: PlayerColor.green, startSquare: 13, tokens: []),
        ],
        currentPlayerIndex: 1,
      );

      advanceTurn(state);

      expect(state.currentPlayerIndex, 0);
    });

    test('resets dice, legal moves, and phase for the next turn', () {
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: []),
          Player(color: PlayerColor.green, startSquare: 13, tokens: []),
        ],
      );
      state.lastDiceValue = 5;
      state.legalMoves = [
        Move(
          token: Token(id: 'r1', color: PlayerColor.red),
          newDistance: 5,
          isBackward: false,
        ),
      ];
      state.phase = GamePhase.animating;

      advanceTurn(state);

      expect(state.lastDiceValue, 0);
      expect(state.legalMoves, isEmpty);
      expect(state.phase, GamePhase.rolling);
    });
  });
}
