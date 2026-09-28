import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/models/player.dart';

import 'playtest_harness.dart';

/// Full 4-player games played through real taps, with every frame checked
/// against the rules engine (see Playtester) — plus one game with an
/// impatient player tapping everywhere mid-animation. Seeds are fixed so
/// a failure replays exactly.
void main() {
  Future<void> play(WidgetTester tester, int seed, {bool chaos = false}) async {
    final game = await mountGame(tester, colors: PlayerColor.values, seed: seed);
    final report = await Playtester(tester, game, seed: seed, chaos: chaos).playGame();
    // ignore: avoid_print
    print('seed $seed${chaos ? ' (chaos)' : ''}: $report');
    expect(report.violationLog, isEmpty);
    expect(report.winner, isNotNull);
  }

  const timeout = Timeout(Duration(minutes: 10));
  for (final seed in [1, 2, 3]) {
    testWidgets('4-player game, seed $seed, plays clean', (t) => play(t, seed), timeout: timeout);
  }
  testWidgets('4-player game with random taps everywhere plays clean', (t) => play(t, 11, chaos: true), timeout: timeout);
}
