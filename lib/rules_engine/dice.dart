import 'dart:math';

/// Rolls a single six-sided die: returns 1-6.
///
/// Accepts an injectable [random] source so tests can seed deterministic
/// rolls instead of depending on real randomness.
int rollDie([Random? random]) {
  final r = random ?? Random();
  return r.nextInt(6) + 1;
}
