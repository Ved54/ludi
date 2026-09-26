import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludi/game/components/board_component.dart';
import 'package:ludi/game/components/dice_component.dart';
import 'package:ludi/game/components/path_waypoints.dart';
import 'package:ludi/game/components/player_pod_component.dart';
import 'package:ludi/game/components/toast_component.dart';
import 'package:ludi/game/components/token_component.dart';
import 'package:ludi/game/ludi_game.dart';
import 'package:ludi/game/ludi_theme.dart';
import 'package:ludi/rules_engine/capture_logic.dart';
import 'package:ludi/rules_engine/legal_moves.dart';
import 'package:ludi/rules_engine/models/game_state.dart';
import 'package:ludi/rules_engine/models/move.dart';
import 'package:ludi/rules_engine/models/player.dart';
import 'package:ludi/rules_engine/models/token.dart';
import 'package:ludi/state/game_controller.dart';

/// What one played game looked like — printed after each run so a
/// human can sanity-check the pacing and the mix of events.
class PlaytestReport {
  int frames = 0;
  int rolls = 0;
  int sixes = 0;
  int wastedRolls = 0;
  int moves = 0;
  int backwardMoves = 0;
  int captures = 0;
  int tokensCaptured = 0;
  int finishes = 0;
  int autoMoves = 0;
  int chaosTaps = 0;
  int longestBusyFrames = 0;
  final Map<String, int> toasts = {};
  final Set<String> violations = {};
  final List<String> violationLog = [];
  final Map<String, int> violationCounts = {};
  PlayerColor? winner;

  @override
  String toString() =>
      'winner=$winner frames=$frames (${(frames * 16 / 1000 / 60).toStringAsFixed(1)} min) '
      'rolls=$rolls sixes=$sixes wasted=$wastedRolls moves=$moves auto=$autoMoves '
      'backward=$backwardMoves captures=$captures ($tokensCaptured tokens) '
      'finishes=$finishes chaosTaps=$chaosTaps '
      'longestBusy=${(longestBusyFrames * 16 / 1000).toStringAsFixed(2)}s\n'
      'toasts=$toasts';
}

/// A scripted tester: plays a whole game through real taps on the die,
/// pods, tokens and move markers, and after every 16 ms frame checks that
/// what the screen shows agrees with the rules engine.
///
/// With [chaos], it also fires random taps anywhere on the screen at any
/// moment — mid-roll, mid-hop, on locked tokens — the way an impatient
/// player would.
class Playtester {
  Playtester(this.tester, this.game, {required int seed, this.chaos = false})
    : rng = Random(seed);

  final WidgetTester tester;
  final LudiGame game;
  final Random rng;
  final bool chaos;
  final PlaytestReport report = PlaytestReport();

  /// Called after every checked frame — a hook for capturing screenshots.
  Future<void> Function(Playtester p)? onFrame;

  static const double frame = 1 / 60;

  late final Offset origin = tester.getTopLeft(find.byType(GameWidget<LudiGame>));
  late final Size screen = tester.getSize(find.byType(GameWidget<LudiGame>));
  late final BoardComponent board = game.children.whereType<BoardComponent>().single;
  late final DiceComponent dice = game.children.whereType<DiceComponent>().single;
  late final ToastComponent toast = game.children.whereType<ToastComponent>().single;
  late final Map<PlayerColor, PlayerPodComponent> pods = {
    for (final p in game.children.whereType<PlayerPodComponent>()) p.color: p,
  };
  late final List<TokenComponent> tokens = board.children.whereType<TokenComponent>().toList();

  GameState get state => game.controller.state;

  final Map<TokenComponent, Vector2> _lastPos = {};
  final Map<TokenComponent, double> _lastScale = {};
  int _busyFrames = 0;
  int _idleFrames = 0;
  String? _lastToast;
  double _lastToastAge = -1;
  final List<String> _toastsSinceAction = [];

  void violation(String kind, String detail) {
    final n = report.violationCounts[kind] = (report.violationCounts[kind] ?? 0) + 1;
    report.violations.add(kind);
    if (n <= 3) {
      report.violationLog.add(
        'frame ${report.frames}: $kind — $detail '
        '[phase ${state.phase.name}, busy=${!(game.canRoll || game.canSelect)}, prompt ${game.prompt}]',
      );
    }
  }

  Offset boardToScreen(Vector2 local) =>
      origin + (board.basePosition + local * board.scale.x).toOffset();

  Future<void> pumpFrame() async {
    await tester.pump(const Duration(microseconds: 16667));
    report.frames++;
    final error = tester.takeException();
    if (error != null) violation('exception', '$error');
    _checkFrame();
    await onFrame?.call(this);
    if (chaos && state.phase != GamePhase.gameOver && rng.nextDouble() < 0.06) {
      report.chaosTaps++;
      await tester.tapAt(Offset(rng.nextDouble() * screen.width, rng.nextDouble() * screen.height) + origin);
    }
  }

  Future<void> pumpFor(double seconds) async {
    for (var t = 0.0; t < seconds; t += frame) {
      await pumpFrame();
    }
  }

  Future<void> waitUntilIdle({double limit = 12}) async {
    var waited = 0.0;
    while (!(game.canRoll || game.canSelect) && state.phase != GamePhase.gameOver) {
      await pumpFrame();
      waited += frame;
      if (waited > limit) {
        violation('stuck', 'no input accepted for ${limit}s, phase ${state.phase}, prompt ${game.prompt}');
        return;
      }
    }
  }

  // -------------------------------------------------------------------
  // Per-frame checks

  void _checkFrame() {
    final idle = game.canRoll || game.canSelect;
    final over = state.phase == GamePhase.gameOver;

    // Toast history.
    final text = toast.text;
    if (text != null && (text != _lastToast || toast.age < _lastToastAge)) {
      _toastsSinceAction.add(text);
      report.toasts[text] = (report.toasts[text] ?? 0) + 1;
    }
    _lastToast = text;
    _lastToastAge = toast.age;

    // Nothing on screen may jump: hops, knockbacks and re-fanning stacks
    // all move a token a few px per frame at most.
    for (final c in tokens) {
      final prev = _lastPos[c];
      if (prev != null) {
        final jump = prev.distanceTo(c.position);
        if (jump > 22) violation('teleport', '${c.token.id} jumped ${jump.toStringAsFixed(1)} px');
        final scaleJump = (_lastScale[c]! - c.scale.x).abs();
        if (scaleJump > 0.2) violation('scale-pop', '${c.token.id} scale jumped $scaleJump');
      }
      _lastPos[c] = c.position.clone();
      _lastScale[c] = c.scale.x;
    }

    // A token in the air draws over every token on the ground.
    final resting = tokens.where((c) => !c.isAnimating);
    final flying = tokens.where((c) => c.isAnimating);
    if (flying.isNotEmpty && resting.isNotEmpty) {
      final topResting = resting.map((c) => c.priority).reduce(max);
      for (final c in flying) {
        if (c.priority <= topResting) {
          violation('z-order', '${c.token.id} flies under resting tokens');
        }
      }
    }

    // Two colors never rest on one non-safe square.
    final colorsAt = <int, Set<PlayerColor>>{};
    for (final c in resting) {
      if (isOnSharedTrack(c.shownDistance)) {
        final square = toSharedSquare(c.token.color, c.shownDistance);
        if (!isSafeSquare(square)) (colorsAt[square] ??= {}).add(c.token.color);
      }
    }
    for (final e in colorsAt.entries) {
      if (e.value.length > 1) violation('shared-square', 'square ${e.key} shows ${e.value}');
    }

    // HUD tallies what the board shows, not what the engine already knows.
    for (final pod in pods.values) {
      final shownHome = tokens
          .where((c) => c.token.color == pod.color && c.shownDistance == maxDistance)
          .length;
      if (pod.homeCount != shownHome) {
        violation('hud-ahead', '${pod.color} pod says ${pod.homeCount} home, board shows $shownHome');
      }
    }

    // Effects and timers are cleaned up.
    final particles = board.children.whereType<ParticleSystemComponent>().length;
    if (particles > 6) violation('particle-leak', '$particles particle systems alive');
    final timers = game.children.whereType<TimerComponent>().length;
    if (timers > 3) violation('timer-leak', '$timers timers alive');

    if (idle || over) {
      _busyFrames = 0;
    } else {
      _busyFrames++;
      report.longestBusyFrames = max(report.longestBusyFrames, _busyFrames);
    }

    if (!idle) {
      _idleFrames = 0;
      return;
    }
    _idleFrames++;

    for (final c in tokens) {
      if (c.isAnimating) violation('anim-while-idle', '${c.token.id} still hopping');
      if (c.shownDistance != c.token.distance) {
        violation('shown-mismatch', '${c.token.id} shown ${c.shownDistance} engine ${c.token.distance}');
      }
      // Settled tokens sit exactly where the layout wants them.
      if (_idleFrames > 30 && c.position.distanceTo(c.restPosition) > 0.5) {
        violation('not-settled', '${c.token.id} ${c.position} vs rest ${c.restPosition}');
      }
    }
    if (game.activeColor != state.currentPlayer.color) {
      violation('active-mismatch', 'screen ${game.activeColor} engine ${state.currentPlayer.color}');
    }
    if (state.finishOrder.contains(game.activeColor)) {
      violation('finished-plays', '${game.activeColor} already finished but is up');
    }
    for (final pod in pods.values) {
      final index = state.finishOrder.indexOf(pod.color);
      if (pod.place != (index < 0 ? null : index + 1)) {
        violation('pod-place', '${pod.color} pod shows ${pod.place}');
      }
    }
    final running = dice.children.whereType<Effect>().where((e) => !e.controller.completed);
    if (running.isNotEmpty) {
      violation('dice-moving-idle', 'die still has ${running.map((e) => e.runtimeType)} running');
    }
    if (_idleFrames > 2 && dice.position.distanceTo(pods[game.activeColor]!.diceSlot) > 0.5) {
      violation('dice-off-slot', 'die at ${dice.position}, slot ${pods[game.activeColor]!.diceSlot}');
    }

    if (game.canSelect) {
      if (dice.face != state.lastRoll) {
        violation('dice-face', 'die shows ${dice.face}, rolled ${state.lastRoll}');
      }
      final legal = {for (final m in state.legalMoves) m.token};
      if (!_sameSet(game.movableTokens, legal)) {
        violation(
          'movable-mismatch',
          'bobbing ${game.movableTokens.map((t) => t.id)} legal ${legal.map((t) => t.id)} idleFrames $_idleFrames',
        );
      }
      final want = game.selectedToken == null ? ['Pick a token', 'Tap a token'] : ['Pick a square'];
      if (!want.contains(game.prompt)) violation('prompt:$want', 'shows "${game.prompt}"');
      final effective = {for (final m in state.legalMoves) m.token.distance};
      if (effective.length == 1 && game.selectedToken == null) {
        violation('no-autopick', 'one token with two options was not picked for the player');
      }
    }
    if (game.canRoll && !(game.prompt?.contains('oll') ?? false)) {
      violation('prompt:roll', 'shows "${game.prompt}" while rolling');
    }
  }

  bool _sameSet(Set<Token> a, Set<Token> b) => a.length == b.length && a.containsAll(b);

  // -------------------------------------------------------------------
  // Playing

  Future<PlaytestReport> playGame({int maxActions = 5000}) async {
    await pumpFor(0.2);
    var actions = 0;
    while (state.phase != GamePhase.gameOver) {
      if (++actions > maxActions) {
        violation('never-ends', 'over $maxActions actions');
        break;
      }
      await waitUntilIdle();
      if (report.violations.contains('stuck')) break;
      if (state.phase == GamePhase.gameOver) break;
      // A human takes a moment before acting.
      await pumpFor(rng.nextDouble() * 0.25);
      if (chaos) {
        await _chaosAct();
      } else if (game.canRoll) {
        await _roll();
      } else if (game.canSelect) {
        await _choose();
      }
    }
    await pumpFor(1.5);
    if (state.phase == GamePhase.gameOver) {
      report.winner = state.finishOrder.first;
      // Play went on until one player was left; every finisher is home.
      if (state.finishOrder.length != state.players.length - 1) {
        violation('ended-early', 'finish order ${state.finishOrder}');
      }
      for (final p in state.players) {
        final home = p.tokens.every((t) => t.distance == maxDistance);
        if (home != state.finishOrder.contains(p.color)) {
          violation('bad-standings', '${p.color} home=$home, order ${state.finishOrder}');
        }
      }
      if (game.prompt != null) violation('prompt', 'final prompt ${game.prompt}');
    }
    return report;
  }

  /// Chaos mode: no bookkeeping, just plausible taps between random ones.
  Future<void> _chaosAct() async {
    if (game.canRoll) {
      report.rolls++;
      await tester.tapAt(origin + dice.position.toOffset());
    } else if (game.canSelect) {
      final moves = state.legalMoves;
      final move = moves[rng.nextInt(moves.length)];
      await tester.tapAt(boardToScreen(tokens.singleWhere((c) => c.token == move.token).bodyCenter));
      await pumpFrame();
      await tester.tapAt(boardToScreen(positionForDistance(move.token.color, move.newDistance)));
    }
    await pumpFrame();
  }

  Future<void> _roll() async {
    final roller = state.currentPlayerIndex;
    _toastsSinceAction.clear();
    // Mostly the die; sometimes anywhere on the active pod.
    if (rng.nextDouble() < 0.7) {
      await tester.tapAt(origin + dice.position.toOffset());
    } else {
      final pod = pods[game.activeColor]!;
      final spot = pod.position + Vector2(pod.size.x * (0.1 + 0.8 * rng.nextDouble()), pod.size.y * 0.5);
      await tester.tapAt(origin + spot.toOffset());
    }
    await pumpFrame();
    if (game.canRoll) {
      violation('roll-ignored', 'tap on die/pod did not roll');
      return;
    }
    report.rolls++;

    // Watch the tumble: the number must not show until the die stops.
    while (dice.face == null && state.phase == GamePhase.rolling && !game.canRoll) {
      if (state.lastRoll != 0 && state.phase != GamePhase.rolling) break;
      await pumpFrame();
    }
    final wasSelecting = state.phase == GamePhase.selecting;
    final roll = state.lastRoll;
    if (roll == 6) report.sixes++;
    final snapshot = _snapshot();

    if (!wasSelecting) {
      report.wastedRolls++;
      final waiting = state.players[roller].tokens.every((t) => t.distance == 0 || t.distance == maxDistance);
      await pumpFor(0.1);
      final want = waiting ? 'Need a 6' : 'No moves';
      if (game.prompt != want) violation('prompt:$want', 'wasted $roll shows "${game.prompt}"');
      await waitUntilIdle();
      _expectToasts([], 'wasted roll of $roll');
      _expectRollPrompt(roller);
      return;
    }
    // One distinct choice plays itself.
    await pumpFor(LudiMotion.readBeat + 0.1);
    if (game.canSelect) return;
    report.autoMoves++;
    await _afterMove(snapshot, roller, roll, expected: null);
  }

  Future<void> _choose() async {
    final roller = state.currentPlayerIndex;
    final roll = state.lastDiceValue;
    final moves = state.legalMoves;
    final move = moves[rng.nextInt(moves.length)];
    final snapshot = _snapshot();
    _toastsSinceAction.clear();

    final marker = positionForDistance(move.token.color, move.newDistance);
    final component = tokens.singleWhere((c) => c.token == move.token);
    final markerIsClear =
        moves.where((m) => m.newDistance == move.newDistance && m.token.color == move.token.color).every(
          (m) => m.token.distance == move.token.distance,
        ) &&
        game.movableTokens.every(
          (t) => tokens.singleWhere((c) => c.token == t).bodyCenter.distanceTo(marker) > 20,
        );

    if (markerIsClear && rng.nextBool()) {
      await tester.tapAt(boardToScreen(marker));
    } else {
      await tester.tapAt(boardToScreen(component.bodyCenter));
      await pumpFrame();
      if (game.canSelect) {
        if (game.selectedToken != move.token &&
            game.selectedToken?.distance != move.token.distance) {
          violation('tap-token-ignored', 'tapped movable ${move.token.id}, picked ${game.selectedToken?.id}');
          return;
        }
        await pumpFor(0.2);
        await tester.tapAt(boardToScreen(marker));
      }
    }
    await pumpFrame();
    if (game.canSelect) {
      violation('tap-marker-ignored', 'tapped marker for ${move.token.id} -> ${move.newDistance}');
      return;
    }
    await _afterMove(snapshot, roller, roll, expected: move);
  }

  Map<Token, int> _snapshot() => {
    for (final p in state.players)
      for (final t in p.tokens) t: t.distance,
  };

  Future<void> _afterMove(
    Map<Token, int> before,
    int roller,
    int roll,
    {required Move? expected}
  ) async {
    final placesBefore = state.finishOrder.length;
    // Which move actually happened, read off the engine.
    final moved = before.keys.where((t) => t.color == state.players[roller].color && t.distance != before[t]).toList();
    final captured = before.keys.where((t) => t.color != state.players[roller].color && t.distance != before[t]).toList();
    if (moved.length != 1) {
      violation('move-count', '${moved.length} own tokens changed');
      await waitUntilIdle();
      return;
    }
    final token = moved.single;
    report.moves++;
    final backward = token.distance < before[token]!;
    if (backward) report.backwardMoves++;
    if (captured.isNotEmpty) {
      report.captures++;
      report.tokensCaptured += captured.length;
    }
    final finished = token.distance == maxDistance;
    if (finished) report.finishes++;

    if (expected != null &&
        !(before[token] == before[expected.token] && token.distance == expected.newDistance)) {
      violation(
        'wrong-move',
        'wanted ${expected.token.id} ${before[expected.token]}->${expected.newDistance}, '
            'got ${token.id} ${before[token]}->${token.distance}',
      );
    }
    if (backward && captured.isEmpty) violation('silent-retreat', '${token.id} went back without a kill');

    // While it walks, the die keeps showing the roll being moved; a
    // player taking a place has their pod say so rather than "Moving…".
    while (!(game.canRoll || game.canSelect) && state.phase != GamePhase.gameOver) {
      if (dice.face != null && dice.face != roll && dice.children.isEmpty) {
        violation('dice-face-moving', 'die shows ${dice.face} while moving a $roll');
      }
      if (state.finishOrder.length > placesBefore && game.prompt != null) {
        violation('place-prompt', 'pod says "${game.prompt}" after taking a place');
      }
      await pumpFrame();
      if (_busyFrames > 12 * 60) {
        violation('stuck', 'move never finished');
        return;
      }
    }

    // A player whose last token came home takes a place; the callout
    // replaces "Home!" on the same frame.
    final place = state.finishOrder.length > placesBefore ? state.finishOrder.length : null;
    _expectToasts([
      if (captured.isNotEmpty) backward ? 'Backstrike!' : 'Captured!',
      if (finished && place == null) 'Home!',
      if (place == 1) '${_label(token.color)} wins!',
      if (place != null && place > 1) '${_label(token.color)} takes ${placeLabel(place)}!',
    ], 'move ${token.id} ${before[token]}->${token.distance} roll $roll');
    if (state.phase == GamePhase.gameOver) return;
    _expectRollPrompt(roller);
  }

  /// Once input unlocks after [roller]'s action: a player who keeps the
  /// die is told to roll again (with the count when several are owed).
  void _expectRollPrompt(int roller) {
    if (!game.canRoll) return;
    final rolls = state.bonusRollsRemaining + 1;
    final want = state.currentPlayerIndex != roller
        ? 'Tap to roll'
        : rolls > 1
        ? 'Roll again ×$rolls'
        : 'Roll again';
    if (game.prompt != want) violation('prompt:$want', 'shows "${game.prompt}"');
  }

  void _expectToasts(List<String> want, String context) {
    final got = [..._toastsSinceAction];
    if ('$got' != '$want') violation('toast:$want', '$context: saw $got');
    _toastsSinceAction.clear();
  }

  String _label(PlayerColor c) => c.name[0].toUpperCase() + c.name.substring(1);
}

/// Wraps the game so a test can grab a screenshot of it.
final GlobalKey gameBoundaryKey = GlobalKey();

/// Mounts [game] full-screen at a phone size, like GameScreen does.
///
/// Pass [controller] to start from a hand-built position instead (it must
/// hold moves for animation).
Future<LudiGame> mountGame(
  WidgetTester tester, {
  List<PlayerColor> colors = PlayerColor.values,
  int seed = 0,
  GameController? controller,
  Size physical = const Size(1080, 2424),
  double dpr = 2.625,
}) async {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  controller ??= GameController(
    initialState: newGame(colors: colors),
    random: Random(seed),
    holdMovesForAnimation: true,
  );
  final game = LudiGame(controller: controller);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: RepaintBoundary(
            key: gameBoundaryKey,
            child: Stack(fit: StackFit.expand, children: [GameWidget(game: game)]),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return game;
}

/// Pumps [seconds] of 60 fps frames.
Future<void> pumpSeconds(WidgetTester tester, double seconds) async {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}
