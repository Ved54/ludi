import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../rules_engine/models/game_state.dart';
import '../rules_engine/models/move.dart';
import '../rules_engine/models/player.dart';
import '../rules_engine/models/token.dart';
import '../state/game_controller.dart';
import 'components/board_component.dart';
import 'components/dice_component.dart';
import 'components/path_waypoints.dart';
import 'components/player_pod_component.dart';
import 'components/toast_component.dart';
import 'components/token_component.dart';
import 'effects/capture_effect.dart';
import 'ludi_theme.dart';

/// Flame game root — lays out the board, tokens, HUD pods and die, and
/// directs the show.
///
/// The rules engine resolves everything instantly; this class turns each
/// resolution into a readable sequence and holds input until it's over:
///
///   tap die -> tumble -> real roll lands -> (auto-move if only one choice)
///   tap token -> hop square by square -> impact / knockback home / sparkle
///   -> controller.completeMove() -> callout -> die travels to next player
///
/// Needs a controller built with `holdMovesForAnimation: true`, so the
/// turn doesn't resolve until the animation has played.
class LudiGame extends FlameGame {
  LudiGame({required this.controller})
    : assert(
        controller.holdMovesForAnimation,
        'LudiGame drives completeMove() itself',
      ),
      activeColor = controller.state.currentPlayer.color;

  final GameController controller;

  /// Whose turn the screen is showing — trails the engine's current
  /// player until the die has actually traveled over.
  PlayerColor activeColor;

  /// Token picked by a tap when it had more than one option.
  Token? selectedToken;

  /// Tokens that can move this roll (they bob), empty while locked.
  Set<Token> movableTokens = const {};

  /// Short instruction shown in the active player's pod.
  String? prompt = 'Tap to roll';

  /// Space the Flutter shell keeps free at the top for its buttons.
  static const double topInset = 56;

  late final BoardComponent _board;
  late final DiceComponent _dice;
  late final ToastComponent _toast;
  final Map<Token, TokenComponent> _tokens = {};
  final Map<PlayerColor, PlayerPodComponent> _pods = {};
  bool _busy = false;

  GameState get _state => controller.state;

  bool get canRoll => !_busy && _state.phase == GamePhase.rolling;
  bool get canSelect => !_busy && _state.phase == GamePhase.selecting;

  @override
  Color backgroundColor() => LudiNeutral.boardBackground;

  @override
  Future<void> onLoad() async {
    _board = BoardComponent(seated: {for (final p in _state.players) p.color});
    await add(_board);
    for (final player in _state.players) {
      for (final token in player.tokens) {
        final component = TokenComponent(token: token);
        _tokens[token] = component;
        await _board.add(component);
      }
      final pod = PlayerPodComponent(
        player: player,
        dockOnRight: player.color == PlayerColor.red || player.color == PlayerColor.blue,
      );
      _pods[player.color] = pod;
      await add(pod);
    }
    _toast = ToastComponent();
    _dice = DiceComponent()..priority = 20;
    await addAll([_toast, _dice]);
    _layout();
    _dice.position = _pods[activeColor]!.diceSlot;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      _layout();
      if (!_busy) _dice.position = _pods[activeColor]!.diceSlot;
    }
  }

  /// Board as big as fits, a row of two pods above it (red, green — the
  /// top yards) and below it (blue, yellow), all centered.
  void _layout() {
    const margin = 14.0;
    const gap = 12.0;
    const minPodHeight = 58.0;
    final free = Vector2(size.x - 2 * margin, size.y - topInset - 2 * margin);
    final boardPx = min(free.x, free.y - 2 * (minPodHeight + gap)).clamp(160.0, 720.0);
    // Spare height goes to taller pods — bigger targets for rolling.
    final podHeight = ((free.y - boardPx) / 2 - gap).clamp(minPodHeight, 76.0);
    final left = (size.x - boardPx) / 2;
    final top = topInset + (size.y - topInset - boardPx - 2 * (podHeight + gap)) / 2;
    final boardTop = top + podHeight + gap;

    _board
      ..scale = Vector2.all(boardPx / boardSize)
      ..basePosition = Vector2(left, boardTop)
      ..position = Vector2(left, boardTop);

    final podSize = Vector2((boardPx - gap) / 2, podHeight);
    final rightX = left + podSize.x + gap;
    final bottomY = boardTop + boardPx + gap;
    final spots = {
      PlayerColor.red: Vector2(left, top),
      PlayerColor.green: Vector2(rightX, top),
      PlayerColor.blue: Vector2(left, bottomY),
      PlayerColor.yellow: Vector2(rightX, bottomY),
    };
    for (final pod in _pods.values) {
      pod
        ..size = podSize
        ..position = spots[pod.color]!;
    }
    _toast.position = Vector2(left + boardPx / 2, boardTop + boardPx / 2);
  }

  @override
  void update(double dt) {
    movableTokens = canSelect ? {for (final m in controller.currentLegalMoves) m.token} : const {};
    _layoutTokens();
    super.update(dt);
  }

  // ---------------------------------------------------------------------
  // Token layout: where each resting token sits, fanning out stacks.

  static const double _groundDrop = 7;

  void _layoutTokens() {
    final groups = <String, List<TokenComponent>>{};
    for (final c in _tokens.values) {
      if (c.isAnimating) continue;
      (groups[_spotKey(c)] ??= []).add(c);
    }
    for (final group in groups.values) {
      group.sort((a, b) {
        final byColor = a.token.color.index.compareTo(b.token.color.index);
        return byColor != 0 ? byColor : a.token.id.compareTo(b.token.id);
      });
      final (offsets, scale) = _fan(group.length);
      for (var i = 0; i < group.length; i++) {
        final c = group[i];
        c.restPosition = _groundOf(c.token, c.shownDistance) + offsets[i];
        c.restScale = scale;
        final depth = 100 + c.restPosition.y.round();
        if (c.priority != depth) c.priority = depth;
      }
    }
  }

  String _spotKey(TokenComponent c) {
    final d = c.shownDistance;
    if (d == 0) return '${c.token.id}-yard';
    final at = positionForDistance(c.token.color, d);
    return '${at.x.round()},${at.y.round()}';
  }

  Vector2 _groundOf(Token token, int distance) {
    final at = distance == 0
        ? yardSlotPosition(token.color, yardSlotOf(token))
        : positionForDistance(token.color, distance);
    return at + Vector2(0, _groundDrop);
  }

  /// Offsets and scale for [n] tokens sharing one square.
  static (List<Vector2>, double) _fan(int n) => switch (n) {
    1 => ([Vector2.zero()], 1.0),
    2 => ([Vector2(-5, 0), Vector2(5, 0)], 0.8),
    3 => ([Vector2(-5, 2), Vector2(5, 2), Vector2(0, -5)], 0.72),
    4 => ([Vector2(-5, -3), Vector2(5, -3), Vector2(-5, 4), Vector2(5, 4)], 0.66),
    _ => (
      [for (var i = 0; i < n; i++) Vector2((i % 3 - 1) * 6.5, (i ~/ 3 - 1) * 6.5)],
      0.52,
    ),
  };

  // ---------------------------------------------------------------------
  // Rolling

  /// Die or active pod tapped.
  Future<void> requestRoll() async {
    if (!canRoll) return;
    _busy = true;
    selectedToken = null;
    prompt = 'Rolling…';
    final roller = _state.currentPlayerIndex;
    _haptic(HapticFeedback.lightImpact);

    await _dice.tumble();
    controller.rollDice();
    _dice.land(_state.lastRoll);
    _haptic(HapticFeedback.mediumImpact);

    if (_state.phase == GamePhase.selecting) {
      final only = _onlyChoice(_state.legalMoves);
      if (only != null) {
        prompt = 'Moving…';
        await _wait(LudiMotion.readBeat);
        await _play(only);
        return;
      }
      prompt = 'Pick a token';
      _busy = false;
      return;
    }

    // Wasted roll: nothing could move.
    final keepsTurn = _state.currentPlayerIndex == roller;
    _toast.show(
      keepsTurn ? 'No moves · roll again' : 'No moves',
      accent: playerPalette[activeColor]!.base,
    );
    await _wait(LudiMotion.wastedRollHold);
    await _nextTurn();
  }

  /// The single move to auto-play when every legal move is the same move
  /// in effect (one token, or identical stacked/yard tokens).
  Move? _onlyChoice(List<Move> moves) {
    final first = moves.first;
    final same = moves.every(
      (m) =>
          m.token.distance == first.token.distance &&
          m.newDistance == first.newDistance &&
          m.isBackward == first.isBackward,
    );
    return same ? first : null;
  }

  // ---------------------------------------------------------------------
  // Choosing and playing a move

  /// A tap on the board, in board-local coordinates. Tapping a movable
  /// token plays it when all its options land on the same square;
  /// otherwise it gets picked, its options are marked, and the next tap on
  /// one of them plays it. A marker can also be tapped directly.
  void onBoardTap(Vector2 at) {
    if (!canSelect) return;
    final picked = selectedToken;

    // A picked token's own options win over anything else under the finger.
    if (picked != null) {
      final option = _markerAt(at, controller.currentLegalMoves.where((m) => m.token == picked));
      if (option != null) {
        _play(option);
        return;
      }
    }

    final token = _movableTokenAt(at);
    if (token != null) {
      final options = controller.currentLegalMoves.where((m) => m.token == token).toList();
      if (options.map((m) => m.newDistance).toSet().length == 1) {
        _play(options.first);
      } else {
        selectedToken = token;
        _haptic(HapticFeedback.selectionClick);
      }
      return;
    }

    final marker = _markerAt(at, controller.currentLegalMoves);
    if (marker != null) {
      _play(marker);
    } else {
      selectedToken = null;
    }
  }

  Token? _movableTokenAt(Vector2 at) {
    Token? nearest;
    var best = 16.0;
    for (final token in movableTokens) {
      final distance = _tokens[token]!.bodyCenter.distanceTo(at);
      if (distance < best) {
        best = distance;
        nearest = token;
      }
    }
    return nearest;
  }

  Move? _markerAt(Vector2 at, Iterable<Move> moves) {
    Move? nearest;
    var best = 15.0;
    for (final move in moves) {
      final distance = positionForDistance(move.token.color, move.newDistance).distanceTo(at);
      if (distance < best) {
        best = distance;
        nearest = move;
      }
    }
    return nearest;
  }

  Future<void> _play(Move move) async {
    final mover = _tokens[move.token]!;
    final from = mover.shownDistance;
    final roll = _state.lastDiceValue;
    final mover0 = _state.currentPlayerIndex;
    final captured = <Token>[];
    controller.onCapture = captured.add;
    controller.selectMove(move);
    controller.onCapture = null;
    if (_state.phase != GamePhase.animating) return; // not a legal move

    _busy = true;
    selectedToken = null;
    prompt = 'Moving…';
    final color = move.token.color;

    final route = stepDistances(from, move.newDistance).skip(1);
    final entering = from == 0;
    await mover.hopThrough(
      [for (final d in route) _groundOf(move.token, d)],
      step: entering ? LudiMotion.enterDuration : LudiMotion.hopStep,
      height: entering ? LudiMotion.enterHeight : LudiMotion.hopHeight,
      onLand: () => _haptic(HapticFeedback.selectionClick),
    );
    mover.shownDistance = move.newDistance;

    final finished = move.token.state == TokenState.finished;
    String? callout;
    if (captured.isNotEmpty) {
      callout = move.isBackward ? 'Backstrike!' : 'Captured!';
      _board
        ..shake()
        ..add(
          captureBurst(
            positionForDistance(color, move.newDistance),
            attacker: playerPalette[color]!.base,
            victim: playerPalette[captured.first.color]!.base,
          )..priority = 900,
        );
      _haptic(HapticFeedback.heavyImpact);
      await Future.wait([
        for (final token in captured) _knockHome(_tokens[token]!),
      ]);
    } else if (finished) {
      callout = 'Home!';
      _board.add(
        homeSparkle(positionForDistance(color, move.newDistance), playerPalette[color]!.base)
          ..priority = 900,
      );
      _haptic(HapticFeedback.mediumImpact);
    }

    controller.completeMove();

    if (_state.phase == GamePhase.gameOver) {
      prompt = 'Winner!';
      _toast.show('${colorLabel(color)} wins!', accent: playerPalette[color]!.base, hold: 2.5);
      add(confetti(size, winner: playerPalette[color]!.base)..priority = 100);
      _haptic(HapticFeedback.heavyImpact);
      return; // stays locked — the Flutter shell takes over
    }

    final again = _state.currentPlayerIndex == mover0;
    if (again) {
      final reason = callout ?? (roll == 6 ? 'Six!' : null);
      _toast.show(
        reason == null ? 'Roll again' : '$reason Roll again',
        accent: playerPalette[color]!.base,
      );
    } else if (callout != null) {
      _toast.show(callout, accent: playerPalette[color]!.base);
    }
    await _nextTurn();
  }

  /// A captured token pops up, tumbles, and arcs back to its yard socket.
  Future<void> _knockHome(TokenComponent victim) async {
    await victim.hopThrough(
      [_groundOf(victim.token, 0)],
      step: LudiMotion.knockDuration,
      height: LudiMotion.knockHeight,
      spinTurns: 2,
    );
    victim.shownDistance = 0;
  }

  /// Unlocks input for whoever plays next, sending the die over first
  /// if the turn changed hands.
  Future<void> _nextTurn() async {
    final next = _state.currentPlayer.color;
    if (next != activeColor) {
      prompt = null;
      activeColor = next;
      await _dice.travelTo(_pods[next]!.diceSlot);
    }
    prompt = 'Tap to roll';
    _busy = false;
  }

  Future<void> _wait(double seconds) {
    final done = Completer<void>();
    add(TimerComponent(period: seconds, removeOnFinish: true, onTick: done.complete));
    return done.future;
  }

  /// Haptics are garnish — never let a platform hiccup break the game.
  void _haptic(Future<void> Function() buzz) {
    unawaited(buzz().catchError((Object _) {}));
  }
}
