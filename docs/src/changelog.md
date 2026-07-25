# Changelog

All notable changes to this project are documented here. This page mirrors
[`CHANGELOG.md`](https://github.com/nerima-lisp/cl-history-kit/blob/main/CHANGELOG.md)
at the repository root, which remains the source of truth. Releases are also
listed on the [GitHub releases page](https://github.com/nerima-lisp/cl-history-kit/releases).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-07-25

First stable release. The public API is unchanged from 0.4.0 apart from the
fix below; what 1.0.0 adds is the commitment that it will stay that way.

### Stability

- `cl-history-kit` now follows [Semantic Versioning](https://semver.org/), and
  its exported surface is frozen for the 1.x series: no export will be renamed
  or removed and no existing lambda list will change, so new capability can
  only arrive as a new keyword argument defaulting to today's behaviour, or as
  a new function. See [Stability](scope.md#stability) for both halves of the
  contract -- what is covered, and what stays explicitly unstable (every
  `%`-prefixed internal symbol, including the `history` struct's slots; the
  identity of returned lists beyond the documented freshness; the exact
  condition class and report string behind "signals a `type-error`"; and
  performance outside the complexities a docstring states). This is a promise
  the 0.x line had already been keeping in practice: the API grew through
  0.2.0, 0.3.0 and 0.4.0 by addition only, with no export ever renamed or
  removed.

### Fixed

- Navigation: [`history-previous`](api-reference.md#history-previous) accepted
  only the strict booleans `T` and `NIL` for `:wrap`, `:smartcase` and
  `:case-sensitive`, signalling a `type-error` naming a private slot
  (`HISTORY-KIT::CURSOR-WRAP`) for any other true value -- so an ordinary
  generalized boolean such as `1`, which every other flag in the library
  accepts, aborted the walk instead of starting one. The three flags are
  frozen into cursor slots declared `boolean`, the strict `(member t nil)`;
  they are now normalized to that type at the boundary where they are frozen.
  Only the first step of a walk ever writes those slots, so the failure needed
  a walk that actually found a match to surface at all.
- Tooling: `coverage.lisp` failed outright unless its output directory already
  existed -- `ensure-directories-exist` reads a path with no trailing slash as
  naming a *file*, so it created the parents but not the directory itself and
  the following `truename` errored. That is precisely the invocation
  [Contributing](contributing.md#coverage) gives; the Nix wrappers happened to
  hide it by creating the directory first.

### Tests

- New `t/boundary-test.lisp`, mirroring `src/boundary.lisp`: the
  "signals a `type-error` for a wrong-typed argument" contract is documented
  for the whole public surface and frozen by 1.0.0, so it is now asserted for
  every entry point in one sweep instead of spot-checked wherever a spec file
  happened to think of it. Also covers that a rejected call signals *before*
  mutating (an in-progress walk survives it), and that the boundary values the
  contract does admit -- a zero capacity, a zero `:limit`, an empty query, a
  negative exit code -- are accepted rather than rejected. See
  [Error Handling](error-handling.md).
- `history-empty-p` was only ever called on empty stores, so its false branch
  was untested; `sb-cover` reported it as "one branch taken". Covered now, and
  with it every behavioral branch in `src/`. The remaining uncovered branches
  in `store.lisp` are `defstruct` slot type declarations the compiler folds
  away -- see [Coverage](contributing.md#coverage).

### Packaging

- The flake now declares `aarch64-darwin` alongside `x86_64-linux`, and
  `ci.yml`'s `check` job became a matrix running `nix flake check` once per
  declared system on a runner of that platform. The flake's rule -- never
  advertise a platform CI does not verify -- is unchanged; what changed is
  that a second platform is now verified, so `nix develop`, `nix fmt`,
  `nix flake check` and `nix build` work on Apple Silicon instead of failing
  with "does not provide attribute". See
  [Supported implementations](installation.md#supported-implementations).
- `flake.lock` now resolves `cl-weave` to the `v1.0.0` tag `flake.nix`
  declares. The lock had been left resolving the previous `v0.10.0` pin, so
  every Nix build was silently testing against the older dependency.
- `flake.nix` binds its `version` once in the `let` block and `inherit`s it
  into all three derivations, instead of repeating the literal three times
  where a release could leave them disagreeing. Its three `apps` outputs also
  carry a `meta.description`, which `nix flake show` lists and `nix flake
  check` no longer warns about. Contributing gained a
  [Cutting a release](contributing.md#cutting-a-release) section naming the
  two files that carry the version and the order the release steps go in.

## [0.4.0] - 2026-07-25

### Performance

- `history-count` reads a `count` slot maintained by
  `%history-install-entries` -- the single place entries are ever replaced --
  instead of walking `entries` with `length` on every call.
- `history-add` under the default `:remove` duplicate policy displaces a
  repeated entry with a single linear scan (`%history-remove-text`) instead of
  rebuilding a hash table over the whole history (`%history-dedupe`) on every
  recorded entry; under `:remove`, `entries` is already duplicate-free by
  induction, so at most one existing entry can ever need displacing.
- `history-search`'s `:limit` now stops scanning as soon as that many matches
  are found, instead of scanning every entry and truncating the result
  afterward, so a small `:limit` against a large, mostly-unmatching history
  costs proportionally to where the last match sits rather than to the
  history's total size.
- `history-merge` prepends `source`'s entries in front of `target`'s in one
  batch and applies `target`'s duplicate policy and capacity to the combined
  list a single time, instead of calling `history-add` once per entry (which
  re-deduped and re-capped on every single entry). This turns an
  O(entry count × target capacity) merge into one that is only O(entry count +
  target capacity), which matters when loading a large history from disk into
  an already-full store. Behavior is unchanged -- see the docstring for why
  the batched form produces the same survivors in the same order.
- `src/package.lisp` declares `(optimize (speed 3) (safety 1)
  (compilation-speed 0))` globally (it loads first, and SBCL's `optimize`
  proclamation is a whole-compilation-unit policy, not a per-file one). Every
  public entry point already validates its arguments at the boundary via
  `define-checked-function`, so the bodies behind that boundary -- and the
  internal (`%`-prefixed) helpers they call, which already assumed valid
  input by convention -- no longer pay for `safety 3`'s redundant runtime
  checking to stay correct.
- `%history-cap`, the shared truncate-to-capacity step behind every mutating
  operation, now detects whether truncation is even needed with `nthcdr`
  instead of `length`: `nthcdr` walks at most `capacity` cells and stops as
  soon as it learns whether there is a capacity-plus-first entry, where
  `length` walked the whole list regardless. Below capacity this still
  returns the list unchanged, with no copying, exactly as before; over
  capacity -- notably right after `history-merge` combines a large `source`
  with an already-full `target` -- the truncation check itself now costs
  `capacity` instead of the combined list's full size.
- `%history-dedupe`'s hash table is now sized to `entries`' length up front,
  instead of growing (and rehashing) from a small default as it fills.

### Changed

Internal refactor with no public API change; every existing export keeps its
exact signature and behavior, verified by the 91-check suite plus one new
check (92 total) covering a branch the `history-merge` batching rewrite below
introduced.

- Operations: `history-delete`, `history-dedup`, and `history-delete-if`
  shared the same "compute survivors, and only when something was actually
  removed, install them and reset navigation" shape three times over. That
  shape is now a single macro, `%purging`, so the shared install-if-changed
  protocol has exactly one definition instead of three near-identical copies.
- Navigation: `history-previous` and `history-next` each duplicated a "try the
  primary scan, and only on a miss, if wrapping, try the wraparound scan"
  cascade with their own bookkeeping on success and their own fallback on
  failure. That cascade is now one continuation-passing combinator,
  `%scan-with-wrap`, taking success/failure continuations instead of being
  reconstructed at each call site via nested `multiple-value-bind`/`when`.
- Boundary validation: every public entry point (`make-history-entry`,
  `make-history`, the `history-*` readers and operations, `history-search`
  and friends, and the navigation functions) is now defined with a new macro,
  `define-checked-function` (`src/boundary.lisp`), instead of a bare `defun`
  opening with imperative `check-type` calls. The checks are now a
  declarative `(var type)` list the definition carries as data, separate from
  the logic in its body; `define-checked-function` also makes a docstring
  structurally mandatory, matching the convention every public function
  already followed. Internal (`%`-prefixed) helpers are unaffected -- they
  assume valid input by design and stay plain `defun`s.
- Tooling: `coverage.lisp` (and `nix build .#coverage` / `nix run .#coverage`)
  reproduces this project's `cl-weave:coverage-statistics` /
  `save-coverage-report` measurement as a checked-in, reproducible script and
  Nix package instead of an ad-hoc one-off; see [Contributing](contributing.md)'s
  new Coverage section for what the numbers mean and why the raw expression
  percentage cannot reach 100.
- Dependencies: the test-only `cl-weave` pin moves from `v0.10.0` to `v1.0.0`
  (`cl-weave`'s first stable, SemVer release; see its own changelog for the
  correctness fixes this picks up). No test-facing API used by this project
  changed. `cl-history-kit/test`'s `:depends-on` now pins `(:version
  "cl-weave" "1.0.0")` in the `.asd` itself, not just `flake.nix`, so a
  non-Nix ASDF/Quicklisp checkout also refuses an incompatible `cl-weave`.
- CI: the `check` job in `ci.yml` and the `update` job in `flake-update.yml`
  now carry an explicit `timeout-minutes`, matching `docs.yml`'s existing
  practice, so a hung job fails visibly instead of running to the platform
  default.
- Docs: dropped stale `0.1.0`-pinned phrasing in the README and
  `docs/src/scope.md` / `docs/src/error-handling.md` that had not been updated
  across three subsequent releases; `scope.md`'s Stability section now
  describes the actual 0.2.0 → 0.4.0 track record (additive only, no renames)
  instead of speculating about a since-passed 0.2.0.

## [0.3.0] - 2026-07-25

### Added

- Navigation: `history-previous`/`history-next` accept `&key (wrap nil)`,
  frozen alongside the filter and mode for the whole walk, exactly like
  `current-input` and `mode`. With `wrap t`, stepping past either end cycles
  to the other instead of ending the walk there — origin-restore and wrap are
  mutually exclusive per walk, so a wrapping walk only ends via an explicit
  `history-reset-navigation` or an operation that already resets navigation
  unconditionally (`history-add`, `history-clear`, a `history-delete` that
  removed something). See [Wraparound](navigation.md#wraparound). This is the
  piece that was still missing to drive a Ctrl-R-style search that cycles
  through matches indefinitely instead of stopping dead at either end.
- Navigation: `history-previous`/`history-next` accept `&key case-sensitive
  (smartcase t)`, mirroring `history-search`'s exact keyword shape (see
  [Case sensitivity](navigation.md#case-sensitivity)) and frozen the same way
  as `mode` and `wrap`. Previously the cursor only ever derived sensitivity
  from smartcase with no way to override it explicitly, unlike every other
  matching entry point in the library.
- Operations: `history-dedup`, compacting a store in place by removing later
  entries that repeat an earlier one's text under the same comparison the
  `:remove` duplicate policy already applies at add-time. See
  [Removing](store.md#removing). This is the on-demand purge nshell's own
  history module had and cl-history-kit lacked — useful for cleaning up a
  history loaded verbatim from disk, or from a `:keep`-policy store, without
  waiting for every entry to be re-recorded.
- Operations: `history-delete-if`, deleting every entry for which a predicate
  — called with the `history-entry` object itself, not just its text —
  returns true. See [Removing](store.md#removing). This is a second, separate
  filtering paradigm from `history-delete`'s exact-text match, added as its
  own function rather than an overloaded parameter, so a host can purge by
  exit code or timestamp without a tokeniser or a text comparison standing in
  the way.
- Search: `history-search` accepts `&key limit`, truncating the newest-first
  result to at most that many of the newest matches. See
  [Limiting results](search.md#limiting-results). A cheap, architecturally
  consistent addition for a host that only ever renders the first page of
  results.

## [0.2.0] - 2026-07-25

### Added

- Navigation: `history-previous` accepts `&key (mode :line-prefix)`, one of
  `history-search`'s four modes (see [Search](search.md#modes)), frozen
  alongside the filter for the whole walk exactly as `current-input` is. A
  plain Up/Down key pair keeps its existing `:line-prefix` behaviour with no
  change; a host can additionally bind `:contains` (or `:prefix` / `:exact`)
  to drive a Ctrl-R-style incremental search over the same cursor mechanics,
  instead of hand-rolling a second search state. See
  [Choosing a match mode](navigation.md#choosing-a-match-mode). An unknown
  `mode` signals the same error `history-search` does.

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
