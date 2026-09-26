import 'token.dart';

class Move {
  Move({
    required this.token,
    required this.newDistance,
    required this.isBackward,
    this.capturedToken,
  });

  final Token token;
  final int newDistance;
  final bool isBackward;

  /// Null if this move doesn't capture an opponent token. If several
  /// opponent tokens are stacked on the destination, this is one of them;
  /// applyMove (turn_manager.dart) sends all of them back to the yard.
  final Token? capturedToken;
}
