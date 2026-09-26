import 'dart:ui' show ImageFilter;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/ludi_game.dart';
import '../game/ludi_theme.dart';
import '../rules_engine/models/game_state.dart';
import '../rules_engine/models/player.dart';
import '../state/game_controller.dart';
import 'widgets/token_icon.dart';

/// One pass-and-play game: the Flame scene (board, HUD pods, die) fills
/// the screen; Flutter adds the exit button and the winner card. One
/// GameController per screen, disposed with it.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.colors = PlayerColor.values});

  /// Who is playing, 2-4 colors.
  final List<PlayerColor> colors;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController _controller = GameController(
    initialState: newGame(colors: widget.colors),
    holdMovesForAnimation: true,
  );
  late final LudiGame _game = LudiGame(controller: _controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _inProgress => _controller.state.phase != GamePhase.gameOver;

  Future<void> _leave() async {
    final navigator = Navigator.of(context);
    if (_inProgress && !await _confirmLeave()) return;
    navigator.pop();
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LudiNeutral.surface,
        title: const Text('Leave this game?'),
        content: const Text('Progress in this game will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  void _playAgain() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => GameScreen(colors: widget.colors)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: LudiNeutral.boardBackground,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              GameWidget(game: _game),
              Positioned(
                left: 8,
                top: 4,
                child: _RoundButton(icon: Icons.arrow_back_rounded, onTap: _leave),
              ),
              const Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: IgnorePointer(child: _Wordmark()),
              ),
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _controller.state.phase == GamePhase.gameOver
                    ? _WinnerCard(
                        winner: _controller.state.currentPlayer.color,
                        onPlayAgain: _playAgain,
                        onHome: () => Navigator.of(context).pop(),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Ludi',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: ludiFontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        color: LudiNeutral.textPrimary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LudiNeutral.surface,
      shape: const CircleBorder(),
      elevation: 1.5,
      shadowColor: LudiNeutral.textPrimary.withValues(alpha: 0.3),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: LudiNeutral.textPrimary, size: 24),
        ),
      ),
    );
  }
}

/// Slides up over the board once the winner's confetti has started.
class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.winner, required this.onPlayAgain, required this.onHome});

  final PlayerColor winner;
  final VoidCallback onPlayAgain;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final palette = playerPalette[winner]!;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1500),
      builder: (context, t, child) {
        // First ~40% is a pause so the win lands on the board first.
        final appear = Curves.easeOutBack.transform(((t - 0.4) / 0.6).clamp(0.0, 1.0));
        return IgnorePointer(
          ignoring: t < 0.5,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3 * appear.clamp(0, 1), sigmaY: 3 * appear.clamp(0, 1)),
            child: ColoredBox(
              color: LudiNeutral.textPrimary.withValues(alpha: 0.28 * appear.clamp(0, 1)),
              child: Center(
                child: Opacity(
                  opacity: appear.clamp(0.0, 1.0),
                  child: Transform.translate(offset: Offset(0, 40 * (1 - appear)), child: child),
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        width: 290,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        decoration: BoxDecoration(
          color: LudiNeutral.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: palette.deep.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: palette.light, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: TokenIcon(color: winner, size: 58),
            ),
            const SizedBox(height: 16),
            Text(
              '${colorLabel(winner)} wins!',
              style: TextStyle(
                fontFamily: ludiFontFamily,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: palette.deep,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'All four tokens made it home.',
              style: TextStyle(
                fontFamily: ludiFontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: LudiNeutral.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.base,
                  foregroundColor: LudiNeutral.surface,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontFamily: ludiFontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: onPlayAgain,
                child: const Text('Play again'),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onHome,
              style: TextButton.styleFrom(foregroundColor: LudiNeutral.textSecondary),
              child: const Text(
                'Home',
                style: TextStyle(fontFamily: ludiFontFamily, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
