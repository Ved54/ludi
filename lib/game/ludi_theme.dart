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

  /// The board card the cells sit on — shows through the gaps between
  /// cells as the grid.
  static const Color boardBase = Color(0xFFEFE7DA);

  /// Cards and panels floating over the page (HUD pods, dice face).
  static const Color surface = Color(0xFFFFFDF9);

  /// The dice's shaded side, faking depth.
  static const Color diceSide = Color(0xFFE6DDCF);

  /// Yard panel for a color nobody is playing this game.
  static const Color emptyYard = Color(0xFFE9E2D6);
}

/// Typeface from style guide section 3, bundled in assets/fonts/.
const String ludiFontFamily = 'Nunito';

String colorLabel(PlayerColor color) =>
    color.name[0].toUpperCase() + color.name.substring(1);

/// Motion timings, in seconds — one place to tune the game's feel.
class LudiMotion {
  /// One square of a multi-square move.
  static const double hopStep = 0.14;

  /// Arc height of a single hop, board units (one cell = 24).
  static const double hopHeight = 7;

  /// Leaving the yard for the start square.
  static const double enterDuration = 0.38;
  static const double enterHeight = 24;

  /// A captured token flying home to its yard.
  static const double knockDuration = 0.6;
  static const double knockHeight = 48;

  static const double diceTumble = 0.65;
  static const double diceTravel = 0.38;

  /// Beat between a roll landing and the game acting on it (auto-move,
  /// passing a wasted turn) so the player can read the die first.
  static const double readBeat = 0.4;
  static const double wastedRollHold = 0.75;
}
