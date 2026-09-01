import 'dart:ui';

import 'package:flame/game.dart';

import '../state/game_controller.dart';
import 'components/board_component.dart';
import 'components/path_waypoints.dart';
import 'components/token_component.dart';
import 'ludi_theme.dart';

/// Flame game root — wires GameController to BoardComponent plus one
/// TokenComponent per token, so the current game state renders live.
/// Dice, HUD, and menu chrome are later tasks (A3, A6); this is just
/// enough to see the board and tokens for real.
class LudiGame extends FlameGame {
  LudiGame({GameController? controller})
      : controller = controller ?? GameController();

  final GameController controller;

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
  }
}
