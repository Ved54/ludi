import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/legal_moves.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';

import '../helpers/fixtures.dart';

void main() {
  group('isValidDestination', () {
    test('1 through 57 are valid', () {
      expect(isValidDestination(1), isTrue);
      expect(isValidDestination(57), isTrue);
    });

    test('0 and past 57 are invalid — no overshoot', () {
      expect(isValidDestination(0), isFalse);
      expect(isValidDestination(58), isFalse);
    });
  });

  group('stateForDistance', () {
    test('maps each distance band to its token state', () {
      expect(stateForDistance(0), TokenState.yard);
      expect(stateForDistance(1), TokenState.active);
      expect(stateForDistance(51), TokenState.active);
      expect(stateForDistance(52), TokenState.homeStretch);
      expect(stateForDistance(56), TokenState.homeStretch);
      expect(stateForDistance(57), TokenState.finished);
    });
  });

  group('getLegalMoves — forward', () {
    test('always offers forward when destination is valid', () {
      final redToken = tokenAt(PlayerColor.red, 10);
      final state = stateWith([playerWith(PlayerColor.red, [redToken])]);

      final moves = getLegalMoves(redToken, 4, state);

      expect(moves.length, 1);
      expect(moves.first.isBackward, isFalse);
      expect(moves.first.newDistance, 14);
    });

    test('omits forward when it would overshoot past 57', () {
      final redToken = tokenAt(PlayerColor.red, 55);
      final state = stateWith([playerWith(PlayerColor.red, [redToken])]);

      expect(getLegalMoves(redToken, 3, state), isEmpty); // 58
    });

    test('lands exactly on 57 to finish', () {
      final redToken = tokenAt(PlayerColor.red, 55);
      final state = stateWith([playerWith(PlayerColor.red, [redToken])]);

      final moves = getLegalMoves(redToken, 2, state);

      expect(moves.single.newDistance, 57);
    });

    test('a finished token has no moves at all', () {
      final redToken = tokenAt(PlayerColor.red, 57);
      final state = stateWith([playerWith(PlayerColor.red, [redToken])]);

      for (var roll = 1; roll <= 6; roll++) {
        expect(getLegalMoves(redToken, roll, state), isEmpty, reason: 'roll $roll');
      }
    });

    test('a yard token can only leave on a roll of exactly 6', () {
      final redToken = Token(id: 'r1', color: PlayerColor.red);
      final state = stateWith([playerWith(PlayerColor.red, [redToken])]);

      final moves = getLegalMoves(redToken, 6, state);

      // Entering uses the whole roll — lands on distance 1 (the color's
      // own start/safe square), not distance 6.
      expect(moves.single.newDistance, 1);
      expect(moves.single.isBackward, isFalse);
    });

    test('a yard token has no legal move on any roll other than 6', () {
      final redToken = Token(id: 'r1', color: PlayerColor.red);
      final state = stateWith([playerWith(PlayerColor.red, [redToken])]);

      for (final roll in [1, 2, 3, 4, 5]) {
        expect(getLegalMoves(redToken, roll, state), isEmpty, reason: 'roll $roll');
      }
    });

    test('forward move onto an opponent populates capturedToken', () {
      final redToken = tokenAt(PlayerColor.red, 10); // square 9
      final greenToken = tokenAt(PlayerColor.green, 4); // square 16
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken]),
        playerWith(PlayerColor.green, [greenToken]),
      ]);

      final moves = getLegalMoves(redToken, 7, state); // -> square 16

      expect(moves.single.capturedToken, greenToken);
    });

    test('forward move onto a star square never captures', () {
      final redToken = tokenAt(PlayerColor.red, 5); // square 4
      final greenToken = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 8));
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken]),
        playerWith(PlayerColor.green, [greenToken]),
      ]);

      final moves = getLegalMoves(redToken, 4, state); // -> square 8, star

      expect(moves.single.capturedToken, isNull);
    });

    test('captures an opponent on the last shared-track square (distance 51)', () {
      final redToken = tokenAt(PlayerColor.red, 45);
      final greenToken = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 50));
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken]),
        playerWith(PlayerColor.green, [greenToken]),
      ]);

      final moves = getLegalMoves(redToken, 6, state);

      expect(moves.single.newDistance, 51);
      expect(moves.single.capturedToken, greenToken);
    });

    test('forward move into the home stretch never captures', () {
      final redToken = tokenAt(PlayerColor.red, 50);
      // An opponent on the square the home-stretch distance would alias to
      // if it were (wrongly) mapped onto the shared track.
      // (54 would alias to square 1.)
      final greenToken = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 1));
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken]),
        playerWith(PlayerColor.green, [greenToken]),
      ]);

      final moves = getLegalMoves(redToken, 4, state); // distance 54

      expect(moves.single.capturedToken, isNull);
    });
  });

  group('getLegalMoves — backward', () {
    test('offers backward when it lands exactly on a capturable opponent', () {
      final redToken = tokenAt(PlayerColor.red, 10); // square 9
      final greenBlocker = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 6));
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken]),
        playerWith(PlayerColor.green, [greenBlocker]),
      ]);

      final moves = getLegalMoves(redToken, 3, state); // back to square 6

      final backward = moves.where((m) => m.isBackward).single;
      expect(backward.newDistance, 7);
      expect(backward.capturedToken, greenBlocker);
      expect(moves.where((m) => !m.isBackward).single.newDistance, 13);
    });

    test('does not offer backward when nothing capturable is behind', () {
      final redToken = tokenAt(PlayerColor.red, 10);
      final state = stateWith([playerWith(PlayerColor.red, [redToken])]);

      final moves = getLegalMoves(redToken, 3, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });

    test('does not offer backward onto own token', () {
      final redToken = tokenAt(PlayerColor.red, 10, id: 'r1');
      final redBehind = tokenAt(PlayerColor.red, 7, id: 'r2');
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken, redBehind]),
      ]);

      final moves = getLegalMoves(redToken, 3, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });

    test('never offers backward for a token still in the yard', () {
      final redToken = Token(id: 'r1', color: PlayerColor.red);
      final state = stateWith([playerWith(PlayerColor.red, [redToken])]);

      final moves = getLegalMoves(redToken, 6, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });

    test('does not retreat past the yard-retreat floor (distance < 1)', () {
      final redToken = tokenAt(PlayerColor.red, 2);
      // Sits on the square backwardDist = -3 would wrap to, if allowed.
      final greenBlocker = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 48));
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken]),
        playerWith(PlayerColor.green, [greenBlocker]),
      ]);

      final moves = getLegalMoves(redToken, 5, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });

    test('does not offer backward onto a safe square', () {
      final redToken = tokenAt(PlayerColor.red, 2); // square 1
      // Opponent on red's own start (square 0) — safe, so immune.
      final greenOnRedStart = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 0));
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken]),
        playerWith(PlayerColor.green, [greenOnRedStart]),
      ]);

      final moves = getLegalMoves(redToken, 1, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });

    test('never offers a backward step that stays inside the home column', () {
      // 56 - 2 = 54, still home column. The old engine mapped 54 onto
      // shared square 1 and offered a bogus capture-less "backward kill"
      // whenever an opponent happened to stand there.
      final redToken = tokenAt(PlayerColor.red, 56);
      final greenOnSquare1 = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 1));
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken]),
        playerWith(PlayerColor.green, [greenOnSquare1]),
      ]);

      final moves = getLegalMoves(redToken, 2, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });

    test('a home-column token may still strike back onto the shared track', () {
      // README Section 4: only the yard is a floor — 53 - 4 = 49 is shared.
      final redToken = tokenAt(PlayerColor.red, 53);
      final greenBlocker = tokenAt(PlayerColor.green, distanceOn(PlayerColor.green, 48));
      final state = stateWith([
        playerWith(PlayerColor.red, [redToken]),
        playerWith(PlayerColor.green, [greenBlocker]),
      ]);

      final moves = getLegalMoves(redToken, 4, state);

      final backward = moves.where((m) => m.isBackward).single;
      expect(backward.newDistance, 49);
      expect(backward.capturedToken, greenBlocker);
    });

    test('every backward move offered is a capture', () {
      // Opponents scattered over the whole track, red token at every spot
      // and every roll — backward must appear only alongside a capture.
      final greens = [
        for (var d = 2; d <= 51; d += 3)
          tokenAt(PlayerColor.green, d, id: 'g$d'),
      ];
      for (var distance = 1; distance <= 56; distance++) {
        final red = tokenAt(PlayerColor.red, distance);
        final state = stateWith([
          playerWith(PlayerColor.red, [red]),
          playerWith(PlayerColor.green, greens),
        ]);
        for (var roll = 1; roll <= 6; roll++) {
          for (final move in getLegalMoves(red, roll, state)) {
            if (move.isBackward) {
              expect(move.capturedToken, isNotNull, reason: 'd$distance r$roll');
            }
          }
        }
      }
    });
  });

  group('legalMovesFor', () {
    test("collects every token's moves for the roll", () {
      final yard = Token(id: 'r0', color: PlayerColor.red);
      final active = tokenAt(PlayerColor.red, 10, id: 'r1');
      final finished = tokenAt(PlayerColor.red, 57, id: 'r2');
      final player = playerWith(PlayerColor.red, [yard, active, finished]);
      final state = stateWith([player]);

      final moves = legalMovesFor(player, 6, state);

      expect(moves.map((m) => m.token), [yard, active]);
    });
  });
}
