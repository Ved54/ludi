import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/legal_moves.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';

GameState buildState({required List<Player> players}) =>
    GameState(players: players);

void main() {
  group('isValidDestination', () {
    test('1 through 58 are valid', () {
      expect(isValidDestination(1), isTrue);
      expect(isValidDestination(58), isTrue);
    });

    test('0 and past 58 are invalid — no overshoot', () {
      expect(isValidDestination(0), isFalse);
      expect(isValidDestination(59), isFalse);
    });
  });

  group('getLegalMoves — forward', () {
    test('always offers forward when destination is valid', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 10,
        state: TokenState.active,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
        ],
      );

      final moves = getLegalMoves(redToken, 4, state);

      expect(moves.length, 1);
      expect(moves.first.isBackward, isFalse);
      expect(moves.first.newDistance, 14);
    });

    test('omits forward when it would overshoot past 58', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 56,
        state: TokenState.homeStretch,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
        ],
      );

      // 56 + 5 = 61, past the 58 finish square.
      final moves = getLegalMoves(redToken, 5, state);

      expect(moves, isEmpty);
    });

    test('lands exactly on 58 to finish', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 56,
        state: TokenState.homeStretch,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
        ],
      );

      final moves = getLegalMoves(redToken, 2, state);

      expect(moves.length, 1);
      expect(moves.first.newDistance, 58);
    });

    test('a yard token can move forward onto the shared track', () {
      final redToken = Token(id: 'r1', color: PlayerColor.red);
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
        ],
      );

      final moves = getLegalMoves(redToken, 6, state);

      expect(moves.length, 1);
      expect(moves.first.newDistance, 6);
      expect(moves.first.isBackward, isFalse);
    });

    test('forward move onto an opponent populates capturedToken', () {
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
      ); // shared square = 13 + 4 - 1 = 16, same as red's 10 + 6 -> 15

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

      // red at distance 10 -> shared square 9. +7 -> distance 17 -> square 16.
      final moves = getLegalMoves(redToken, 7, state);

      expect(moves.first.capturedToken, greenToken);
    });

    test('captures an opponent on the last shared-track square (distance 51)', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 45,
        state: TokenState.active,
      );
      // red distance 45 -> square 44. +6 -> distance 51 -> square 50, still
      // shared track (homeStretchStart is 52), so still capturable.
      final greenToken = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 38,
        state: TokenState.active,
      ); // 13 + 38 - 1 = 50

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

      final moves = getLegalMoves(redToken, 6, state);

      expect(moves.first.newDistance, 51);
      expect(moves.first.capturedToken, greenToken);
    });

    test('forward move into the home stretch never captures', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 50,
        state: TokenState.active,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
        ],
      );

      final moves = getLegalMoves(redToken, 3, state); // distance 53, home stretch

      expect(moves.first.capturedToken, isNull);
    });
  });

  group('getLegalMoves — backward', () {
    test('offers backward when it lands exactly on a capturable opponent', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 10,
        state: TokenState.active,
      );
      // red at distance 10 -> square 9. backward by 3 -> distance 7 -> square 6.
      // Place green so its shared square is 6: 13 + d - 1 == 6 (mod 52) -> d = 46.
      final greenBlocker = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 46,
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

      final moves = getLegalMoves(redToken, 3, state);

      final backwardMoves = moves.where((m) => m.isBackward);
      expect(backwardMoves.length, 1);
      expect(backwardMoves.first.newDistance, 7);
      expect(backwardMoves.first.capturedToken, greenBlocker);
    });

    test('does not offer backward when nothing capturable is behind', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 10,
        state: TokenState.active,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
        ],
      );

      final moves = getLegalMoves(redToken, 3, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });

    test('never offers backward for a token still in the yard', () {
      final redToken = Token(id: 'r1', color: PlayerColor.red);
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
        ],
      );

      final moves = getLegalMoves(redToken, 6, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });

    test('does not retreat past the yard-retreat floor (distance < 1)', () {
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 2,
        state: TokenState.active,
      );
      final greenBlocker = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 40,
        state: TokenState.active,
      ); // would sit at the square backwardDist=-3 maps to, if it were allowed

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

      // backwardDist = 2 - 5 = -3, below the floor of 1 -> must not appear,
      // regardless of what's sitting behind it.
      final moves = getLegalMoves(redToken, 5, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });

    test('does not offer backward onto a safe square', () {
      // red at distance 2 -> square 1. backward by 1 -> distance 1 -> square 0,
      // red's own start square, which is safe.
      final redToken = Token(
        id: 'r1',
        color: PlayerColor.red,
        distance: 2,
        state: TokenState.active,
      );
      // Occupy square 0 anyway to prove even a live opponent there is immune:
      // 13 + d - 1 == 0 (mod 52) -> d = 40.
      final greenOnRedStart = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 40,
        state: TokenState.active,
      );
      final state = buildState(
        players: [
          Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
          Player(
            color: PlayerColor.green,
            startSquare: 13,
            tokens: [greenOnRedStart],
          ),
        ],
      );

      final moves = getLegalMoves(redToken, 1, state);

      expect(moves.every((m) => !m.isBackward), isTrue);
    });
  });
}
