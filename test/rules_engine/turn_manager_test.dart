import 'dart:math';

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

      // A yard token only has a legal move on a 6 — force that roll rather
      // than leaving it to real randomness (which would make this test
      // flaky 5/6 of the time under that rule).
      rollDice(state, random: _AlwaysSix());

      expect(state.lastDiceValue, 6);
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

    test('lastRoll keeps the rolled value on screen even when the turn skips', () {
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

      // Non-6, no red tokens -> turn auto-skips and zeros lastDiceValue,
      // but lastRoll (display-only) holds the number the dice landed on.
      rollDice(state, random: _AlwaysFour());

      expect(state.lastDiceValue, 0); // cleared by the auto-skip
      expect(state.lastRoll, 4); // still shown on the die
    });

    test('gathers both forward and backward moves when both are legal', () {
      // Random(11) rolls 3 first — see the dice value math in the setup
      // below, which is built around a roll of 3.
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 10, // square 9
        state: TokenState.active,
      );
      // backward: distance 7 -> square 6. Put an opponent there so backward
      // is offered too.
      final greenBlocker = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 46, // 13 + 46 - 1 = 58 % 52 = 6
        state: TokenState.active,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
          Player(
            color: PlayerColor.green,
            startSquare: 13,
            tokens: [greenBlocker],
          ),
        ],
      );

      rollDice(state, random: Random(11));

      expect(state.lastDiceValue, 3);
      expect(state.legalMoves.length, 2);
      expect(state.legalMoves.any((m) => !m.isBackward && m.newDistance == 13), isTrue);
      expect(
        state.legalMoves.any(
          (m) => m.isBackward && m.newDistance == 7 && m.capturedToken == greenBlocker,
        ),
        isTrue,
      );
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

    test('grants a bonus roll when the move used a roll of 6', () {
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
      state.lastDiceValue = 6;
      final move = Move(token: token, newDistance: 16, isBackward: false);

      applyMove(state, move);

      expect(state.bonusRollsRemaining, 1);
    });

    test('grants a bonus roll when the move captures, even off a non-6', () {
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
      state.lastDiceValue = 3;
      final move = Move(
        token: redToken,
        newDistance: 13,
        isBackward: false,
        capturedToken: capturedToken,
      );

      applyMove(state, move);

      expect(state.bonusRollsRemaining, 1);
    });

    test('grants a bonus roll when the move finishes a token', () {
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
      state.lastDiceValue = 2;
      final move = Move(token: token, newDistance: 58, isBackward: false);

      applyMove(state, move);

      expect(state.bonusRollsRemaining, 1);
    });

    test('stacks bonus rolls — a 6 that also captures grants two', () {
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
      state.lastDiceValue = 6;
      final move = Move(
        token: redToken,
        newDistance: 16,
        isBackward: false,
        capturedToken: capturedToken,
      );

      applyMove(state, move);

      expect(state.bonusRollsRemaining, 2);
    });

    test('grants no bonus roll for an ordinary non-6, non-capturing move', () {
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
      state.lastDiceValue = 4;
      final move = Move(token: token, newDistance: 14, isBackward: false);

      applyMove(state, move);

      expect(state.bonusRollsRemaining, 0);
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

    test('keeps the same player and decrements when a bonus roll is pending', () {
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
      state.bonusRollsRemaining = 1;
      state.lastDiceValue = 6;
      state.legalMoves = [
        Move(token: Token(id: 'r1', color: PlayerColor.red), newDistance: 1, isBackward: false),
      ];

      completeTurn(state);

      expect(state.currentPlayerIndex, 0); // still red — turn did not pass
      expect(state.bonusRollsRemaining, 0);
      expect(state.lastDiceValue, 0); // cleared, ready for the bonus roll
      expect(state.legalMoves, isEmpty);
      expect(state.phase, GamePhase.rolling);
    });

    test('only passes to the next player once every bonus roll is used up', () {
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
      state.bonusRollsRemaining = 2; // e.g. a 6 that also captured

      completeTurn(state); // consumes one
      expect(state.currentPlayerIndex, 0);
      expect(state.bonusRollsRemaining, 1);

      completeTurn(state); // consumes the last one
      expect(state.currentPlayerIndex, 0);
      expect(state.bonusRollsRemaining, 0);

      completeTurn(state); // none left — turn actually passes now
      expect(state.currentPlayerIndex, 1);
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

    test('resets bonusRollsRemaining for the next player', () {
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: []),
          Player(color: PlayerColor.green, startSquare: 13, tokens: []),
        ],
      );
      state.bonusRollsRemaining = 2; // leftover from red's turn, shouldn't carry over

      advanceTurn(state);

      expect(state.bonusRollsRemaining, 0);
    });
  });
}

/// Deterministic stand-in for Random — always yields a die roll of 6.
class _AlwaysSix implements Random {
  @override
  int nextInt(int max) => max - 1;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

/// Deterministic stand-in for Random — always yields a die roll of 4.
class _AlwaysFour implements Random {
  @override
  int nextInt(int max) => 3; // rollDie adds 1 -> 4

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}
