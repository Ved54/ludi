import 'dart:math';
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ludi/game/components/board_component.dart';
import 'package:ludi/game/components/dice_component.dart';
import 'package:ludi/game/components/path_waypoints.dart';
import 'package:ludi/game/components/player_pod_component.dart';
import 'package:ludi/game/components/token_component.dart';
import 'package:ludi/game/ludi_game.dart';
import 'package:ludi/main.dart';
import 'package:ludi/rules_engine/legal_moves.dart';
import 'package:ludi/rules_engine/models/game_state.dart';

/// On-device playtest: launches the real app, starts a 4-player game from
/// the home screen, and plays it to the standings card (until three
/// players have finished) with real taps in real time — then "Play
/// again", three games in a row. At every point where the game accepts
/// input it checks the screen against the rules engine, and it reports
/// frame timings at the end.
///
///   `flutter test integration_test/full_house_test.dart -d <device-id>`
///
/// Add `--dart-define=GAMES=1` for a single game.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const games = int.fromEnvironment('GAMES', defaultValue: 3);

  testWidgets('full-house games, start to standings card', (tester) async {
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);
    final clock = Stopwatch()..start();
    final rng = Random();
    final problems = <String>[];
    void log(String line) =>
        // ignore: avoid_print
        print('[${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s ${DateTime.now().toIso8601String().substring(11, 19)}] $line');

    Future<void> wait(int ms) => tester.pump(Duration(milliseconds: ms));

    await tester.pumpWidget(const LudiApp());
    await wait(1500);
    await tester.tap(find.text('Play'));
    await wait(1200);

    for (var gameNo = 1; gameNo <= games; gameNo++) {
      final game = tester.widget<GameWidget<LudiGame>>(find.byType(GameWidget<LudiGame>)).game!;
      final origin = tester.getTopLeft(find.byType(GameWidget<LudiGame>));
      final board = game.children.whereType<BoardComponent>().single;
      final dice = game.children.whereType<DiceComponent>().single;
      final pods = {for (final p in game.children.whereType<PlayerPodComponent>()) p.color: p};
      final tokens = board.children.whereType<TokenComponent>().toList();
      Offset onBoard(Vector2 local) => origin + (board.basePosition + local * board.scale.x).toOffset();
      final state = game.controller.state;
      log('game $gameNo started');

      var rolls = 0, moves = 0, captures = 0, finishes = 0, lastPlaced = 0;
      void check(String where) {
        void bad(String what) {
          final line = 'game $gameNo $where: $what';
          if (problems.length < 40) problems.add(line);
          log('PROBLEM $line');
        }

        for (final c in tokens) {
          if (c.isAnimating) bad('${c.token.id} still animating');
          if (c.shownDistance != c.token.distance) {
            bad('${c.token.id} shown ${c.shownDistance} engine ${c.token.distance}');
          }
          if (c.position.distanceTo(c.restPosition) > 1) bad('${c.token.id} not at rest spot');
        }
        if (game.activeColor != state.currentPlayer.color) bad('active pod ${game.activeColor}');
        if (dice.position.distanceTo(pods[game.activeColor]!.diceSlot) > 1) bad('die not docked');
        for (final pod in pods.values) {
          final home = tokens.where((c) => c.token.color == pod.color && c.token.distance == maxDistance).length;
          if (pod.homeCount != home) bad('${pod.color} pod ${pod.homeCount}/4 vs $home');
        }
        if (game.canSelect && dice.face != state.lastRoll) bad('die shows ${dice.face}, rolled ${state.lastRoll}');
      }

      while (state.phase != GamePhase.gameOver) {
        // Wait for the game to take input, like a player watching.
        var waited = 0;
        while (!(game.canRoll || game.canSelect) && state.phase != GamePhase.gameOver) {
          await wait(40);
          waited += 40;
          if (waited > 15000) {
            problems.add('game $gameNo: input locked for 15s (${game.prompt})');
            log('PROBLEM stuck');
            break;
          }
        }
        if (state.phase == GamePhase.gameOver || waited > 15000) break;
        await wait(250 + rng.nextInt(250));
        check(game.canRoll ? 'before roll' : 'before move');

        if (game.canRoll) {
          rolls++;
          await tester.tapAt(origin + dice.position.toOffset());
          await wait(60);
          if (game.canRoll) log('PROBLEM tap on die ignored');
          continue;
        }

        final before = {for (final p in state.players) for (final t in p.tokens) t: t.distance};
        final legal = state.legalMoves;
        final move = legal[rng.nextInt(legal.length)];
        final c = tokens.singleWhere((c) => c.token == move.token);
        await tester.tapAt(onBoard(c.bodyCenter));
        await wait(200);
        if (game.canSelect) {
          await tester.tapAt(onBoard(positionForDistance(move.token.color, move.newDistance)));
          await wait(60);
        }
        if (game.canSelect) {
          log('PROBLEM move not taken (${game.prompt})');
          continue;
        }
        moves++;
        final hit = before.keys.where((t) => t.color != move.token.color && before[t]! > 0 && t.distance == 0);
        if (hit.isNotEmpty) {
          captures++;
          log('capture ${move.token.id} ${move.isBackward ? 'BACKSTRIKE' : 'forward'} -> ${hit.map((t) => t.id)}');
        }
        if (move.token.distance == maxDistance) {
          finishes++;
          log('home ${move.token.id}');
        }
        final placed = state.finishOrder.length;
        if (placed > 0 && placed != lastPlaced) {
          lastPlaced = placed;
          log('place $placed: ${state.finishOrder.last.name}');
        }
      }

      log('game $gameNo over: standings ${state.standings.map((c) => c.name).join(' > ')} after $rolls rolls, '
          '$moves moves, $captures captures, $finishes finishes');
      if (state.finishOrder.length != state.players.length - 1) {
        problems.add('game $gameNo ended with only ${state.finishOrder} placed');
      }
      await wait(2500);
      expect(find.textContaining('wins!'), findsWidgets);
      if (gameNo < games) {
        await tester.tap(find.text('Play again'));
        await wait(1200);
      }
    }
    await tester.tap(find.text('Home'));
    await wait(1000);
    expect(find.text('How to play'), findsOneWidget);

    // Frame timings, whole session.
    List<double> ms(Duration Function(FrameTiming) f) =>
        timings.map((t) => f(t).inMicroseconds / 1000).toList()..sort();
    double pct(List<double> xs, double p) => xs.isEmpty ? 0 : xs[min(xs.length - 1, (xs.length * p).floor())];
    final build = ms((t) => t.buildDuration);
    final raster = ms((t) => t.rasterDuration);
    final total = ms((t) => t.totalSpan);
    log('frames ${timings.length}; build p50 ${pct(build, .5)} p90 ${pct(build, .9)} p99 ${pct(build, .99)} ms; '
        'raster p50 ${pct(raster, .5)} p90 ${pct(raster, .9)} p99 ${pct(raster, .99)} ms; '
        'over 16.7ms: ${total.where((x) => x > 16.7).length}');
    log('problems: ${problems.isEmpty ? 'none' : problems.join('\n')}');
    expect(problems, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 150)));
}
