import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/rules_engine/dice.dart';

void main() {
  group('rollDie', () {
    test('always returns a value between 1 and 6', () {
      final random = Random(42);
      for (var i = 0; i < 200; i++) {
        final value = rollDie(random);
        expect(value, inInclusiveRange(1, 6));
      }
    });

    test('is deterministic given a seeded random source', () {
      final a = rollDie(Random(7));
      final b = rollDie(Random(7));
      expect(a, b);
    });
  });
}
