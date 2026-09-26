# Ludi — Visual Style Guide (A1)

**Owner:** Aditi (creative & rendering) · **Status:** locked direction, v1
**Feeds into:** A2 (board/token components), A3 (dice), A4 (animations), A6 (UI screens), A7 (branding)
**Visual mockup:** live board + palette/style reference canvas — source in `design/canvas/` (`Main.dc.html`, `StyleReference.dc.html`)

This doc is the source of truth for every visual decision downstream tasks need. If a later task wants to deviate from something here, update this file first so it stays the single reference — don't let choices drift silently into individual components.

---

## 1. Art direction

**Flat, minimal, modern.** Solid fills, restrained use of shadow (one soft drop-shadow per element max, no heavy gradients, no skeuomorphism). Shapes read clearly at small mobile sizes. Nothing photorealistic.

Reference feel: closer to a clean productivity app or modern casual-game UI than a "physical board game" skin. Rounded corners throughout (see §5).

---

## 2. Color palette

Softened/pastel take on the four classic Ludo colors — still instantly readable as "red/green/yellow/blue" from across a room, but easier on the eyes over a long session than saturated primaries.

### Player colors

| Color | Base (token/home fill) | Deep (shadow/outline/pressed) | Light (path tint on board) |
|---|---|---|---|
| Red | `#E8746B` | `#C6564D` | `#F7D9D6` |
| Green | `#6FBE8E` | `#4E9A6D` | `#D8EFE2` |
| Yellow | `#F0C25E` | `#D1A03D` | `#FBEBC9` |
| Blue | `#6C94D6` | `#4E74B5` | `#DAE5F5` |

Rule of thumb: **Base** for tokens and each player's home yard, **Light** for that player's stretch of the shared track / home-stretch squares, **Deep** for outlines, pressed states, and shadows — never pure black outlines.

### Neutrals

| Role | Value |
|---|---|
| Board background | `#FAF6F0` (warm off-white, not clinical white) |
| Track squares (unowned) | `#FFFFFF` |
| Track grid lines / square borders | `#E4DCD0` |
| Text — primary | `#3A342C` |
| Text — secondary/muted | `#8A8175` |
| App background (menus) | `#FAF6F0` |

No pure `#000000` or pure `#FFFFFF` anywhere except the unowned track squares — keeps the whole palette warm and consistent.

### Safe square marker

Classic star icon, rendered in `#3A342C` at ~40% opacity sitting on the square, OR in the current player's **Deep** shade when that square is inside their colored stretch — whichever reads more clearly once A2 has it on screen; leave as an open call for A2, not fixed here.

---

## 3. Typography

Rounded, geometric sans — matches the flat/minimal shape language. Recommend **Nunito** (Google Font, free, has a variable weight range, reads well at small HUD sizes). Fallback: **Poppins**.

| Use | Weight | Notes |
|---|---|---|
| Screen titles / game-over banners | Bold (700) | |
| HUD (turn indicator, dice value) | SemiBold (600) | |
| Body / settings labels | Regular (400) | |

---

## 4. Token design

- Classic cone/pawn silhouette (the traditional Ludo piece profile), flattened into a simple 2-tone shape: **Base** fill + a subtle **Deep**-colored base/shadow ellipse under it, no gradient on the body itself.
- One consistent silhouette reused across all 4 colors — recolor, don't redesign per color.
- Sized to comfortably overlap 2–3 tokens on one square without fully obscuring each other (stack with a slight offset, not a dead pile).
- Selected/movable token (per `state.legalMoves`) gets a soft pulsing outline or scale-bounce idle animation — exact treatment is A4's call, this doc just flags that tokens need a distinct "selectable" visual state.

---

## 5. Board layout

- Standard cross-shaped Ludo board, single shared 52-square track, portrait orientation only.
- Each player's home yard (4-token holding area) sits in its color's corner, using that color's **Base** fill on a **Light**-tinted panel, fully rounded corners (12–16px radius equivalent).
- Track squares: rounded-square grid cells, `Track grid lines` neutral border, `Light` tint for the 6 squares directly outside each color's home stretch entry + the full home-stretch column itself.
- Center home triangle/finish area: split into 4 colored wedges (each color's **Base**), meeting at a neutral center point.
- Overall corner radius language: **12px** for large panels (yards, HUD cards), **4px** for individual track squares — keep it as a 2-tier system, not ad hoc per component.

---

## 6. Dice

- Classic 3D cube, rendered in the flat art style (flat-shaded faces + one soft contact shadow — not a photoreal render).
- Cube body: neutral off-white (`#FFFFFF`) with `#3A342C` pips — dice stays color-neutral regardless of whose turn it is, so it never gets confused for a token.
- Roll animation: tumble/rotate per §5 of the master spec (`RotateEffect` + `ScaleEffect`, ~600ms) — A3's build, this doc only fixes the dice's visual identity (shape + colors), not motion.

---

## 7. Backward-move visual identity — DEFERRED

Master spec flags this as the core mechanic worth a distinct visual signature. Decision made with Vedant/Aditi: **don't design this in isolation** — build forward-move animation first (A4), see it running, then decide whether backward needs its own tint/sound/whoosh or should stay visually identical. Revisit this section once A4 has a working forward tween.

---

## 8. Branding notes (feeds A7)

- No personal easter egg — keep branding clean and generic, no hidden references.
- App name "Ludi" — wordmark should use the Nunito Bold from §3, no separate display font needed.
- Icon/splash: pull directly from this palette (§2); don't introduce new colors at the branding stage.

---

## 9. Open items for later A-tasks

- [x] A2: safe-square star color — neutral `#3A342C` at ~28% everywhere (reads on white cells; colored cells never carry stars).
- [x] A2: stacking — tokens sharing a square fan out and shrink (2: side by side at 80%, 3: triangle at 72%, 4: 2x2 at 66%), easing into place.
- [x] A4: selectable tokens gently bob with a looping expanding ring in their Deep shade; a token with two options gets a solid ring when picked and its route is dotted in.
- [x] A4: §7 backward flair — no separate move animation (same hops, reversed); instead every capturing option is marked with a rotating crosshair, and a backward kill is called out as "Backstrike!".
- [ ] A7: app icon + splash screen, palette-locked (Android splash now uses the board background; icon still Flutter's default)
