# Changelog

All notable changes to this project are documented here. This page mirrors
[`CHANGELOG.md`](https://github.com/nerima-lisp/cl-history-kit/blob/main/CHANGELOG.md)
at the repository root, which remains the source of truth. Releases are also
listed on the [GitHub releases page](https://github.com/nerima-lisp/cl-history-kit/releases).

## [0.1.0] - 2026-07-25

### Added

- First release of `cl-history-kit`: a dependency-free command-history store,
  search, and recall navigation library for Common Lisp. The runtime system has
  no external dependencies; only the test system uses `cl-weave`.
- Store: `make-history` with a `:capacity` bound (oldest entries evicted) and a
  `:duplicate-policy` of `:remove` (a repeated command moves to the top) or
  `:keep` (an exact chronological log). Readers `history-entries` (a fresh
  list), `history-count`, `history-capacity`, `history-empty-p`, and
  `history-duplicate-policy`. See [Entries and the Store](store.md).
- Entries: `make-history-entry` producing an immutable value object carrying
  `text`, a universal-time `timestamp`, and an optional integer `exit-code`,
  with `history-entry-texts` for bulk extraction. Text is copied on
  construction, so a caller may keep filling a reused input buffer.
- Operations: `history-add` (returning the store and the new entry),
  `history-clear`, `history-delete` (returning the number removed), and
  `history-merge`, which accepts a history or a plain entry list and preserves
  each entry's original timestamp and exit code rather than restamping it.
- Search: `history-search` and `history-entry-match-p` across four modes —
  `:prefix`, `:exact`, `:contains`, and `:line-prefix` (matching any line of a
  multi-line entry) — with smartcase enabled by default, deriving case
  sensitivity from the query itself. `history-entry-line-suffix` returns the
  remainder an autosuggestion would append, distinguishing "no match" (`NIL`)
  from "already complete" (`""`). See [Search](search.md).
- Navigation: `history-previous`, `history-next`, `history-navigating-p`, and
  `history-reset-navigation`. The filter is frozen at the moment a walk begins,
  so later steps keep the original prefix even though the buffer now shows a
  recalled line; and the in-progress input is preserved as the origin, so
  walking forward past the newest match restores exactly what was typed.
  Navigation resets automatically on any operation that shifts entry positions.
  See [Recall Navigation](navigation.md).
- MkDocs (Material) documentation site under `docs/` (this site), built offline
  via the `docs` flake package and published to GitHub Pages on push to `main`.
- Nix flake with a `nix flake check` gate running the SBCL suite plus a treefmt
  (nixfmt) formatting check, a shared `nix-setup` composite GitHub Action,
  Dependabot coverage for GitHub Actions, and a scheduled `flake.lock` update
  workflow.

### Notes

Persistence, terminal key binding, and shell-specific parsing of entry text are
out of scope; they belong to the host program. See
[Scope and Non-Goals](scope.md).
