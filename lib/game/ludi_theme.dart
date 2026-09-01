import 'dart:ui';

import '../rules_engine/models/player.dart';

/// Ludi's flat, minimal visual language (A1 — design/visual_style_guide.md).
/// Single source of truth for color; every rendering component pulls from
/// here rather than hardcoding hex values.

class PlayerPalette {
  const PlayerPalette({
    required this.base,
    required this.deep,
    required this.light,
  });

  /// Tokens, this player's home yard fill, solid safe-square fill.
  final Color base;

  /// Outlines, shadows, pressed states.
  final Color deep;

  /// This player's path tint (yard panel background, home-lane cells).
  final Color light;
}

const Map<PlayerColor, PlayerPalette> playerPalette = {
  PlayerColor.red: PlayerPalette(
    base: Color(0xFFE8746B),
    deep: Color(0xFFC6564D),
    light: Color(0xFFF7D9D6),
  ),
  PlayerColor.green: PlayerPalette(
    base: Color(0xFF6FBE8E),
    deep: Color(0xFF4E9A6D),
    light: Color(0xFFD8EFE2),
  ),
  PlayerColor.yellow: PlayerPalette(
    base: Color(0xFFF0C25E),
    deep: Color(0xFFD1A03D),
    light: Color(0xFFFBEBC9),
  ),
  PlayerColor.blue: PlayerPalette(
    base: Color(0xFF6C94D6),
    deep: Color(0xFF4E74B5),
    light: Color(0xFFDAE5F5),
  ),
};

class LudiNeutral {
  static const Color boardBackground = Color(0xFFFAF6F0);
  static const Color trackSquare = Color(0xFFFFFFFF);
  static const Color gridLine = Color(0xFFE4DCD0);
  static const Color textPrimary = Color(0xFF3A342C);
  static const Color textSecondary = Color(0xFF8A8175);
}
