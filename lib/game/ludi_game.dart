import 'dart:ui';

import 'package:flame/game.dart';

import '../state/game_controller.dart';
import 'components/board_component.dart';
import 'components/dice_component.dart';
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

    // Bottom-center, below the board — dice is HUD-level, not part of the
    // board's own coordinate space. Full HUD chrome (turn indicator, menu
    // icons) is A6's job; this is just enough to place it sensibly.
    final dice = DiceComponent(controller: controller);
    dice.position = Vector2(
      (size.x - dice.size.x) / 2,
      size.y - dice.size.y - 24,
    );
    await add(dice);
  }
}
