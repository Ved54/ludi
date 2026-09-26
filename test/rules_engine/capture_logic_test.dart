import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/capture_logic.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';

import '../helpers/fixtures.dart';

void main() {
  group('toSharedSquare', () {
    test('maps distance to absolute track index using color offset', () {
      expect(toSharedSquare(PlayerColor.red, 1), 0);
      expect(toSharedSquare(PlayerColor.green, 1), 13);
      expect(toSharedSquare(PlayerColor.yellow, 1), 26);
      expect(toSharedSquare(PlayerColor.blue, 1), 39);
    });

    test('wraps around the 52-square track', () {
      expect(toSharedSquare(PlayerColor.blue, 13), 51);
      expect(toSharedSquare(PlayerColor.blue, 14), 0); // wraps past 51
    });

    test("a color's last shared square is the one just before its start", () {
      // Distance 51 is the final shared square; square start-1 is never
      // visited by that color (it turns into its home column instead).
      expect(toSharedSquare(PlayerColor.red, 51), 50);
      expect(toSharedSquare(PlayerColor.green, 51), 11);
    });

    test('rejects distances off the shared track', () {
      expect(() => toSharedSquare(PlayerColor.red, 0), throwsA(isA<AssertionError>()));
      expect(() => toSharedSquare(PlayerColor.red, 52), throwsA(isA<AssertionError>()));
    });
  });

  group('isOnSharedTrack', () {
    test('is exactly distances 1-51', () {
      expect(isOnSharedTrack(0), isFalse);
      expect(isOnSharedTrack(1), isTrue);
      expect(isOnSharedTrack(51), isTrue);
      expect(isOnSharedTrack(52), isFalse);
    });
  });

  group('isSafeSquare', () {
    test('start squares are safe', () {
      for (final square in [0, 13, 26, 39]) {
        expect(isSafeSquare(square), isTrue, reason: 'square $square');
      }
    });

    test('star squares (8 past each start) are also safe', () {
      for (final square in [8, 21, 34, 47]) {
        expect(isSafeSquare(square), isTrue, reason: 'square $square');
      }
    });

    test('exactly 8 squares are safe', () {
      final safe = [for (var s = 0; s < trackLength; s++) if (isSafeSquare(s)) s];
      expect(safe, [0, 8, 13, 21, 26, 34, 39, 47]);
    });
  });

  group('checkCapture', () {
    test('returns opponent token occupying destSquare', () {
      final greenToken = tokenAt(PlayerColor.green, 5); // square 17
      final state = stateWith([
        playerWith(PlayerColor.red, []),
        playerWith(PlayerColor.green, [greenToken]),
      ]);

      expect(checkCapture(17, PlayerColor.red, state), greenToken);
    });

    test('returns null when destSquare is empty', () {
      final state = stateWith([
        playerWith(PlayerColor.red, []),
        playerWith(PlayerColor.green, []),
      ]);

      expect(checkCapture(17, PlayerColor.red, state), isNull);
    });

    test('returns null on a start square even if an opponent sits there', () {
      final greenToken = tokenAt(PlayerColor.green, 1); // square 13
      final state = stateWith([
        playerWith(PlayerColor.red, []),
        playerWith(PlayerColor.green, [greenToken]),
      ]);

      expect(checkCapture(13, PlayerColor.red, state), isNull);
    });

    test('returns null on a star square even if an opponent sits there', () {
      final greenToken = tokenAt(PlayerColor.green, 9); // square 21, a star
      final state = stateWith([
        playerWith(PlayerColor.red, []),
        playerWith(PlayerColor.green, [greenToken]),
      ]);

      expect(checkCapture(21, PlayerColor.red, state), isNull);
    });

    test('ignores tokens of the moving color (no self-capture)', () {
      final redToken = tokenAt(PlayerColor.red, 5); // square 4
      final state = stateWith([playerWith(PlayerColor.red, [redToken])]);

      expect(checkCapture(4, PlayerColor.red, state), isNull);
    });

    test('ignores tokens still in the yard', () {
      final greenToken = Token(id: 'g1', color: PlayerColor.green);
      final state = stateWith([
        playerWith(PlayerColor.red, []),
        playerWith(PlayerColor.green, [greenToken]),
      ]);

      for (var square = 0; square < trackLength; square++) {
        expect(checkCapture(square, PlayerColor.red, state), isNull);
      }
    });

    test('ignores tokens in the private home stretch', () {
      final greenToken = tokenAt(PlayerColor.green, 52);
      final state = stateWith([
        playerWith(PlayerColor.red, []),
        playerWith(PlayerColor.green, [greenToken]),
      ]);

      for (var square = 0; square < trackLength; square++) {
        expect(checkCapture(square, PlayerColor.red, state), isNull);
      }
    });
  });

  group('capturableTokensAt', () {
    test('returns every token of a stacked opponent pair', () {
      final g1 = tokenAt(PlayerColor.green, 5, id: 'g1'); // square 17
      final g2 = tokenAt(PlayerColor.green, 5, id: 'g2');
      final state = stateWith([
        playerWith(PlayerColor.red, []),
        playerWith(PlayerColor.green, [g1, g2]),
      ]);

      expect(capturableTokensAt(17, PlayerColor.red, state), [g1, g2]);
    });

    test('is empty on a safe square', () {
      final g1 = tokenAt(PlayerColor.green, 9, id: 'g1'); // square 21, star
      final state = stateWith([
        playerWith(PlayerColor.red, []),
        playerWith(PlayerColor.green, [g1]),
      ]);

      expect(capturableTokensAt(21, PlayerColor.red, state), isEmpty);
    });
  });
}
