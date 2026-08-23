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

  /// Null if this move doesn't capture an opponent token.
  final Token? capturedToken;
}
