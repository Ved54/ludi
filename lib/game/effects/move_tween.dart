import 'dart:math';

import 'package:flame/components.dart';

/// A token walking [points] one square at a time — each step a small arc,
/// so a 5-square move reads as five distinct hops rather than a slide
/// (README Section 5). Backward moves are the same thing with the points
/// reversed. Pure math: [TokenComponent] advances it and reads the
/// current ground position and lift every frame.
class HopPath {
  HopPath(this.points, {required this.stepDuration, required this.height})
    : assert(points.length >= 2, 'a hop needs somewhere to go');

  /// Ground positions, starting where the token stands now.
  final List<Vector2> points;
  final double stepDuration;
  final double height;

  double _elapsed = 0;

  int get steps => points.length - 1;
  double get duration => steps * stepDuration;
  bool get isDone => _elapsed >= duration;

  /// Squares landed on so far.
  int get landed => isDone ? steps : (_elapsed / stepDuration).floor();

  /// 0-1 progress through the current hop.
  double get _phase => isDone ? 1 : (_elapsed - landed * stepDuration) / stepDuration;

  /// Advances the walk by [dt] seconds; returns how many squares were
  /// landed on during this advance (for per-hop feedback).
  int advance(double dt) {
    final before = landed;
    _elapsed = min(_elapsed + dt, duration);
    return landed - before;
  }

  Vector2 get position {
    if (isDone) return points.last.clone();
    final eased = 0.5 - cos(pi * _phase) / 2; // ease in-out per hop
    final from = points[landed];
    final to = points[landed + 1];
    return from + (to - from) * eased;
  }

  /// Height above the ground right now — a parabola-like arc per hop.
  double get lift => isDone ? 0 : sin(pi * _phase) * height;

  /// 0 at take-off and landing, 1 at the top of each hop.
  double get airborne => isDone ? 0 : sin(pi * _phase);

  /// Overall 0-1 progress of the whole walk.
  double get progress => duration == 0 ? 1 : _elapsed / duration;
}
