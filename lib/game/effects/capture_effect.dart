import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/particles.dart';

import '../ludi_theme.dart';
import '../token_painter.dart';

final Random _rng = Random();

/// Fading dot that shrinks as it lives.
Particle _dot(Color color, double radius) => ComputedParticle(
  renderer: (canvas, particle) {
    final life = 1 - particle.progress;
    canvas.drawCircle(
      Offset.zero,
      radius * (0.35 + 0.65 * life),
      Paint()..color = color.withValues(alpha: life),
    );
  },
);

/// Impact at the square where a capture lands: a shockwave ring plus a
/// burst of dots in both the attacker's and the victim's colors.
ParticleSystemComponent captureBurst(
  Vector2 at, {
  required Color attacker,
  required Color victim,
}) {
  const count = 22;
  final ring = ComputedParticle(
    lifespan: 0.4,
    renderer: (canvas, particle) {
      final t = particle.progress;
      canvas.drawCircle(
        Offset.zero,
        5 + 22 * (1 - pow(1 - t, 3).toDouble()),
        Paint()
          ..color = attacker.withValues(alpha: 1 - t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t) + 0.5,
      );
    },
  );
  final dots = Particle.generate(
    count: count,
    lifespan: 0.55,
    generator: (i) {
      final angle = i / count * 2 * pi + _rng.nextDouble() * 0.4;
      final direction = Vector2(cos(angle), sin(angle));
      final speed = 60 + _rng.nextDouble() * 90;
      return AcceleratedParticle(
        speed: direction * speed,
        acceleration: direction * -speed * 1.2 + Vector2(0, 90),
        child: _dot(i.isEven ? attacker : victim, 2.2 + _rng.nextDouble() * 1.6),
      );
    },
  );
  return ParticleSystemComponent(
    position: at,
    particle: ComposedParticle(children: [ring, dots]),
  );
}

/// Stars rising off a token that just reached home.
ParticleSystemComponent homeSparkle(Vector2 at, Color color) {
  const count = 14;
  final colors = [color, const Color(0xFFF0C25E), const Color(0xFFFFFFFF)];
  return ParticleSystemComponent(
    position: at,
    particle: Particle.generate(
      count: count,
      lifespan: 0.8,
      generator: (i) {
        final angle = -pi / 2 + (_rng.nextDouble() - 0.5) * 2.4;
        final speed = 40 + _rng.nextDouble() * 70;
        final tint = colors[i % colors.length];
        return AcceleratedParticle(
          speed: Vector2(cos(angle), sin(angle)) * speed,
          acceleration: Vector2(0, 60),
          child: ComputedParticle(
            renderer: (canvas, particle) {
              final life = 1 - particle.progress;
              canvas.save();
              canvas.rotate(particle.progress * 3);
              canvas.drawPath(
                starPath(Offset.zero, outerRadius: 4 * life + 1, innerRadius: 1.8 * life + 0.5),
                Paint()..color = tint.withValues(alpha: life),
              );
              canvas.restore();
            },
          ),
        );
      },
    ),
  );
}

/// Full-screen confetti rain for the winner.
ParticleSystemComponent confetti(Vector2 area, {required Color winner}) {
  final colors = [
    winner,
    winner,
    ...playerPalette.values.map((p) => p.base),
  ];
  return ParticleSystemComponent(
    particle: Particle.generate(
      count: 110,
      lifespan: 3.2,
      generator: (i) {
        final tint = colors[i % colors.length];
        final spin = (_rng.nextDouble() - 0.5) * 14;
        final width = 5 + _rng.nextDouble() * 4;
        return AcceleratedParticle(
          position: Vector2(_rng.nextDouble() * area.x, -20 - _rng.nextDouble() * area.y * 0.4),
          speed: Vector2((_rng.nextDouble() - 0.5) * 80, 60 + _rng.nextDouble() * 120),
          acceleration: Vector2(0, 90),
          child: ComputedParticle(
            renderer: (canvas, particle) {
              final t = particle.progress;
              canvas.save();
              canvas.rotate(spin * t);
              canvas.scale(1, cos(spin * t * 1.7).abs() * 0.8 + 0.2); // flutter
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset.zero, width: width, height: width * 1.6),
                  const Radius.circular(1.5),
                ),
                Paint()..color = tint.withValues(alpha: t > 0.8 ? (1 - t) * 5 : 1),
              );
              canvas.restore();
            },
          ),
        );
      },
    ),
  );
}
