import 'package:flutter/foundation.dart';

import '../rules_engine/models/game_state.dart';
import '../rules_engine/models/move.dart';
import '../rules_engine/models/player.dart';
import '../rules_engine/models/token.dart';

/// Shared Contract (README Section 6). Vedant implements this for real;
/// Aditi's Flame/UI layers depend only on this shape.
///
/// TODO(Vedant): implement in V6.
class GameController extends ChangeNotifier {
  GameState get state => throw UnimplementedError('V6 — GameController not yet implemented');

  List<Move> get currentLegalMoves => throw UnimplementedError('V6 — GameController not yet implemented');

  void rollDice() => throw UnimplementedError('V6 — GameController not yet implemented');

  void selectMove(Move move) => throw UnimplementedError('V6 — GameController not yet implemented');

  // Callbacks Aditi's Flame layer listens to, to trigger animation + sound.
  void Function(Move move)? onMoveAnimated;
  void Function(Token captured)? onCapture;
  void Function(PlayerColor winner)? onGameOver;
}
