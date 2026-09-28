import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../rules_engine/legal_moves.dart' show maxDistance;
import '../rules_engine/models/game_state.dart';
import '../rules_engine/models/move.dart';
import '../rules_engine/models/player.dart';
import '../rules_engine/models/token.dart';
import '../state/game_controller.dart';
import 'components/board_component.dart';
import 'components/dice_component.dart';
import 'components/move_hints_component.dart';
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
///   tap token -> hop square by square -> impact + callout / knockback home
///   / sparkle -> controller.completeMove() -> die travels to next player
///   (or stays, "Roll again")
///
/// Everything on screen — token positions, the HUD's home count, whose
/// turn it looks like — follows what has been *shown*, never the engine
/// state that is already a move ahead during an animation.
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

  /// Token picked by a tap when it had more than one option — or whose
  /// marker was tapped once. Its routes show; a tap on one of its markers
  /// plays that move.
  Token? selectedToken;

  /// The marker tapped once while no token was picked: previewed (route
  /// dotted in, marker enlarged) and played by a second tap.
  Move? armedMove;

  /// Short instruction shown in the active player's pod.
  String? prompt = 'Tap to roll';

  /// Tokens that can move this roll (they bob), empty while locked.
  Set<Token> get movableTokens {
    if (!canSelect) return const {};
    final moves = controller.currentLegalMoves;
    if (!identical(moves, _movableFor)) {
      _movableFor = moves;
      _movable = {for (final m in moves) m.token};
    }
    return _movable;
  }

  List<Move>? _movableFor;
  Set<Token> _movable = const {};

  /// Tokens of [color] the board currently shows at home. The HUD counts
  /// these rather than the engine's tally, which is already a move ahead
  /// while the finishing hop is still in the air.
  int shownHomeCount(PlayerColor color) => _tokens.values
      .where((c) => c.token.color == color && c.shownDistance == maxDistance)
      .length;

  /// Space the Flutter shell keeps free at the top for its buttons.
  static const double topInset = 56;

  late final BoardComponent _board;
  late final DiceComponent _dice;
  late final ToastComponent _toast;
  final Map<Token, TokenComponent> _tokens = {};
  final Map<PlayerColor, PlayerPodComponent> _pods = {};
  bool _busy = false;

  /// The token picked on the player's behalf when it is the only one that
  /// can move but has two options — tapping empty board returns to it.
  Token? _autoPick;

  GameState get _state => controller.state;

  bool get canRoll => !_busy && _state.phase == GamePhase.rolling;
  bool get canSelect => !_busy && _state.phase == GamePhase.selecting;

  @override
  Color backgroundColor() => LudiNeutral.boardBackground;

  @override
  Future<void> onLoad() async {
    _board = BoardComponent(seated: {for (final p in _state.players) p.color});
    await add(_board);
    await _board.addAll([MoveHintsComponent.landings(), MoveHintsComponent.targets()]);
    for (final player in _state.players) {
      for (final token in player.tokens) {
        final component = TokenComponent(token: token, onGroundChanged: _groundChanged);
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
      if (!_dice.isTraveling) _dice.position = _pods[activeColor]!.diceSlot;
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
    _toast
      ..home = Vector2(left + boardPx / 2, boardTop + boardPx / 2)
      ..bounds = Rect.fromLTWH(left, boardTop, boardPx, boardPx)
      ..position = _toast.home;
  }

  /// Shows a callout floating just above board square [local] — near the
  /// action but clear of the token it is about (below it instead on the
  /// board's top rows, where above would run into the HUD).
  void _callout(String text, Vector2 local, Color accent) {
    const lift = 44.0; // board units, a little under two cells
    final spot = local.y - lift < cellSize ? local + Vector2(0, lift) : local - Vector2(0, lift);
    _toast.show(text, accent: accent, at: _board.basePosition + spot * _board.scale.x);
  }

  @override
  void update(double dt) {
    _layoutTokensIfNeeded();
    super.update(dt);
  }

  // ---------------------------------------------------------------------
  // Token layout: where each resting token sits, fanning out stacks.

  static const double _groundDrop = 7;

  /// Set whenever a token takes off, lands or changes square — the only
  /// times the resting layout can change — and cleared once it's redone.
  bool _layoutStale = true;

  void _groundChanged() => _layoutStale = true;

  void _layoutTokensIfNeeded() {
    if (!_layoutStale) return;
    _layoutStale = false;
    _layoutTokens();
  }

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
    selectedToken = _autoPick = armedMove = null;
    prompt = 'Rolling…';
    final roller = _state.currentPlayer;
    _haptic(HapticFeedback.lightImpact);

    await _dice.tumble();
    controller.rollDice();
    _dice.land(_state.lastRoll);
    _haptic(HapticFeedback.mediumImpact);

    if (_state.phase == GamePhase.selecting) {
      final moves = _state.legalMoves;
      final only = _onlyChoice(moves);
      if (only != null) {
        prompt = 'Moving…';
        await _wait(LudiMotion.readBeat);
        await _play(only);
        return;
      }
      // One token (or a stack of identical ones) with a forward and a
      // backward option: pick it for the player and show both.
      if (moves.every((m) => m.token.distance == moves.first.token.distance)) {
        _autoPick = moves.first.token;
      }
      _choose(_autoPick);
      _busy = false;
      return;
    }

    // No move this roll. Say why in the pod, where the player is looking,
    // and shake the die "no". A 6 that ends the turn can only be the third
    // in a row — that one gets the big callout too.
    final forfeited = _state.lastRoll == 6 && _state.currentPlayer != roller;
    final waiting = roller.tokens.every((t) => t.distance == 0 || t.distance == maxDistance);
    prompt = forfeited ? 'Three 6s!' : (waiting ? 'Need a 6' : 'No moves');
    if (forfeited) {
      _toast.show('Three 6s · turn over', accent: playerPalette[roller.color]!.base);
      _haptic(HapticFeedback.heavyImpact);
    }
    _dice.shakeNo();
    await _wait(forfeited ? LudiMotion.forfeitHold : LudiMotion.wastedRollHold);
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

  /// A tap on the board, in board-local coordinates (acted on when the
  /// finger lifts). Tapping a movable token plays it when all its options
  /// land on the same square; otherwise it gets picked and its options are
  /// marked with their routes. A marker plays only once its route is
  /// showing: tapped cold, the first tap previews the move and the second
  /// plays it, so a stray tap near a marker can't make a move.
  void onBoardTap(Vector2 at) {
    if (!canSelect) return;
    final moves = controller.currentLegalMoves;
    final picked = selectedToken;

    // A picked token's own options win over anything else under the finger.
    if (picked != null) {
      final option = _nearestMarker(at, moves.where((m) => m.token == picked));
      if (option != null) {
        _play(option.$1);
        return;
      }
    }

    // Otherwise whatever is closest: a movable token, or — only while no
    // token is picked, since only then are all markers showing — a marker.
    // A finger right on a token's body always means that token.
    final token = _nearestToken(at);
    final marker = picked == null ? _nearestMarker(at, moves) : null;
    if (token != null &&
        (marker == null || token.$2 <= _onTokenRadius || token.$2 <= marker.$2)) {
      _tapToken(token.$1);
    } else if (marker != null) {
      _tapMarker(marker.$1);
    } else {
      _choose(_autoPick);
    }
  }

  /// Finger slop for tokens and markers, board units (one cell = 24).
  static const double _tapRadius = 20;

  /// Closer than this to a token's body, a tap is on the token.
  static const double _onTokenRadius = 11;

  void _tapToken(Token token) {
    final options = controller.currentLegalMoves.where((m) => m.token == token).toList();
    if (options.map((m) => m.newDistance).toSet().length == 1) {
      _play(options.first);
    } else {
      _choose(token);
      _haptic(HapticFeedback.selectionClick);
    }
  }

  /// A marker tapped while no token is picked: preview that move — pick
  /// its token, dot in the route, enlarge the marker — and wait for a
  /// second tap. Two different tokens can reach one square (one forward,
  /// one striking back); then the marker alone doesn't say which to move.
  void _tapMarker(Move move) {
    final rivals = controller.currentLegalMoves.where(
      (m) => m.newDistance == move.newDistance && m.token.distance != move.token.distance,
    );
    if (rivals.isEmpty) {
      _choose(move.token, armed: move);
    } else {
      prompt = 'Tap a token';
    }
    _haptic(HapticFeedback.selectionClick);
  }

  /// Picks [token] (null: none), optionally previewing one of its moves,
  /// and says what the player should do next.
  void _choose(Token? token, {Move? armed}) {
    selectedToken = token;
    armedMove = armed;
    prompt = token == null
        ? 'Pick a token'
        : armed != null
        ? 'Tap again'
        : 'Pick a square';
  }

  (Token, double)? _nearestToken(Vector2 at) {
    (Token, double)? nearest;
    for (final token in movableTokens) {
      final distance = _tokens[token]!.bodyCenter.distanceTo(at);
      if (distance < (nearest?.$2 ?? _tapRadius)) nearest = (token, distance);
    }
    return nearest;
  }

  (Move, double)? _nearestMarker(Vector2 at, Iterable<Move> moves) {
    (Move, double)? nearest;
    for (final move in moves) {
      final distance = positionForDistance(move.token.color, move.newDistance).distanceTo(at);
      if (distance < (nearest?.$2 ?? _tapRadius)) nearest = (move, distance);
    }
    return nearest;
  }

  Future<void> _play(Move move) async {
    final mover = _tokens[move.token]!;
    final from = mover.shownDistance;
    // Who gets captured is read off the engine state before and after,
    // rather than by borrowing the controller's onCapture callback, which
    // belongs to other listeners (sound).
    final onTrack = [
      for (final t in _tokens.keys)
        if (t.color != move.token.color && t.distance > 0) t,
    ];
    controller.selectMove(move);
    if (_state.phase != GamePhase.animating) return; // not a legal move
    final captured = [for (final t in onTrack) if (t.distance == 0) t];

    _busy = true;
    selectedToken = _autoPick = armedMove = null;
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
    _layoutTokensIfNeeded(); // back into the ground layer before anything else flies

    // Only the moments worth stopping for get the big callout, right on
    // impact; a bonus roll is announced in the pod (see _nextTurn).
    final finished = move.token.state == TokenState.finished;
    final accent = playerPalette[color]!.base;
    final landing = positionForDistance(color, move.newDistance);
    if (captured.isNotEmpty) {
      _callout(move.isBackward ? 'Backstrike!' : 'Captured!', landing, accent);
      _board
        ..shake()
        ..add(
          captureBurst(
            landing,
            attacker: accent,
            victim: playerPalette[captured.first.color]!.base,
          )..priority = 900,
        );
      _haptic(HapticFeedback.heavyImpact);
      await Future.wait([
        for (final token in captured) _knockHome(_tokens[token]!),
      ]);
    } else if (finished) {
      _callout('Home!', landing, accent);
      _board.add(
        homeSparkle(landing, accent)
          ..priority = 900,
      );
      _haptic(HapticFeedback.mediumImpact);
    }

    final placesBefore = _state.finishOrder.length;
    controller.completeMove();

    // Last token home: this player takes a place. The first gets the
    // confetti; the rest of the table plays on for the other places.
    // (At game over the last player left is added to finishOrder too.)
    if (_state.finishOrder.length > placesBefore) {
      final place = placesBefore + 1;
      prompt = null; // the pod shows the place instead
      _haptic(HapticFeedback.heavyImpact);
      if (place == 1) {
        _toast.show('${colorLabel(color)} wins!', accent: accent, hold: 2.2);
        add(confetti(size, winner: accent)..priority = 100);
      } else {
        _toast.show('${colorLabel(color)} takes ${placeLabel(place)}!', accent: accent, hold: 1.6);
      }
      await _wait(LudiMotion.placeBeat);
    }

    if (_state.phase == GamePhase.gameOver) {
      return; // stays locked — the Flutter shell shows the standings
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
    _layoutTokensIfNeeded();
  }

  /// Unlocks input for whoever plays next, sending the die over first
  /// if the turn changed hands. A player who keeps the die is told so,
  /// with the count when a move earned more than one bonus roll.
  Future<void> _nextTurn() async {
    final next = _state.currentPlayer.color;
    final again = next == activeColor;
    if (!again) {
      prompt = null;
      activeColor = next;
      await _dice.travelTo(_pods[next]!.diceSlot);
    }
    _dice.position = _pods[next]!.diceSlot; // in case the screen resized
    final rolls = _state.bonusRollsRemaining + 1;
    prompt = !again
        ? 'Tap to roll'
        : rolls > 1
        ? 'Roll again ×$rolls'
        : 'Roll again';
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
