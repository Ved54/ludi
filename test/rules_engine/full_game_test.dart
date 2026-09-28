import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/capture_logic.dart';
import 'package:ludi/rules_engine/legal_moves.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/token.dart';
import 'package:ludi/rules_engine/turn_manager.dart' show sixesToForfeit;
import 'package:ludi/state/game_controller.dart';

/// Board-wide rules that must hold between any two player actions.
void expectConsistent(GameState state, String where) {
  final tokens = state.players.expand((p) => p.tokens).toList();

  for (final t in tokens) {
    expect(t.distance, inInclusiveRange(0, maxDistance), reason: '$where ${t.id}');
    expect(t.state, stateForDistance(t.distance), reason: '$where ${t.id}');
  }

  // A non-safe shared square never holds two colors: landing captures.
  final colorsBySquare = <int, Set<Object>>{};
  for (final t in tokens.where((t) => isOnSharedTrack(t.distance))) {
    final square = toSharedSquare(t.color, t.distance);
    if (!isSafeSquare(square)) {
      (colorsBySquare[square] ??= {}).add(t.color);
    }
  }
  for (final entry in colorsBySquare.entries) {
    expect(entry.value.length, 1, reason: '$where square ${entry.key}');
  }

  for (final move in state.legalMoves) {
    expect(move.token.color, state.currentPlayer.color, reason: where);
    expect(isValidDestination(move.newDistance), isTrue, reason: where);
    if (move.isBackward) expect(move.capturedToken, isNotNull, reason: where);
  }

  expect(
    state.phase,
    isNot(GamePhase.animating),
    reason: '$where: the controller never rests mid-move',
  );

  // Finishers are done: all home, and never up to play again.
  final finishers = state.phase == GamePhase.gameOver
      ? state.finishOrder.sublist(0, state.finishOrder.length - 1)
      : state.finishOrder;
  for (final color in finishers) {
    final player = state.players.firstWhere((p) => p.color == color);
    expect(player.tokens.every((t) => t.state == TokenState.finished), isTrue, reason: where);
  }
  expect(state.sixesInARow, lessThan(sixesToForfeit), reason: where);
  if (state.phase != GamePhase.gameOver) {
    expect(state.finishOrder, isNot(contains(state.currentPlayer.color)), reason: where);
  }
}

void main() {
  test('random 4-player games always finish with a consistent board', () {
    for (var seed = 0; seed < 40; seed++) {
      final rng = Random(seed);
      final controller = GameController(random: rng);
      final state = controller.state;
      var actions = 0;

      while (state.phase != GamePhase.gameOver) {
        expect(++actions, lessThan(20000), reason: 'seed $seed never ended');
        if (state.phase == GamePhase.rolling) {
          controller.rollDice();
        } else {
          final moves = controller.currentLegalMoves;
          controller.selectMove(moves[rng.nextInt(moves.length)]);
        }
        expectConsistent(state, 'seed $seed action $actions');
      }

      // Play went on until a single player was left, who takes last place.
      expect(state.finishOrder.toSet(), state.players.map((p) => p.color).toSet(), reason: 'seed $seed');
      expect(state.finishOrder, hasLength(state.players.length), reason: 'seed $seed');
      final last = state.players.firstWhere((p) => p.color == state.finishOrder.last);
      expect(
        last.tokens.every((t) => t.state == TokenState.finished),
        isFalse,
        reason: 'seed $seed: last place still had tokens out',
      );
    }
  });
}
