import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/game/components/board_component.dart';
import 'package:ludi/game/components/dice_component.dart';
import 'package:ludi/game/components/path_waypoints.dart';
import 'package:ludi/game/components/token_component.dart';
import 'package:ludi/game/ludi_game.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/ui/game_screen.dart';

/// Plays whole games through the real screen with real taps — die, then
/// tokens (or a marker when a token has two options) — to prove the
/// animation director never deadlocks and always hands over to the
/// winner card.
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
    final winner = game.controller.state.currentPlayer.color;
    expect(find.textContaining('wins!'), findsOneWidget);
    expect(colors, contains(winner));
  }

  testWidgets('a 2-player game plays through to the winner card', (tester) async {
    await playToTheEnd(tester, [PlayerColor.red, PlayerColor.yellow]);
  });

  testWidgets('a 4-player game plays through to the winner card', (tester) async {
    await playToTheEnd(tester, PlayerColor.values);
  });
}
