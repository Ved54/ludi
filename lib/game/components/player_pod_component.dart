import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle;

import '../../rules_engine/models/player.dart';
import '../../rules_engine/models/token.dart';
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

  static const double _avatarRadius = 16;

  PlayerColor get color => player.color;

  double get _dockWidth => min(size.y, 64);

  /// Center of the dice dock, in game coordinates.
  Vector2 get diceSlot =>
      position + Vector2(dockOnRight ? size.x - _dockWidth / 2 : _dockWidth / 2, size.y / 2);

  @override
  void onTapDown(TapDownEvent event) {
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

    canvas.saveLayer(size.toRect().inflate(24), Paint()..color = Color.fromRGBO(0, 0, 0, opacity));

    canvas.drawRRect(
      card.shift(Offset(0, 3 + 2 * _active)),
      Paint()
        ..color = Color.lerp(LudiNeutral.textPrimary, palette.deep, _active)!
            .withValues(alpha: 0.10 + 0.14 * _active)
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
    final avatarX = dockOnRight ? contentLeft + 12 + _avatarRadius : contentRight - 12 - _avatarRadius;
    _paintAvatar(canvas, Offset(avatarX, size.y / 2), palette);

    final textX = dockOnRight ? avatarX + _avatarRadius + 10 : avatarX - _avatarRadius - 10;
    final textWidth = contentRight - contentLeft - 2 * _avatarRadius - 30;
    final anchor = dockOnRight ? Anchor.bottomLeft : Anchor.bottomRight;
    final lineAnchor = dockOnRight ? Anchor.topLeft : Anchor.topRight;
    _fitted(canvas, _name, colorLabel(color), Vector2(textX, size.y / 2 + 2), anchor, textWidth);

    final prompt = game.activeColor == color ? game.prompt : null;
    final home = player.tokens.where((t) => t.state == TokenState.finished).length;
    if (prompt != null) {
      final blink = game.canRoll ? 0.75 + 0.25 * sin(_time * 5) : 1.0;
      final style = TextPaint(style: _promptStyle.copyWith(color: palette.deep.withValues(alpha: blink)));
      _fitted(canvas, style, prompt, Vector2(textX, size.y / 2 + 3), lineAnchor, textWidth);
    } else {
      _fitted(canvas, _detail, '$home/4 home', Vector2(textX, size.y / 2 + 3), lineAnchor, textWidth);
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

  void _paintAvatar(Canvas canvas, Offset center, PlayerPalette palette) {
    canvas.drawCircle(center, _avatarRadius, Paint()..color = palette.base);
    canvas.save();
    canvas.translate(center.dx, center.dy + 9);
    canvas.scale(0.78);
    paintPawn(canvas, color, shadow: false);
    canvas.restore();

    // Progress ring: one segment per token home.
    final home = player.tokens.where((t) => t.state == TokenState.finished).length;
    final ring = Rect.fromCircle(center: center, radius: _avatarRadius + 4.5);
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
