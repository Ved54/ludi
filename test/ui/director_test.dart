import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';
import 'package:ludi/game/components/board_component.dart';
import 'package:ludi/game/components/dice_component.dart';
import 'package:ludi/game/components/path_waypoints.dart';
import 'package:ludi/game/components/toast_component.dart';
import 'package:ludi/game/components/token_component.dart';
import 'package:ludi/game/ludi_game.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';
import 'package:ludi/state/game_controller.dart';

import '../helpers/fixtures.dart';
import 'playtest_harness.dart';

/// How LudiGame turns taps into moves in the awkward spots: two options
/// for one token, two tokens aiming at one square, taps on markers that
/// aren't showing. Positions are hand-built; the die is scripted.
void main() {
  // Blue token on shared square 12 — not a safe square.
  Token blueVictim() => tokenAt(PlayerColor.blue, distanceOn(PlayerColor.blue, 12), id: 'blue0');
  List<Token> yard(PlayerColor color, List<int> slots) => [
    for (final i in slots) Token(id: '${color.name}$i', color: color),
  ];

  Future<LudiGame> start(
    WidgetTester tester, {
    required List<Token> red,
    required List<Token> blue,
    required List<int> rolls,
    bool roll = true,
  }) async {
    final controller = GameController(
      initialState: stateWith([playerWith(PlayerColor.red, red), playerWith(PlayerColor.blue, blue)]),
      random: ScriptedRandom(rolls),
      holdMovesForAnimation: true,
    );
    final game = await mountGame(tester, controller: controller);
    if (roll) {
      game.requestRoll();
      await pumpSeconds(tester, 1);
    }
    return game;
  }

  Vector2 square(Token t, int distance) => positionForDistance(t.color, distance);
  Vector2 body(LudiGame game, Token t) => game.children
      .whereType<BoardComponent>()
      .single
      .children
      .whereType<TokenComponent>()
      .singleWhere((c) => c.token == t)
      .bodyCenter;

  testWidgets('a lone token with a forward and a backward option is picked for the player', (tester) async {
    final a = tokenAt(PlayerColor.red, 16, id: 'red0');
    final victim = blueVictim();
    final game = await start(
      tester,
      red: [a, ...yard(PlayerColor.red, [1, 2, 3])],
      blue: [victim, ...yard(PlayerColor.blue, [1, 2, 3])],
      rolls: [3],
    );

    expect(game.canSelect, isTrue);
    expect(game.selectedToken, a);
    expect(game.prompt, 'Pick a square');

    // Striking back: the victim flies home, and a listener on the
    // controller (sound, later) still hears about it.
    final heard = <Token>[];
    game.controller.onCapture = heard.add;
    game.onBoardTap(square(a, 13));
    await pumpSeconds(tester, 3);
    expect(a.distance, 13);
    expect(victim.distance, 0);
    expect(heard, [victim]);
    expect(game.controller.onCapture, isNotNull);
    expect(game.prompt, 'Roll again'); // the capture earned a roll
  });

  testWidgets('a square two tokens can reach asks which token instead of guessing', (tester) async {
    final a = tokenAt(PlayerColor.red, 10, id: 'red0'); // forward 3 -> 13
    final b = tokenAt(PlayerColor.red, 16, id: 'red1'); // back 3 -> 13
    final victim = blueVictim();
    final game = await start(
      tester,
      red: [a, b, ...yard(PlayerColor.red, [2, 3])],
      blue: [victim, ...yard(PlayerColor.blue, [1, 2, 3])],
      rolls: [3],
    );

    game.onBoardTap(square(a, 13));
    await pumpSeconds(tester, 0.2);
    expect(game.controller.state.phase, GamePhase.selecting, reason: 'nothing moved');
    expect(game.prompt, 'Tap a token');

    game.onBoardTap(body(game, a));
    await pumpSeconds(tester, 3);
    expect(a.distance, 13);
    expect(b.distance, 16);
    expect(victim.distance, 0);
  });

  testWidgets("with a token picked, other tokens' hidden markers don't play", (tester) async {
    final a = tokenAt(PlayerColor.red, 16, id: 'red0'); // 19, or back 13 (kill)
    final b = tokenAt(PlayerColor.red, 30, id: 'red1'); // 33
    final game = await start(
      tester,
      red: [a, b, ...yard(PlayerColor.red, [2, 3])],
      blue: [blueVictim(), ...yard(PlayerColor.blue, [1, 2, 3])],
      rolls: [3],
    );
    expect(game.selectedToken, isNull);
    expect(game.prompt, 'Pick a token');

    game.onBoardTap(body(game, a));
    expect(game.selectedToken, a);

    game.onBoardTap(square(b, 33)); // b's marker is hidden while a is picked
    await pumpSeconds(tester, 0.2);
    expect(game.controller.state.phase, GamePhase.selecting);
    expect(b.distance, 30);
    expect(game.selectedToken, isNull);
    expect(game.prompt, 'Pick a token');

    game.onBoardTap(square(b, 33)); // now it shows: the first tap previews
    await pumpSeconds(tester, 0.2);
    expect(b.distance, 30);
    expect(game.selectedToken, b);
    expect(game.armedMove?.newDistance, 33);
    expect(game.prompt, 'Tap again');

    game.onBoardTap(square(b, 33)); // the second plays
    await pumpSeconds(tester, 2);
    expect(b.distance, 33);
  });

  testWidgets('a cold marker tap previews; tapping elsewhere drops the preview', (tester) async {
    final a = tokenAt(PlayerColor.red, 20, id: 'red0'); // -> 23
    final b = tokenAt(PlayerColor.red, 30, id: 'red1'); // -> 33
    final game = await start(
      tester,
      red: [a, b, ...yard(PlayerColor.red, [2, 3])],
      blue: yard(PlayerColor.blue, [0, 1, 2, 3]),
      rolls: [3],
    );

    game.onBoardTap(square(a, 23));
    await pumpSeconds(tester, 0.2);
    expect(game.controller.state.phase, GamePhase.selecting, reason: 'one tap never moves');
    expect(game.armedMove?.token, a);

    game.onBoardTap(Vector2(180, 180)); // the middle of the board: nothing there
    expect(game.armedMove, isNull);
    expect(game.selectedToken, isNull);
    expect(game.prompt, 'Pick a token');

    game.onBoardTap(body(game, b)); // a token itself still moves on one tap
    await pumpSeconds(tester, 2);
    expect(b.distance, 33);
    expect(a.distance, 20);
  });

  testWidgets('a third 6 in a row ends the turn, and the pod says why', (tester) async {
    final a = tokenAt(PlayerColor.red, 10, id: 'red0');
    final game = await start(
      tester,
      red: [a, ...yard(PlayerColor.red, [1, 2, 3])],
      blue: yard(PlayerColor.blue, [0, 1, 2, 3]),
      rolls: [6, 6, 6, 1],
    );
    for (final target in [16, 22]) {
      expect(game.prompt, 'Pick a token'); // move a, or bring a token out
      game.onBoardTap(body(game, a));
      await pumpSeconds(tester, 2.5);
      expect(a.distance, target);
      expect(game.prompt, 'Roll again');
      game.requestRoll();
      await pumpSeconds(tester, 1);
    }

    expect(game.prompt, 'Three 6s!');
    expect(game.children.whereType<ToastComponent>().single.text, 'Three 6s · turn over');
    expect(a.distance, 22, reason: 'the first two moves stand');
    await pumpSeconds(tester, 2);
    expect(game.activeColor, PlayerColor.blue);
    expect(game.prompt, 'Tap to roll');
  });

  testWidgets('the die rolls when the finger lifts; dragging off cancels', (tester) async {
    final game = await start(
      tester,
      red: yard(PlayerColor.red, [0, 1, 2, 3]),
      blue: yard(PlayerColor.blue, [0, 1, 2, 3]),
      rolls: [4, 4],
      roll: false,
    );
    final dice = game.children.whereType<DiceComponent>().single;
    final origin = tester.getTopLeft(find.byType(GameWidget<LudiGame>));
    final at = origin + dice.position.toOffset();

    final drag = await tester.startGesture(at);
    await pumpSeconds(tester, 0.1);
    expect(game.canRoll, isTrue, reason: 'nothing happens on touch-down');
    await drag.moveBy(const Offset(0, 80)); // slides off
    await drag.up();
    await pumpSeconds(tester, 0.2);
    expect(game.canRoll, isTrue, reason: 'a drag is not a tap');

    await tester.tapAt(at);
    await pumpSeconds(tester, 0.1);
    expect(game.canRoll, isFalse, reason: 'a real tap rolls');
  });

  testWidgets('a wasted roll says why in the pod', (tester) async {
    final game = await start(
      tester,
      red: yard(PlayerColor.red, [0, 1, 2, 3]),
      blue: yard(PlayerColor.blue, [0, 1, 2, 3]),
      rolls: [4],
    );
    // Die has landed; the turn hasn't passed yet.
    expect(game.activeColor, PlayerColor.red);
    expect(game.prompt, 'Need a 6');
    await pumpSeconds(tester, 2);
    expect(game.activeColor, PlayerColor.blue);
    expect(game.prompt, 'Tap to roll');
  });
}
