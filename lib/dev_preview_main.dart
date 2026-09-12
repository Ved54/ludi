// TEMPORARY — standalone debug harness for trying the game by hand,
// PLUS a tap-to-select-move overlay that doesn't exist in the real app
// yet (that's A4/A6's job) so a full roll -> move -> next-turn cycle is
// actually testable. Not part of the app; delete when done testing.
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/components/board_component.dart';
import 'game/components/dice_component.dart';
import 'game/components/path_waypoints.dart';
import 'game/components/token_component.dart';
import 'game/ludi_theme.dart';
import 'state/game_controller.dart';

void main() {
  runApp(
    MaterialApp(
      home: Scaffold(body: GameWidget(game: _DebugGame())),
    ),
  );
}

class _DebugGame extends FlameGame {
  final controller = GameController();

  @override
  Color backgroundColor() => LudiNeutral.boardBackground;

  @override
  Future<void> onLoad() async {
    final board = BoardComponent(controller: controller)
      ..position = (size - Vector2.all(boardSize)) / 2;
    await add(board);

    for (final player in controller.state.players) {
      for (final token in player.tokens) {
        await board.add(TokenComponent(token: token));
      }
    }

    // DEBUG ONLY: tap a highlighted legal-move square to actually apply
    // it, so dice -> real token movement -> next turn is testable now.
    await board.add(_DebugMoveSelector(controller: controller));

    final dice = DiceComponent(controller: controller);
    dice.position = Vector2(
      (size.x - dice.size.x) / 2,
      size.y - dice.size.y - 24,
    );
    await add(dice);
  }
}

class _DebugMoveSelector extends PositionComponent with TapCallbacks {
  _DebugMoveSelector({required this.controller})
      : super(size: Vector2.all(boardSize));

  final GameController controller;

  @override
  void onTapDown(TapDownEvent event) {
    final tap = event.localPosition;
    for (final move in controller.currentLegalMoves) {
      final dest = positionForDistance(move.token.color, move.newDistance);
      if ((dest - tap).length < 16) {
        controller.selectMove(move);
        return;
      }
    }
  }
}
