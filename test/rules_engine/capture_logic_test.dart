import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/capture_logic.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';

GameState buildState({required List<Player> players}) => GameState(players: players);

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
  });

  group('isSafeSquare', () {
    test('start squares are safe', () {
      expect(isSafeSquare(0), isTrue);
      expect(isSafeSquare(13), isTrue);
      expect(isSafeSquare(26), isTrue);
      expect(isSafeSquare(39), isTrue);
    });

    test('star squares are also safe', () {
      expect(isSafeSquare(9), isTrue);
      expect(isSafeSquare(22), isTrue);
      expect(isSafeSquare(35), isTrue);
      expect(isSafeSquare(48), isTrue);
    });

    test('non-safe squares are not safe', () {
      expect(isSafeSquare(1), isFalse);
      expect(isSafeSquare(50), isFalse);
    });
  });

  group('checkCapture', () {
    test('returns opponent token occupying destSquare', () {
      final redToken = Token(id: 'r1', color: PlayerColor.red, distance: 0);
      final greenToken = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 5,
        state: TokenState.active,
      ); // shared square = 13 + 5 - 1 = 17

      final state = buildState(players: [
        Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken]),
        Player(color: PlayerColor.green, startSquare: 13, tokens: [greenToken]),
      ]);

      final captured = checkCapture(17, PlayerColor.red, state);
      expect(captured, greenToken);
    });

    test('returns null when destSquare is empty', () {
      final state = buildState(players: [
        Player(color: PlayerColor.red, startSquare: 0, tokens: []),
        Player(color: PlayerColor.green, startSquare: 13, tokens: []),
      ]);

      expect(checkCapture(17, PlayerColor.red, state), isNull);
    });

    test('returns null on a safe square even if an opponent sits there', () {
      final greenToken = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 1,
        state: TokenState.active,
      ); // shared square = 13, a start square = safe

      final state = buildState(players: [
        Player(color: PlayerColor.red, startSquare: 0, tokens: []),
        Player(color: PlayerColor.green, startSquare: 13, tokens: [greenToken]),
      ]);

      expect(checkCapture(13, PlayerColor.red, state), isNull);
    });

    test('returns null on a star square even if an opponent sits there', () {
      final greenToken = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 10,
        state: TokenState.active,
      ); // shared square = 13 + 10 - 1 = 22, a star square = safe

      final state = buildState(players: [
        Player(color: PlayerColor.red, startSquare: 0, tokens: []),
        Player(color: PlayerColor.green, startSquare: 13, tokens: [greenToken]),
      ]);

      expect(checkCapture(22, PlayerColor.red, state), isNull);
    });

    test('ignores tokens of the moving color (no self-capture)', () {
      final redToken2 = Token(
        id: 'r2',
        color: PlayerColor.red,
        distance: 5,
        state: TokenState.active,
      ); // shared square = 0 + 5 - 1 = 4

      final state = buildState(players: [
        Player(color: PlayerColor.red, startSquare: 0, tokens: [redToken2]),
      ]);

      expect(checkCapture(4, PlayerColor.red, state), isNull);
    });

    test('ignores tokens still in the yard', () {
      final greenToken = Token(id: 'g1', color: PlayerColor.green, distance: 0);
      // yard token, state defaults to TokenState.yard — not on the track at all.

      final state = buildState(players: [
        Player(color: PlayerColor.red, startSquare: 0, tokens: []),
        Player(color: PlayerColor.green, startSquare: 13, tokens: [greenToken]),
      ]);

      expect(checkCapture(13, PlayerColor.red, state), isNull);
    });

    test('ignores tokens in the private home stretch', () {
      final greenToken = Token(
        id: 'g1',
        color: PlayerColor.green,
        distance: 52,
        state: TokenState.homeStretch,
      );

      final state = buildState(players: [
        Player(color: PlayerColor.red, startSquare: 0, tokens: []),
        Player(color: PlayerColor.green, startSquare: 13, tokens: [greenToken]),
      ]);

      // Even probing the square the home-stretch math would otherwise hit.
      expect(checkCapture(toSharedSquare(PlayerColor.green, 52), PlayerColor.red, state), isNull);
    });
  });
}
