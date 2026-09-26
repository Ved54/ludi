import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/game/components/board_component.dart';
import 'package:ludi/game/components/dice_component.dart';
import 'package:ludi/game/components/path_waypoints.dart';
import 'package:ludi/game/components/token_component.dart';
import 'package:ludi/game/ludi_game.dart';
import 'package:ludi/game/ludi_theme.dart';
import 'package:ludi/main.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/ui/game_screen.dart';

/// Plays whole games through the real screen with real taps — die, then
/// tokens (or a marker when a token has two options) — to prove the
/// animation director never deadlocks, plays on past the first finisher,
/// and always hands over to the standings card.
void main() {
  Future<void> playToTheEnd(WidgetTester tester, List<PlayerColor> colors) async {
    tester.view.physicalSize = const Size(1080, 2424);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: GameScreen(colors: colors)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final game = tester.widget<GameWidget<LudiGame>>(find.byType(GameWidget<LudiGame>)).game!;
    final origin = tester.getTopLeft(find.byType(GameWidget<LudiGame>));
    final board = game.children.whereType<BoardComponent>().single;
    final dice = game.children.whereType<DiceComponent>().single;
    Offset onBoard(Vector2 local) =>
        origin + (board.basePosition + local * board.scale.x).toOffset();

    var actions = 0;
    while (game.controller.state.phase != GamePhase.gameOver) {
      expect(++actions, lessThan(20000), reason: 'input never unlocked');
      if (game.canRoll) {
        await tester.tapAt(origin + dice.position.toOffset());
      } else if (game.canSelect) {
        final move = game.controller.currentLegalMoves.first;
        final token = board.children
            .whereType<TokenComponent>()
            .singleWhere((c) => c.token == move.token);
        await tester.tapAt(onBoard(token.bodyCenter));
        await tester.pump(const Duration(milliseconds: 30));
        if (game.canSelect) {
          await tester.tapAt(onBoard(positionForDistance(move.token.color, move.newDistance)));
        }
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final state = game.controller.state;
    expect(state.finishOrder, hasLength(colors.length - 1), reason: 'played on for every place');
    expect(find.text('${colorLabel(state.finishOrder.first)} wins!'), findsOneWidget);
    expect(state.standings.toSet(), colors.toSet());
  }

  testWidgets('a 2-player game plays through to the standings card', (tester) async {
    await playToTheEnd(tester, [PlayerColor.red, PlayerColor.yellow]);
  });

  testWidgets('a 4-player game plays through to the standings card', (tester) async {
    await playToTheEnd(tester, PlayerColor.values);
  });

  testWidgets('pausing mid-move freezes it, and leaving mid-move goes home cleanly', (tester) async {
    tester.view.physicalSize = const Size(1080, 2424);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LudiApp());
    await tester.tap(find.text('Play'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final game = tester.widget<GameWidget<LudiGame>>(find.byType(GameWidget<LudiGame>)).game!;
    final origin = tester.getTopLeft(find.byType(GameWidget<LudiGame>));
    final dice = game.children.whereType<DiceComponent>().single;

    // Play until a token is in the air.
    for (var i = 0; game.controller.state.phase != GamePhase.animating; i++) {
      expect(i, lessThan(20000));
      if (game.canRoll) await tester.tapAt(origin + dice.position.toOffset());
      if (game.canSelect) {
        final move = game.controller.currentLegalMoves.first;
        game.onBoardTap(positionForDistance(move.token.color, move.newDistance));
      }
      await tester.pump(const Duration(milliseconds: 16));
    }

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(game.controller.state.phase, GamePhase.animating, reason: 'nothing moves while away');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 16));

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Leave this game?'), findsOneWidget);
    await tester.tap(find.text('Leave'));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('How to play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
