import 'player.dart';

enum TokenState { yard, active, homeStretch, finished }

class Token {
  Token({
    required this.id,
    required this.color,
    this.distance = 0,
    this.state = TokenState.yard,
  });

  final String id;
  final PlayerColor color;

  /// 0 = yard. 1-51 = shared track. 52+ = home stretch.
  int distance;

  TokenState state;
}
