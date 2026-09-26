# Ludi — Master Project Spec
**Single source of truth for both Vedant's and Aditi's Claude Code instances.**

---

## Start Here (Claude Code: read this first)

- **If you are Vedant's Claude Code instance:** your owned scope is **Section 10**. Full read/write access to `lib/rules_engine/`, `lib/state/`, `test/`, and repo root/config. Everything else is read-only reference.
- **If you are Aditi's Claude Code instance:** your owned scope is **Section 11**. Full read/write access to `lib/game/`, `lib/audio/`, `lib/ui/`, `assets/`. Everything else is read-only reference.
- **Section 6 (Shared Contract)** is read-only for both — Vedant implements it for real, Aditi mocks it exactly as written until the real thing lands. Neither side changes its shape unilaterally.
- Full scope rules and the "what to do if you need something the other person owns" protocol are in **Section 9**.

---

## 1. Concept & Core Rules

Ludi is a bidirectional Ludo variant. It plays by classic Ludo rules with one twist: a token can move **backward only if doing so captures an opponent token**. If the dice roll doesn't produce a valid kill behind the token, that token must move forward instead.

- A token always has the option to move forward (standard Ludo movement).
- A token may move backward by the dice value **only if** the destination square is occupied by an opponent's token *and* that square isn't a safe square (e.g. a home-entry tile) — landing there kills the opponent, same as a forward capture.
- If the backward distance doesn't land exactly on a capturable opponent, backward is simply not offered as an option for that token on that roll — only forward is legal.
- Backward movement still cannot retreat a token past its entry point (distance floor = 0; can't re-enter the yard).

**Rule details (as implemented in `lib/rules_engine/`):**

- **Board:** 52-square shared loop. Start squares 0/13/26/39 (red/green/yellow/blue) and star squares 8/21/34/47 are the 8 safe squares — no capture happens on them, in either direction.
- **Leaving the yard:** only on a 6, onto the color's own start square (distance 1); the whole roll is used.
- **Home:** distance 1–51 is the shared track, 52–56 the private home column, 57 the finish. The finish needs an exact roll — overshooting isn't a legal move.
- **Capture:** landing on a non-safe square sends every opponent token there back to its yard (a stacked pair goes home together), so no non-safe square is ever shared by two colors.
- **Backward:** only as a kill, and only onto the shared track — a token in its home column may strike back out onto the track, but never steps backward within the column.
- **Bonus rolls:** rolling a 6, capturing, and finishing a token each earn one extra roll, and they stack (a 6 that captures earns two). A 6 with no legal move still earns its re-roll. No cap on consecutive 6s.
- **No legal move:** the roll is wasted; the turn passes unless a bonus roll is still owed.
- **Winning:** the first player to finish all 4 tokens wins and the game ends.

**Team:** two developers — Vedant (code & logic, owns the repo/folder structure) and Aditi (creative & rendering).
**Target:** Google Play. **MVP monetization:** none — fully free for now (see Section 8).

---

## 2. Architecture Overview

Four strictly separated layers. This is the most important architectural decision — it's what lets Vedant and Aditi work in parallel without stepping on each other.

```
┌─────────────────────────────┐
│   Presentation (Flutter)     │  Menus, settings, game-over screens
├─────────────────────────────┤
│   Rendering (Flame)          │  Board, tokens, dice, tweens, effects
├─────────────────────────────┤
│   Audio (flame_audio)        │  Move/capture/win/dice sound cues
├─────────────────────────────┤
│   Rules Engine (pure Dart)   │  Board state, legal moves, capture logic, turn order
└─────────────────────────────┘
```

The **Rules Engine has zero Flutter/Flame imports** — plain Dart, unit-testable in isolation. The rendering/audio/UI layers read from it and call into it; they never contain rule logic themselves.

---

## 3. Data Model

Flat structures — no dependency graphs, no nested config objects.

```dart
enum TokenState { yard, active, homeStretch, finished }
enum PlayerColor { red, green, yellow, blue }

class Token {
  final String id;
  final PlayerColor color;
  int distance;        // 0 = yard. 1-51 = shared track. 52-56 = home column. 57 = finished.
  TokenState state;
}

class Player {
  final PlayerColor color;
  final int startSquare;   // offset into the 52-square shared track
  final List<Token> tokens; // 4 tokens per player
  final bool isAI;
}

class GameState {
  final List<Player> players;
  int currentPlayerIndex;
  int lastDiceValue;
  List<Move> legalMoves;   // recalculated each turn
  GamePhase phase;          // rolling, selecting, animating, gameOver
}

class Move {
  final Token token;
  final int newDistance;
  final bool isBackward;
  final Token? capturedToken; // null if no capture
}
```

**Board layout:** single shared 52-square track (indices 0–51), each player's `startSquare` is an offset into it, plus a private 6-step home stretch per color (indices 52–57 relative to that player: 52–56 are the 5 home-column squares, 57 is the finish).

---

## 4. Rules Engine — Core Logic

The bidirectional twist lives in one function. Forward is always evaluated; backward is only added to the legal-moves list if it would land exactly on a capturable opponent token:

```dart
List<Move> getLegalMoves(Token token, int diceValue, GameState state) {
  final moves = <Move>[];

  // Forward — always allowed if the destination is valid
  final forwardDist = token.distance + diceValue;
  if (isValidDestination(forwardDist)) {
    moves.add(buildMove(token, forwardDist, isBackward: false, state));
  }

  // Backward — ONLY legal if it lands exactly on an opponent token (a kill).
  // No capturable opponent at that square -> backward is not offered at all.
  if (token.state != TokenState.yard) {
    final backwardDist = token.distance - diceValue;
    if (isOnSharedTrack(backwardDist)) { // 1-51: not the yard, not the home column
      final destSquare = toSharedSquare(token.color, backwardDist);
      final wouldCapture = checkCapture(destSquare, token.color, state);
      if (wouldCapture != null) {
        moves.add(buildMove(token, backwardDist, isBackward: true, state));
      }
    }
  }

  return moves;
}
```

Capture check is unchanged — same function serves both directions, and already excludes safe squares (this is what covers "can't kill a token sitting on a home-entry/safe tile"):

```dart
Token? checkCapture(int destSquare, PlayerColor movingColor, GameState state) {
  if (isSafeSquare(destSquare)) return null;
  for (final player in state.players) {
    if (player.color == movingColor) continue;
    for (final t in player.tokens) {
      if (t.state == TokenState.active && toSharedSquare(t) == destSquare) {
        return t; // gets sent back to yard
      }
    }
  }
  return null;
}
```

**Unit test this exhaustively before writing any Flame code.** In particular, test both directions of the new rule: a roll that *does* line up a backward kill, and a roll that doesn't (where backward must simply not appear in `legalMoves` at all) — plus the existing edge cases around safe squares and the home-stretch boundary.

**State management:** a single `GameController extends ChangeNotifier` owns `GameState`, exposes `rollDice()` / `selectMove(Move)`, and notifies listeners after each mutation. No Bloc, no Riverpod. Flame components and Flutter widgets both just listen to this one controller.

---

## 5. Animation, Audio & Monetization

**Animation (Flame):**
- Each token's path is a precomputed `List<Vector2>` of waypoints (52 shared + 6 home-stretch per color).
- Forward move = walk the waypoint sublist in order. Backward move = walk it in reverse — same tween code, reversed list slice.
- Use `MoveEffect.to()` chained via `SequenceEffect` for multi-square moves (visibly hop square-by-square, not slide straight there).
- Capture = short "knockback" `MoveEffect` + `ScaleEffect`, then reset to yard position.
- Dice roll = `RotateEffect` + `ScaleEffect` combo, ~600ms.
- Since backward moves are now only ever legal when they capture, the backward tween and the capture knockback effect **always fire together** — no need to build a "silent retreat" animation with no capture.

**Audio (`flame_audio`):** preload `dice_roll.mp3`, `token_move.mp3`, `capture.mp3`, `token_home.mp3`, `game_win.mp3`, `game_lose.mp3`. Respect a mute toggle stored in `SharedPreferences`, one visible tap — not buried in settings.

**Monetization:** MVP ships fully free — no ads, no IAP. If added later, it slots in as an isolated module (e.g. `ads/ad_manager.dart`) called only from the UI layer, without touching the rules engine, rendering, or state management.

---

## 6. Shared Contract

This is the seam between Vedant's and Aditi's work. Vedant implements it for real; Aditi mocks it exactly as written until the real implementation lands.

```dart
// lib/rules_engine/models/... — Vedant owns the real implementation.
// (Token, Player, GameState, Move — full shape in Section 3 above.)

// GameController public API — lib/state/game_controller.dart
class GameController extends ChangeNotifier {
  GameState get state;
  List<Move> get currentLegalMoves;
  void rollDice();
  void selectMove(Move move);

  // Animation handshake: built with holdMovesForAnimation: true, a selected
  // move stops in GamePhase.animating (board already updated, turn not yet
  // resolved) until the Flame layer calls completeMove() after its hop /
  // capture animations. Off by default — selectMove then resolves at once.
  GameController({GameState? initialState, Random? random,
                  bool holdMovesForAnimation = false});
  void completeMove();

  // Callbacks Aditi's Flame layer listens to, to trigger animation + sound:
  // - onMoveAnimated(Move move)
  // - onCapture(Token captured)
  // - onGameOver(PlayerColor winner)
}
```

---

## 7. Folder Structure

Owned by Vedant — created as the first commit (Module V1, Section 10).

```
ludi/
├── lib/
│   ├── main.dart
│   ├── rules_engine/              # pure Dart, no Flutter/Flame imports — VEDANT
│   │   ├── models/
│   │   │   ├── token.dart
│   │   │   ├── player.dart
│   │   │   ├── game_state.dart
│   │   │   └── move.dart
│   │   ├── legal_moves.dart
│   │   ├── capture_logic.dart
│   │   ├── dice.dart
│   │   └── turn_manager.dart
│   ├── state/
│   │   └── game_controller.dart   # ChangeNotifier bridging engine ↔ UI — VEDANT
│   ├── game/                      # Flame layer — ADITI
│   │   ├── ludi_game.dart
│   │   ├── components/
│   │   │   ├── board_component.dart
│   │   │   ├── token_component.dart
│   │   │   ├── dice_component.dart
│   │   │   └── path_waypoints.dart
│   │   └── effects/
│   │       ├── move_tween.dart
│   │       └── capture_effect.dart
│   ├── audio/                     # ADITI
│   │   └── sound_manager.dart
│   └── ui/                        # ADITI
│       ├── home_screen.dart
│       ├── game_screen.dart
│       └── widgets/
├── test/
│   └── rules_engine/              # VEDANT — most of the test effort goes here
│       ├── legal_moves_test.dart
│       └── capture_logic_test.dart
└── assets/                        # ADITI
    ├── images/
    └── sounds/
```

---

## 8. Testing Strategy

- **Rules engine:** unit tests only. Cover forward/backward legality, capture in both directions, home-stretch boundary, yard-retreat floor.
- **Flame layer:** manual testing is fine given the solo-hobby time budget per person — full widget/integration coverage isn't worth the investment here.

---

## 9. Claude Code Scope Rules

**Vedant's Claude Code**
- Full read/write: `lib/rules_engine/`, `lib/state/`, `test/`, repo root/config files.
- Read-only reference: `lib/game/`, `lib/audio/`, `lib/ui/`, `assets/`.
- If a task requires touching Aditi's owned files (e.g. wiring `GameController` into a Flame component so a test can run end-to-end), make only the **minimal change needed** — a hookup call, not new rendering/animation logic — and leave a `// TODO(Aditi):` comment explaining what was touched and why.

**Aditi's Claude Code**
- Full read/write: `lib/game/`, `lib/audio/`, `lib/ui/`, `assets/`.
- Read-only reference: `lib/rules_engine/`, `lib/state/`, `test/`.
- If a task depends on a Vedant module that isn't built yet, **mock it locally using the exact shape in Section 6** — never invent a different shape — and leave a `// TODO(Vedant):` comment. Don't implement rules-engine or game-logic code.

---

## 10. Vedant — Owned Modules (Code & Logic + Repo Structure)

Vedant creates the repo and pushes the full folder skeleton with contract stubs as the very first commit — this unblocks Aditi immediately instead of making her wait on real logic.

**Status: V1–V7 complete, all merged into `dev`.** `GameController` (Section 6) is now the real implementation, not a stub — Aditi's Claude Code instance can wire against it directly instead of mocking it.

| # | Module | Description | Files/Folders | Depends on |
|---|---|---|---|---|
| V1 | Repo & folder scaffold | Create repo, full `lib/**` structure (Section 7), empty stub files for the Shared Contract | repo root, `lib/**` skeleton | none — do first |
| V2 | Data models | `Token`, `Player`, `GameState`, `Move` | `lib/rules_engine/models/` | V1 |
| V3 | Legal move calculation | Forward moves + backward-**only**-if-it-captures, yard-retreat floor | `lib/rules_engine/legal_moves.dart` | V2 |
| V4 | Capture logic | Direction-agnostic capture check, safe squares | `lib/rules_engine/capture_logic.dart` | V2 |
| V5 | Turn manager + dice | Turn order, dice roll, phase transitions | `lib/rules_engine/turn_manager.dart`, `dice.dart` | V3, V4 |
| V6 | GameController | ChangeNotifier bridging engine ↔ UI, exposes the Shared Contract API | `lib/state/game_controller.dart` | V5 |
| V7 | Unit tests | Forward/backward moves, captures, edge cases | `test/rules_engine/` | V2–V5 |

---

## 11. Aditi — Owned Modules (Creative & Rendering)

| # | Module | Description | Files/Folders | Depends on |
|---|---|---|---|---|
| A1 | Visual design | Board layout, palette, token/dice look, theme | design files, `assets/images/` | none |
| A2 | Board & token Flame components | `BoardComponent`, `TokenComponent` rendering current state | `lib/game/components/` | V2 shape — **mockable** |
| A3 | Dice component + roll animation | `DiceComponent`, roll tween | `lib/game/components/dice_component.dart` | V6 `rollDice()` — **mockable** |
| A4 | Move & capture animations | Forward/backward token tweens, capture knockback | `lib/game/effects/` | V6 `onMoveAnimated`/`onCapture` — **mockable** |
| A5 | Audio | Source clips, `SoundManager`, mute toggle | `lib/audio/` | none — build standalone, wire in later |
| A6 | UI screens | Home, game screen, HUD, game-over | `lib/ui/` | V6 full controller — **mockable for layout**, real for final wiring |
| A7 | Branding | App icon, Play Store graphics, splash screen | `assets/`, store listing | none |

**Status:** A1–A3 by Aditi. At the project owner's request, Vedant's instance then built out A4 (hop / capture / home animations in `lib/game/effects/`, driven by `LudiGame`), A6 (home screen with player count + rules, game screen, HUD pods, winner card) and reworked A2/A3 to match (tiled board, token stacking, dice handoff). Nunito is bundled in `assets/fonts/`. **Still open:** A5 audio (no sound assets yet) and A7 branding (app icon; the Android splash only got the palette background).

---

## 12. Dependency Map — What Blocks What

| Aditi's task | Needs from Vedant | Blocking or mockable? |
|---|---|---|
| A2 — board/token rendering | V2 data shapes | Mockable — use Section 6, don't wait for V2 |
| A3 — dice animation | V6 `rollDice()` + dice value | Mockable — fake a dice value locally |
| A4 — move/capture animation | V6 `onMoveAnimated` / `onCapture` | Mockable — fire fake events, swap to real callbacks later |
| A6 — UI screens (final wiring) | V6 full `GameController` | Mockable for layout only; **real integration needs V6 done** |

**Nothing on Aditi's side is hard-blocked** past day one, as long as the Shared Contract is respected — every downstream task can be built against a local mock and swapped later with no rework.

The one genuinely blocking step for **both** developers: **V1 (repo + folder scaffold)**. Nothing gets committed until it exists.

---

## 13. Git Workflow

- Vedant created the repo, pushed V1 (folder skeleton + contract stubs) as the first commit.
- **Branches:** `dev` is the active integration branch (default branch). `main` is the release branch. Everyone branches off a freshly-pulled `dev`, never off `main`.
- **Branch naming:** one branch per module, prefixed by owner — `vedant/<module>` (e.g. `vedant/legal-moves`, `vedant/turn-manager`) and `aditi/<module>` (e.g. `aditi/board-component`, `aditi/dice-animation`).
- **PRs target `dev`, not `main`.** Both Claude Code instances open PRs with base `dev`. Small, frequent PRs — folders are physically separated by owner, so merge conflicts should be rare.
- **Review gate:** every commit, push, and PR is explicitly authorized by the human owner first — Claude Code implements + tests on a branch and reports back; it does not commit/push/open a PR unprompted. The `auto-assign-reviewer` workflow cross-assigns Vedant ↔ Aditi as reviewer on every PR.
- **`dev` → `main` promotion is Vedant's call only.** Neither Claude Code instance merges `dev` into `main` or pushes directly to `main` — that promotion is done manually by Vedant once a batch of merged `dev` work is verified stable. Aditi's Claude Code instance should never touch `main` at all.
- If the Shared Contract (Section 6) needs to change (e.g. `Move` gains a new field), open a PR against just that file and flag it to the other person before merging — it's the one surface both sides depend on.

---

## 14. Phased Roadmap

| Phase | Scope |
|---|---|
| **1 — MVP** | Local pass-and-play, full bidirectional rules, animations, sound, no monetization. Shippable on its own. |
| **2** | Simple heuristic AI opponent (prefer captures > escape threats > progress furthest token). No minimax needed. |
| **3** | Online multiplayer via Firebase Realtime Database — turn sync, matchmaking, reconnect handling. Separate project phase; doesn't block Phase 1 shipping. |