# CLAUDE.md

Guidance for any Claude Code instance working in this repo.

## First step, always

**Read `README.md` in full before touching anything.** It is the single source of truth for both Vedant's and Aditi's Claude Code instances — architecture, data model, scope split, and the module checklist. This file only adds operational rules that sit on top of it.

## Which instance am I?

- **Vedant's instance:** owns `lib/rules_engine/`, `lib/state/`, `test/`, repo root/config. See README Section 10 for the module list. Section 10 (V1-V7) is complete and merged into `dev` — `GameController` is real, not a stub.
- **Aditi's instance:** owns `lib/game/`, `lib/audio/`, `lib/ui/`, `assets/`. See README Section 11.
- Everything outside your own scope is **read-only reference**. If a task needs a file you don't own, see README Section 9 for the protocol (minimal touch + `// TODO(<owner>):` comment, never a full change).
- Section 6 (Shared Contract) is read-only for both sides — don't change its shape unilaterally.

## Git workflow (README Section 13 — full detail there)

- Branch off a freshly-pulled `dev`, never off `main`.
- Branch naming: `vedant/<module>` or `aditi/<module>`.
- PRs target `dev`, not `main`.
- **Never commit, push, or open a PR without the human explicitly asking for it first.** Implement + test on a branch, report back what was built and any design calls made, then wait. Only act on an explicit instruction like "commit this and push to branch X and make PR."
- `dev` → `main` promotion is Vedant's manual call only. Never merge into `main` or push to it directly.

## Before reporting anything as done

- Run `flutter analyze` and `flutter test` — both clean, every time, before telling the human it's ready for review.
- Flag any design call not explicit in the README (e.g. an inferred numeric boundary, an unstated rule) instead of silently guessing.
