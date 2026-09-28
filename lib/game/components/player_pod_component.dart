import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../../rules_engine/models/player.dart';
import '../ludi_game.dart';
import '../ludi_theme.dart';
import '../token_painter.dart';

/// A player's HUD card, sitting outside the board next to that player's
/// yard: avatar with a 4-segment ring counting tokens home, name, and a
/// prompt while it's their turn. Its inner end is the dice dock — the die
/// sits there during this player's turn, and tapping anywhere on the
/// active pod rolls it (a far bigger target than the die alone).
class PlayerPodComponent extends PositionComponent
    with TapCallbacks, HasGameReference<LudiGame> {
  PlayerPodComponent({required this.player, required this.dockOnRight});

  final Player player;

  /// Left-column pods dock the die on their right (toward the middle of
  /// the screen) and read left to right; right-column pods mirror that.
  final bool dockOnRight;

  double _active = 0;
  double _time = 0;

  /// Width the name and prompt need — the longest prompts ("Pick a
  /// square", "Roll again ×2") still render at ~90% size.
  static const double _textRoom = 68;

  /// The avatar shrinks, then goes, on narrow pods so the name and prompt
  /// keep a readable size — a 360 dp phone leaves only ~160 dp per pod,
  /// most of it taken by the dice dock.
  double get _avatarRadius {
    final room = size.x - _dockWidth - 8;
    if (room - _avatarSpan(16) >= _textRoom) return 16;
    if (room - _avatarSpan(11) >= _textRoom) return 11;
    return 0;
  }

  /// Horizontal space an avatar of [radius] takes, margins included.
  static double _avatarSpan(double radius) => radius == 0 ? 12 : 2 * radius + 22;

  PlayerColor get color => player.color;

  /// Tokens this pod counts as home — the ones the board has shown
  /// arriving, not the engine's tally (which runs ahead during a hop).
  int get homeCount => game.shownHomeCount(color);

  /// This player's final place once they have one — on finishing, or last
  /// place for whoever is left when the game ends.
  int? get place {
    final index = game.controller.state.finishOrder.indexOf(color);
    return index < 0 ? null : index + 1;
  }

  double get _dockWidth => min(size.y, 64);

  /// Center of the dice dock, in game coordinates.
  Vector2 get diceSlot =>
      position + Vector2(dockOnRight ? size.x - _dockWidth / 2 : _dockWidth / 2, size.y / 2);

  // Acts when the finger lifts, like a button: sliding off cancels.
  @override
  void onTapUp(TapUpEvent event) {
    if (game.activeColor == color) game.requestRoll();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    final target = game.activeColor == color ? 1.0 : 0.0;
    _active += (target - _active) * min(1, dt * 8);
  }

  @override
  void render(Canvas canvas) {
    final palette = playerPalette[color]!;
    final card = RRect.fromRectAndRadius(size.toRect(), const Radius.circular(18));
    final opacity = 0.62 + 0.38 * _active;

    canvas.save();
    canvas.drawRRect(
      card.shift(Offset(0, 3 + 2 * _active)),
      Paint()
        ..color = Color.lerp(LudiNeutral.textPrimary, palette.deep, _active)!
            .withValues(alpha: (0.10 + 0.14 * _active) * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 6 * _active),
    );
    canvas.drawRRect(card, Paint()..color = LudiNeutral.surface);
    if (_active > 0.01) {
      canvas.drawRRect(
        card.deflate(1.25),
        Paint()
          ..color = palette.base.withValues(alpha: _active)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // Dice dock.
    final dock = RRect.fromRectAndRadius(
      Rect.fromCenter(center: (diceSlot - position).toOffset(), width: _dockWidth - 10, height: _dockWidth - 10),
      const Radius.circular(14),
    );
    canvas.drawRRect(dock, Paint()..color = LudiNeutral.boardBase.withValues(alpha: 0.7));

    final contentLeft = dockOnRight ? 0.0 : _dockWidth;
    final contentRight = dockOnRight ? size.x - _dockWidth : size.x;
    final radius = _avatarRadius;
    final span = _avatarSpan(radius);
    if (radius > 0) {
      final avatarX = dockOnRight ? contentLeft + 12 + radius : contentRight - 12 - radius;
      _paintAvatar(canvas, Offset(avatarX, size.y / 2), palette, radius);
    }

    final textX = dockOnRight ? contentLeft + span : contentRight - span;
    final textWidth = contentRight - contentLeft - span - 8;
    final anchor = dockOnRight ? Anchor.bottomLeft : Anchor.bottomRight;
    final lineAnchor = dockOnRight ? Anchor.topLeft : Anchor.topRight;
    // Without an avatar the name carries the color.
    final name = radius > 0 ? _name : _coloredName[color]!;
    _fitted(canvas, name, colorLabel(color), Vector2(textX, size.y / 2 + 2), anchor, textWidth);

    final prompt = game.activeColor == color ? game.prompt : null;
    if (prompt != null) {
      final blink = game.canRoll ? 0.75 + 0.25 * sin(_time * 5) : 1.0;
      final style = TextPaint(style: _promptStyle.copyWith(color: palette.deep.withValues(alpha: blink)));
      _fitted(canvas, style, prompt, Vector2(textX, size.y / 2 + 3), lineAnchor, textWidth);
    } else if (place case final place?) {
      final style = TextPaint(style: _promptStyle.copyWith(color: palette.deep));
      _fitted(canvas, style, '${placeLabel(place)} place', Vector2(textX, size.y / 2 + 3), lineAnchor, textWidth);
    } else {
      _fitted(canvas, _detail, '$homeCount/4 home', Vector2(textX, size.y / 2 + 3), lineAnchor, textWidth);
    }

    // Fade an inactive pod into the page by veiling it in the page color —
    // the same result as drawing it translucent (the page behind is one
    // flat color) without an offscreen layer per pod every frame.
    if (opacity < 0.999) {
      canvas.drawRRect(card, Paint()..color = LudiNeutral.boardBackground.withValues(alpha: 1 - opacity));
    }
    canvas.restore();
  }

  /// Renders [text], shrunk if needed so it never runs into the dock.
  void _fitted(Canvas canvas, TextPaint paint, String text, Vector2 at, Anchor anchor, double maxWidth) {
    final width = paint.toTextPainter(text).width;
    final fit = width > maxWidth ? maxWidth / width : 1.0;
    canvas.save();
    canvas.translate(at.x, at.y);
    canvas.scale(fit);
    paint.render(canvas, text, Vector2.zero(), anchor: anchor);
    canvas.restore();
  }

  void _paintAvatar(Canvas canvas, Offset center, PlayerPalette palette, double radius) {
    canvas.drawCircle(center, radius, Paint()..color = palette.base);
    canvas.save();
    canvas.translate(center.dx, center.dy + 9 * radius / 16);
    canvas.scale(0.78 * radius / 16);
    paintPawn(canvas, color, shadow: false);
    canvas.restore();

    // Progress ring: one segment per token home.
    final home = homeCount;
    final ring = Rect.fromCircle(center: center, radius: radius + 4.5);
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(
        ring,
        -pi / 2 + i * pi / 2 + 0.16,
        pi / 2 - 0.32,
        false,
        Paint()
          ..color = i < home ? palette.deep : LudiNeutral.gridLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  static final TextPaint _name = TextPaint(
    style: const TextStyle(
      fontFamily: ludiFontFamily,
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: LudiNeutral.textPrimary,
      height: 1.1,
    ),
  );

  static final Map<PlayerColor, TextPaint> _coloredName = {
    for (final color in PlayerColor.values)
      color: TextPaint(style: _name.style.copyWith(color: playerPalette[color]!.deep)),
  };

  static const TextStyle _promptStyle = TextStyle(
    fontFamily: ludiFontFamily,
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    height: 1.1,
  );

  static final TextPaint _detail = TextPaint(
    style: _promptStyle.copyWith(
      color: LudiNeutral.textSecondary,
      fontWeight: FontWeight.w700,
    ),
  );
}
