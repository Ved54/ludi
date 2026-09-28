import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/game/components/board_component.dart';
import 'package:ludi/game/components/path_waypoints.dart';
import 'package:ludi/game/components/player_pod_component.dart';
import 'package:ludi/game/ludi_game.dart';
import 'package:ludi/main.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/ui/game_screen.dart';

/// Screens across phone sizes and system font sizes: nothing overflows,
/// and the game's board, HUD pods and die all fit on screen without
/// running into each other.
void main() {
  const screens = {
    'small phone 320x568': (Size(640, 1136), 2.0),
    'compact 360x640': (Size(720, 1280), 2.0),
    'tall phone 411x923': (Size(1080, 2424), 2.625),
    'short wide 360x640@3': (Size(1080, 1920), 3.0),
    'tablet 800x1280': (Size(1600, 2560), 2.0),
    'foldable 690x829': (Size(1812, 2176), 2.625),
  };

  Future<void> setScreen(WidgetTester tester, (Size, double) screen, {double text = 1}) async {
    tester.view.physicalSize = screen.$1;
    tester.view.devicePixelRatio = screen.$2;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    for (final text in [1.0, 1.3, 2.0]) {
      testWidgets('home and rules fit: $name, text x$text', (tester) async {
        await setScreen(tester, screen, text: text);
        await tester.pumpWidget(const LudiApp());
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'home screen');

        await tester.ensureVisible(find.text('How to play'));
        await tester.tap(find.text('How to play'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'rules sheet');
        expect(find.text('Win'), findsOneWidget);
      });
    }

    testWidgets('game layout fits: $name', (tester) async {
      await setScreen(tester, screen);
      await tester.pumpWidget(const MaterialApp(home: GameScreen(colors: PlayerColor.values)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final game = tester.widget<GameWidget<LudiGame>>(find.byType(GameWidget<LudiGame>)).game!;
      final view = Offset.zero & game.size.toSize();
      final board = game.children.whereType<BoardComponent>().single;
      final boardRect = board.basePosition.toOffset() & Size.square(boardSize * board.scale.x);
      expect(boardRect.top, greaterThanOrEqualTo(LudiGame.topInset), reason: 'clear of the back button');
      expect(view.inflate(0.5).contains(boardRect.bottomRight), isTrue);
      expect(boardRect.left, greaterThanOrEqualTo(0));

      for (final pod in game.children.whereType<PlayerPodComponent>()) {
        final rect = pod.position.toOffset() & pod.size.toSize();
        expect(view.inflate(0.5).contains(rect.topLeft) && view.inflate(0.5).contains(rect.bottomRight), isTrue,
            reason: '${pod.color} pod on screen');
        expect(rect.overlaps(boardRect), isFalse, reason: '${pod.color} pod clear of the board');
        expect(rect.top, greaterThanOrEqualTo(LudiGame.topInset));
        expect(rect.contains(pod.diceSlot.toOffset()), isTrue, reason: 'die docks inside the pod');
        expect(pod.size.y, greaterThanOrEqualTo(48), reason: 'pod is a usable tap target');
      }
    });
  }

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    testWidgets('standings card fits: $name, text x2.0', (tester) async {
      await setScreen(tester, screen, text: 2);
      await tester.pumpWidget(const MaterialApp(home: GameScreen(colors: PlayerColor.values)));
      await tester.pump(const Duration(milliseconds: 16));
      final game = tester.widget<GameWidget<LudiGame>>(find.byType(GameWidget<LudiGame>)).game!;
      game.controller.state
        ..finishOrder.addAll([PlayerColor.blue, PlayerColor.red, PlayerColor.green, PlayerColor.yellow])
        ..phase = GamePhase.gameOver;
      tester.element(find.byType(GameScreen)).markNeedsBuild();
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('Blue wins!'), findsOneWidget);
      for (final place in ['2nd', '3rd', '4th']) {
        expect(find.text(place), findsOneWidget);
      }
      await tester.ensureVisible(find.text('Play again'));
      expect(find.text('Play again').hitTestable(), findsOneWidget);
    });
  }
}
