import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/move.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';
import 'package:ludi/rules_engine/turn_manager.dart';

import '../helpers/fixtures.dart';

/// Rolls [value] for the current player through the real engine.
void roll(GameState state, int value) =>
    rollDice(state, random: ScriptedRandom([value]));

/// Rolls [value], then returns the legal move that takes [token] to
/// [newDistance] — the same Move object the UI would hand back.
Move rollFor(GameState state, int value, Token token, int newDistance) {
  roll(state, value);
  return state.legalMoves.singleWhere(
    (m) => m.token == token && m.newDistance == newDistance,
  );
}

/// Red (index 0) vs green (index 1), tokens as given.
GameState redVsGreen(List<Token> red, List<Token> green) => stateWith([
  playerWith(PlayerColor.red, red),
  playerWith(PlayerColor.green, green),
]);

/// All four seated in turn order; unlisted colors keep one yard token.
GameState fourPlayers({
  List<Token>? red,
  List<Token>? green,
  List<Token>? yellow,
  List<Token>? blue,
}) => stateWith([
  for (final (color, tokens) in [
    (PlayerColor.red, red),
    (PlayerColor.green, green),
    (PlayerColor.yellow, yellow),
    (PlayerColor.blue, blue),
  ])
    playerWith(color, tokens ?? [Token(id: '${color.name}0', color: color)]),
]);

/// [count] of [color]'s tokens, already home.
List<Token> homeTokens(PlayerColor color, int count) => [
  for (var i = 0; i < count; i++) tokenAt(color, 57, id: '${color.name}$i'),
];

void main() {
  group('rollDice', () {
    test('sets lastDiceValue and moves to selecting when a move exists', () {
      final state = redVsGreen([Token(id: 'r1', color: PlayerColor.red)], []);

      roll(state, 6);

      expect(state.lastDiceValue, 6);
      expect(state.lastRoll, 6);
      expect(state.phase, GamePhase.selecting);
      expect(state.legalMoves.single.newDistance, 1);
    });

    test('auto-skips the turn when no token has a legal move', () {
      final state = redVsGreen(
        [Token(id: 'r1', color: PlayerColor.red)],
        [Token(id: 'g1', color: PlayerColor.green)],
      );

      roll(state, 4); // yard token, non-6

      expect(state.currentPlayerIndex, 1);
      expect(state.phase, GamePhase.rolling);
      expect(state.legalMoves, isEmpty);
      expect(state.lastDiceValue, 0); // cleared by the auto-skip
      expect(state.lastRoll, 4); // still shown on the die
    });

    test('a wasted 6 still earns a re-roll for the same player', () {
      // Only token is deep in the home column — a 6 overshoots.
      final state = redVsGreen([tokenAt(PlayerColor.red, 54)], []);

      roll(state, 6);

      expect(state.currentPlayerIndex, 0);
      expect(state.phase, GamePhase.rolling);
      expect(state.bonusRollsRemaining, 0); // earned and already consumed
    });

    test('a wasted roll does not forfeit bonus rolls already owed', () {
      final state = redVsGreen([tokenAt(PlayerColor.red, 54)], []);
      state.bonusRollsRemaining = 1;

      roll(state, 5); // overshoots, but a bonus roll is still owed

      expect(state.currentPlayerIndex, 0);
      expect(state.phase, GamePhase.rolling);
      expect(state.bonusRollsRemaining, 0);

      roll(state, 5); // nothing owed any more — turn passes
      expect(state.currentPlayerIndex, 1);
    });

    test('gathers both forward and backward moves when both are legal', () {
      final redToken = tokenAt(PlayerColor.red, 10); // square 9
      final greenBlocker = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 6));
      final state = redVsGreen([redToken], [greenBlocker]);

      roll(state, 3);

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
      final state = redVsGreen([tokenAt(PlayerColor.red, 57)], []);

      roll(state, 3);

      expect(state.currentPlayerIndex, 1); // auto-skipped
    });

    test('refuses to roll outside the rolling phase', () {
      final state = redVsGreen([tokenAt(PlayerColor.red, 10)], []);
      roll(state, 3); // now selecting

      expect(() => roll(state, 4), throwsStateError);
      expect(state.lastDiceValue, 3); // the pending roll is untouched
    });
  });

  group('applyMove', () {
    test('updates the token distance/state and moves phase to animating', () {
      final token = tokenAt(PlayerColor.red, 10);
      final state = redVsGreen([token], []);
      final move = rollFor(state, 4, token, 14);

      final captured = applyMove(state, move);

      expect(captured, isEmpty);
      expect(token.distance, 14);
      expect(token.state, TokenState.active);
      expect(state.phase, GamePhase.animating);
    });

    test('rejects a move that is not one of the legal moves', () {
      final token = tokenAt(PlayerColor.red, 10);
      final state = redVsGreen([token], []);
      roll(state, 4);
      final forged = Move(token: token, newDistance: 30, isBackward: false);

      expect(() => applyMove(state, forged), throwsArgumentError);
      expect(token.distance, 10);
    });

    test('refuses to apply a move outside the selecting phase', () {
      final token = tokenAt(PlayerColor.red, 10);
      final state = redVsGreen([token], []);
      final move = rollFor(state, 4, token, 14);
      applyMove(state, move);

      expect(() => applyMove(state, move), throwsStateError);
      expect(token.distance, 14); // not applied twice
    });

    test('sends a captured token back to the yard', () {
      final redToken = tokenAt(PlayerColor.red, 12); // square 11
      final greenToken = tokenAt(PlayerColor.green, 4); // square 16
      final state = redVsGreen([redToken], [greenToken]);
      final move = rollFor(state, 5, redToken, 17); // -> square 16

      final captured = applyMove(state, move);

      expect(captured, [greenToken]);
      expect(greenToken.distance, 0);
      expect(greenToken.state, TokenState.yard);
      expect(state.bonusRollsRemaining, 1); // capture bonus, non-6 roll
    });

    test('captures every opponent token stacked on the destination', () {
      final redToken = tokenAt(PlayerColor.red, 11); // square 10
      final g1 = tokenAt(PlayerColor.green, 4, id: 'g1'); // square 16
      final g2 = tokenAt(PlayerColor.green, 4, id: 'g2');
      final state = redVsGreen([redToken], [g1, g2]);
      final move = rollFor(state, 6, redToken, 17);

      final captured = applyMove(state, move);

      expect(captured, [g1, g2]);
      expect([g1.state, g2.state], [TokenState.yard, TokenState.yard]);
      expect(state.bonusRollsRemaining, 2); // the 6 + one for capturing
    });

    test('a backward kill moves the token back and captures', () {
      final redToken = tokenAt(PlayerColor.red, 10);
      final greenBlocker = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 6));
      final state = redVsGreen([redToken], [greenBlocker]);
      roll(state, 3);
      final backward = state.legalMoves.singleWhere((m) => m.isBackward);

      final captured = applyMove(state, backward);

      expect(redToken.distance, 7);
      expect(captured, [greenBlocker]);
      expect(greenBlocker.state, TokenState.yard);
      expect(state.bonusRollsRemaining, 1); // capture bonus, non-6 roll
    });

    test('marks a token finished exactly at the last distance', () {
      final token = tokenAt(PlayerColor.red, 55);
      final state = redVsGreen([token, tokenAt(PlayerColor.red, 10)], []);
      final move = rollFor(state, 2, token, 57);

      applyMove(state, move);

      expect(token.state, TokenState.finished);
      expect(state.bonusRollsRemaining, 1); // finishing bonus
    });

    test('grants a bonus roll when the move used a roll of 6', () {
      final token = tokenAt(PlayerColor.red, 10);
      final state = redVsGreen([token], []);

      applyMove(state, rollFor(state, 6, token, 16));

      expect(state.bonusRollsRemaining, 1);
    });

    test('grants no bonus roll for an ordinary non-6, non-capturing move', () {
      final token = tokenAt(PlayerColor.red, 10);
      final state = redVsGreen([token], []);

      applyMove(state, rollFor(state, 4, token, 14));

      expect(state.bonusRollsRemaining, 0);
    });

    test('finishing with a 6 stacks two bonus rolls', () {
      final token = tokenAt(PlayerColor.red, 51);
      final state = redVsGreen([token, tokenAt(PlayerColor.red, 10)], []);

      applyMove(state, rollFor(state, 6, token, 57));

      expect(state.bonusRollsRemaining, 2);
    });
  });

  group('completeTurn', () {
    test('in a 2-player game, the first to bring all four home ends it', () {
      final last = tokenAt(PlayerColor.red, 56, id: 'r3');
      final state = redVsGreen(
        [
          for (var i = 0; i < 3; i++) tokenAt(PlayerColor.red, 57, id: 'r$i'),
          last,
        ],
        [Token(id: 'g1', color: PlayerColor.green)],
      );
      applyMove(state, rollFor(state, 1, last, 57));

      completeTurn(state);

      expect(state.phase, GamePhase.gameOver);
      expect(state.finishOrder, [PlayerColor.red]);
      expect(state.standings, [PlayerColor.red, PlayerColor.green]);
      expect(state.legalMoves, isEmpty);
    });

    test('with more players left, the finisher takes a place and play goes on without them', () {
      final last = tokenAt(PlayerColor.red, 51, id: 'r3');
      final state = fourPlayers(red: [...homeTokens(PlayerColor.red, 3), last]);
      applyMove(state, rollFor(state, 6, last, 57)); // a 6 AND a finish: 2 bonus rolls

      completeTurn(state);

      expect(state.finishOrder, [PlayerColor.red]);
      expect(state.phase, GamePhase.rolling);
      expect(state.currentPlayer.color, PlayerColor.green, reason: 'no bonus rolls once done');
      expect(state.bonusRollsRemaining, 0);
    });

    test('the game ends when only one player is left, first finisher on top', () {
      final last = tokenAt(PlayerColor.yellow, 56, id: 'y3');
      final state = fourPlayers(
        red: homeTokens(PlayerColor.red, 4),
        yellow: [...homeTokens(PlayerColor.yellow, 3), last],
        blue: homeTokens(PlayerColor.blue, 4),
      )
        ..finishOrder.addAll([PlayerColor.blue, PlayerColor.red])
        ..currentPlayerIndex = 2;
      applyMove(state, rollFor(state, 1, last, 57));

      completeTurn(state);

      expect(state.phase, GamePhase.gameOver);
      expect(state.finishOrder, [PlayerColor.blue, PlayerColor.red, PlayerColor.yellow]);
      expect(state.standings.last, PlayerColor.green);
    });

    test('advances to the next player when no bonus roll is owed', () {
      final token = tokenAt(PlayerColor.red, 10);
      final state = redVsGreen([token], [Token(id: 'g1', color: PlayerColor.green)]);
      applyMove(state, rollFor(state, 4, token, 14));

      completeTurn(state);

      expect(state.currentPlayerIndex, 1);
      expect(state.phase, GamePhase.rolling);
      expect(state.lastDiceValue, 0);
      expect(state.legalMoves, isEmpty);
    });

    test('keeps the same player and consumes one owed bonus roll', () {
      final token = tokenAt(PlayerColor.red, 10);
      final state = redVsGreen([token], [Token(id: 'g1', color: PlayerColor.green)]);
      applyMove(state, rollFor(state, 6, token, 16));

      completeTurn(state);

      expect(state.currentPlayerIndex, 0); // still red — turn did not pass
      expect(state.bonusRollsRemaining, 0);
      expect(state.lastDiceValue, 0); // cleared, ready for the bonus roll
      expect(state.legalMoves, isEmpty);
      expect(state.phase, GamePhase.rolling);
    });

    test('only passes to the next player once every bonus roll is used up', () {
      final redToken = tokenAt(PlayerColor.red, 11);
      final greenToken = tokenAt(PlayerColor.green, 4); // square 16
      final state = redVsGreen([redToken], [greenToken]);

      applyMove(state, rollFor(state, 6, redToken, 17)); // 6 + capture = 2
      completeTurn(state);
      expect(state.currentPlayerIndex, 0);
      expect(state.bonusRollsRemaining, 1);

      applyMove(state, rollFor(state, 2, redToken, 19));
      completeTurn(state); // consumes the last one
      expect(state.currentPlayerIndex, 0);
      expect(state.bonusRollsRemaining, 0);

      applyMove(state, rollFor(state, 2, redToken, 21));
      completeTurn(state); // none left — turn actually passes now
      expect(state.currentPlayerIndex, 1);
    });

    test('refuses to complete a turn that has no applied move', () {
      final state = redVsGreen([tokenAt(PlayerColor.red, 10)], []);

      expect(() => completeTurn(state), throwsStateError);
    });
  });

  group('advanceTurn', () {
    test('wraps back to the first player after the last one', () {
      final state = stateWith(
        [playerWith(PlayerColor.red, []), playerWith(PlayerColor.green, [])],
        currentPlayerIndex: 1,
      );

      advanceTurn(state);

      expect(state.currentPlayerIndex, 0);
    });

    test('skips players who have already finished', () {
      final state = fourPlayers()..finishOrder.addAll([PlayerColor.green, PlayerColor.yellow]);

      advanceTurn(state);
      expect(state.currentPlayer.color, PlayerColor.blue);
      advanceTurn(state);
      expect(state.currentPlayer.color, PlayerColor.red);
    });

    test('resets dice, legal moves, bonus rolls, and phase', () {
      final state = redVsGreen([], []);
      state
        ..lastDiceValue = 5
        ..bonusRollsRemaining = 2
        ..legalMoves = [
          Move(
            token: Token(id: 'r1', color: PlayerColor.red),
            newDistance: 5,
            isBackward: false,
          ),
        ]
        ..phase = GamePhase.animating;

      advanceTurn(state);

      expect(state.lastDiceValue, 0);
      expect(state.bonusRollsRemaining, 0);
      expect(state.legalMoves, isEmpty);
      expect(state.phase, GamePhase.rolling);
    });
  });
}
