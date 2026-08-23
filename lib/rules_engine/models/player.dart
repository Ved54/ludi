import 'token.dart';

/// Four player colors on the shared 52-square track.
enum PlayerColor { red, green, yellow, blue }

class Player {
  Player({
    required this.color,
    required this.startSquare,
    required this.tokens,
    this.isAI = false,
  });

  final PlayerColor color;

  /// Offset into the shared 52-square track (indices 0-51).
  final int startSquare;

  /// 4 tokens per player.
  final List<Token> tokens;

  final bool isAI;
}
