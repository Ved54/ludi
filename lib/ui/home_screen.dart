import 'package:flutter/material.dart';

import '../game/ludi_theme.dart';
import '../rules_engine/models/player.dart';
import 'game_screen.dart';
import 'widgets/token_icon.dart';

/// Title screen: logo, player count, Play, and the rules — the backward
/// strike is new to anyone who knows Ludo, so "How to play" is one tap
/// away rather than buried.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _players = 4;

  /// Seats for each player count — 2 players sit on opposite corners.
  static const Map<int, List<PlayerColor>> _seats = {
    2: [PlayerColor.red, PlayerColor.yellow],
    3: [PlayerColor.red, PlayerColor.green, PlayerColor.yellow],
    4: PlayerColor.values,
  };

  void _play() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen(colors: _seats[_players]!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LudiNeutral.boardBackground,
      // Scrolls only when it can't fit — a small phone or a large system
      // font — otherwise the spacers spread it over the full height.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: viewport.maxWidth.clamp(0.0, 420.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          const Spacer(flex: 3),
                          const _Logo(),
                          const SizedBox(height: 18),
                          const Text(
                            'Ludi',
                            style: TextStyle(
                              fontFamily: ludiFontFamily,
                              fontSize: 64,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: LudiNeutral.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Classic Ludo — with a backward strike.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: ludiFontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: LudiNeutral.textSecondary,
                            ),
                          ),
                          const Spacer(flex: 3),
                          const Text(
                            'PLAYERS',
                            style: TextStyle(
                              fontFamily: ludiFontFamily,
                              fontSize: 12,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w800,
                              color: LudiNeutral.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (final count in _seats.keys) ...[
                                if (count != _seats.keys.first) const SizedBox(width: 10),
                                Expanded(
                                  child: _PlayerCountOption(
                                    colors: _seats[count]!,
                                    selected: _players == count,
                                    onTap: () => setState(() => _players = count),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: LudiNeutral.textPrimary,
                                foregroundColor: LudiNeutral.surface,
                                shape: const StadiumBorder(),
                                elevation: 2,
                                textStyle: const TextStyle(
                                  fontFamily: ludiFontFamily,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              onPressed: _play,
                              child: const Text('Play'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () => _showRules(context),
                            style: TextButton.styleFrom(foregroundColor: LudiNeutral.textSecondary),
                            child: const Text(
                              'How to play',
                              style: TextStyle(
                                fontFamily: ludiFontFamily,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    const corners = {
      PlayerColor.red: Alignment.topLeft,
      PlayerColor.green: Alignment.topRight,
      PlayerColor.yellow: Alignment.bottomRight,
      PlayerColor.blue: Alignment.bottomLeft,
    };
    return SizedBox.square(
      dimension: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: LudiNeutral.textPrimary.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: const CustomPaint(painter: _PinwheelPainter()),
            ),
          ),
          for (final MapEntry(key: color, value: corner) in corners.entries)
            Align(alignment: corner, child: TokenIcon(color: color, size: 52)),
        ],
      ),
    );
  }
}

class _PinwheelPainter extends CustomPainter {
  const _PinwheelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    const wedges = [PlayerColor.green, PlayerColor.yellow, PlayerColor.blue, PlayerColor.red];
    for (var i = 0; i < 4; i++) {
      final wedge = Path()
        ..moveTo(corners[i].dx, corners[i].dy)
        ..lineTo(corners[(i + 1) % 4].dx, corners[(i + 1) % 4].dy)
        ..lineTo(center.dx, center.dy)
        ..close();
      canvas.drawPath(wedge, Paint()..color = playerPalette[wedges[i]]!.base);
      canvas.drawPath(
        wedge,
        Paint()
          ..color = LudiNeutral.surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_PinwheelPainter oldDelegate) => false;
}

class _PlayerCountOption extends StatelessWidget {
  const _PlayerCountOption({required this.colors, required this.selected, required this.onTap});

  final List<PlayerColor> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 76,
        decoration: BoxDecoration(
          color: LudiNeutral.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? LudiNeutral.textPrimary : LudiNeutral.gridLine,
            width: selected ? 2.5 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: LudiNeutral.textPrimary.withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${colors.length}',
              style: TextStyle(
                fontFamily: ludiFontFamily,
                fontSize: 24,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: selected ? LudiNeutral.textPrimary : LudiNeutral.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final color in colors)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: playerPalette[color]!.base,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _showRules(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: LudiNeutral.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) => const _Rules(),
  );
}

class _Rules extends StatelessWidget {
  const _Rules();

  static const List<(IconData, String, String)> _rules = [
    (Icons.casino_rounded, 'Roll a 6 to start', 'A token leaves its yard only on a 6.'),
    (Icons.rotate_right_rounded, 'Race clockwise', 'Go once round the board, then up your colored lane. Land exactly on home.'),
    (Icons.gps_fixed_rounded, 'Capture', 'Land on an opponent to send them back to their yard. Stars and start squares are safe.'),
    (Icons.undo_rounded, 'The twist: strike backward', 'You may move a token backward — but only if it lands on an opponent and captures it.'),
    (Icons.replay_rounded, 'Bonus rolls', 'A 6, a capture, or bringing a token home each earn another roll — and they add up. Three 6s in a row, though, and your turn is over.'),
    (Icons.emoji_events_rounded, 'Win', 'First to bring all four tokens home wins — the rest play on for the other places.'),
  ];

  @override
  Widget build(BuildContext context) {
    // Scrollable: six rules don't fit a small phone or a large font.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How to play',
              style: TextStyle(
                fontFamily: ludiFontFamily,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: LudiNeutral.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            for (final (icon, title, body) in _rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: LudiNeutral.boardBase,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 21, color: LudiNeutral.textPrimary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontFamily: ludiFontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: LudiNeutral.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            body,
                            style: const TextStyle(
                              fontFamily: ludiFontFamily,
                              fontSize: 14,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: LudiNeutral.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
