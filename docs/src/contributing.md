# Contributing

Contributions are welcome. This page covers the development workflow, how to
run the tests, and the conventions the codebase follows.

## Development environment

The repository is a Nix flake. The simplest way to get a working toolchain is:

```sh
nix develop
```

This drops you into a shell with SBCL and `CL_SOURCE_REGISTRY` already pointing
at this checkout and `cl-weave`.

If you prefer a local SBCL, ensure `cl-history-kit` and (for the tests)
`cl-weave` are visible to ASDF, then load the system:

```lisp
(asdf:load-system "cl-history-kit")
```

## Running the tests

```sh
sbcl --script run-tests.lisp
```

or, through Nix, which additionally builds the packaged system and runs the
coverage, formatting, and documentation checks:

```sh
nix flake check
```

`nix run .#test` runs the suite on its own.

When other SBCL builds may be active, prefer `nix run .#test`. Each Nix app
uses an isolated `HOME` and `XDG_CACHE_HOME`, while the direct command shares
your usual ASDF cache.

The suite uses [cl-weave](https://github.com/nerima-lisp/cl-weave). Every spec
gets a 10-second per-attempt wall-clock budget, so a hanging test fails with a
clear timeout status rather than stalling CI.

### Coverage

```sh
nix build .#coverage
```

`$out` **is** the report (`result/cover-index.html` and friends). This is
[`cl-nix-forge`](https://github.com/nerima-lisp/cl-nix-forge)'s
`mkCoverageReport`, driven through `run-tests.lisp` -- the same entry point
`checks.default` and `apps.test` use. It wraps `sb-cover` and reports
expression/branch coverage restricted to `src/`, instrumenting only
`cl-history-kit` itself (not `cl-weave` or the test system). Every behavioral
branch — every `if`, `cond`, `when`/`unless`, and the
`%history-navigation-matches` / `%purging` combinators — is exercised by the suite:
`navigation.lisp`, `operations.lisp`, `search.lisp`, and `text.lisp` each
report 100% branch coverage.

`store.lisp` is the one file whose *reported* branch percentage is low while
still having every real behavioral branch covered, so read its number with
care rather than treating it as a gap to close. Most of the uncovered
branches are the `:type` declarations on `defstruct history`'s slots —
`(integer 0 *)`, `(member :remove :keep)`, `(or null vector)` and friends.
`sb-cover` reports each as "neither branch taken": they are slot type checks
the compiler folds away, not code any spec can steer.

The one remaining branch is `%history-install-entries`'s
`(when (= count capacity) (return))` guard against overrunning its backing
array. Every current caller already hands it a list bounded to `capacity` or
smaller — `%purging` only ever shrinks a history's own entries,
`%history-bounded-merge-entries` enforces the bound itself before returning,
and `history-clear` passes none — so the guard's "exactly full" arm cannot
fire without a caller first breaking that invariant. It stays as
defense-in-depth for a private helper rather than being deleted to chase a
cosmetic percentage. The HTML report marks all of this plainly, so if these
numbers ever move, compare against the report before concluding anything.

`sb-cover` cannot mark three categories of form as "executed," even though the
suite exercises the paths behind them, so the raw expression percentage sits
in the low-90s rather than at 100:

- `in-package` forms run before instrumentation begins tracking the compilation
  unit, so every file's `in-package` shows as not-executed.
- Literal `&key` default-value forms (`(mode :line-prefix)`, `(smartcase t)`)
  and `defstruct` slot type declarations are compiled inline / constant-folded,
  so they are never independently steppable, regardless of how many calls take
  the default.
- `defmacro` bodies (`%purging`) run at macroexpansion time, not in the
  instrumented runtime image, so a macro's own body never shows as executed
  even though every call site using it does.

None of these represent an untested code path — do not chase them by removing
type declarations or restructuring default values purely to move the
percentage; that would trade real safety for a cosmetic number.

### Performance regression benchmark

```sh
nix run .#benchmark
```

The benchmark creates a 4,096-entry history and separately reports first
prefix lookup, cached `history-previous` navigation, a merge into a full
bounded history, and recording into a full `:keep` history. The default
`:remove` policy keeps a text index for new recordings; its duplicate path is
separately protected by unit tests because it intentionally compacts retained
entries. The benchmark is a repeatable regression signal, not a claim of an
absolute result across different machines or SBCL builds.

```text
src/
  package.lisp           the single public package; everything else is internal
  boundary.lisp          DEFINE-CHECKED-FUNCTION: argument validation as data
  text.lisp              case-aware text predicates (prefix, equal, contains, line)
  entry.lisp             the immutable entry value object
  store.lisp             the bounded store and its checked readers
  operations.lisp        add, clear, delete, delete-if, dedup
  merge.lisp             combining a second history or entry list into one
  search.lisp            the four search modes and the autosuggestion suffix
  navigation.lisp        the recall cursor
t/
  package.lisp           the test package and the RUN-TESTS entry point
  helpers-matchers.lisp  domain matchers and generators shared by every spec
  *-test.lisp            one spec file per concern, mirroring src/
docs/
  mkdocs.yml             Material for MkDocs configuration
  src/                   the documentation pages
run-tests.lisp           test entry point (see "Running the tests" above)
benchmark.lisp           performance regression benchmark (see below)
```

Files are split by concern rather than by size. A new public function belongs
in the file whose concern it shares, and its specs in the matching `t/` file.

## Conventions

### Naming

- Every public symbol is prefixed `history-` or `make-history-`, so a host can
  `:import-from` them without shadowing anything in `CL`.
- Internal helpers carry a leading `%` and are never exported. If a `%` name
  needs to become public, it gets renamed rather than merely exported.

### Style

- **Validate at the boundary.** Every public entry point is defined with
  `define-checked-function` (`src/boundary.lisp`) rather than a bare `defun`,
  so its `check-type` calls are declared as a CHECKS list -- data the
  definition carries -- instead of imperative statements opening the body.
  Nearly every one of those checks a principal argument (a `history` or a
  `history-entry`) first, so `define-typed-function` -- also in
  `boundary.lisp` -- supplies that one shared check from its own arguments
  rather than a literal every call site repeats; only the two constructors
  (`make-history`, `make-history-entry`) have no such argument and stay on
  plain `define-checked-function`. Internal (`%`-prefixed) helpers assume
  valid input and stay plain `defun`s.
- **`nil` means "nothing happened".** No operation signals to report an
  ordinary miss; see [Error Handling](error-handling.md).
- **One definition per rule.** Case sensitivity and smartcase are defined once
  in `text.lisp` and used by both search and navigation, so the two cannot
  drift apart on what counts as a match.
- **Comment the *why*.** Docstrings state the contract; comments explain a
  decision that is not obvious from the code — such as why `history-add` resets
  navigation.
- No runtime dependencies. A change that would add one needs to justify itself
  against the library's central constraint.

### Tests

- Prefer a domain matcher (`:to-record-texts`, `:to-have-texts`) over raw list
  predicates, so a failure message reads in the library's vocabulary.
- Add a property test for any invariant that should hold across arbitrary
  input — capacity bounds, uniqueness under `:remove`, the
  backward-then-forward round trip. `cl-weave` shrinks counterexamples for you.
- A bug fix arrives with the spec that would have caught it.

## Documentation

The site is built with Material for MkDocs from `docs/src/`:

```sh
nix build .#docs      # offline, --strict
```

`--strict` promotes broken links and unlisted pages to build failures, so a new
page must be added to the `nav:` section of `docs/mkdocs.yml`. Changes under
`docs/` publish to GitHub Pages automatically on push to `main`.

Public API changes need three edits in the same commit: the docstring, the
relevant guide page, and [`api-reference.md`](api-reference.md).

## Formatting

`nix fmt` runs treefmt with nixfmt. Its scope is Nix files only — YAML
formatters mangle the GitHub Actions `on:` key, and Markdown reformatting would
churn the docs tree. `nix flake check` fails on unformatted Nix.

## Submitting a change

1. Open an issue first for anything that changes the public API, so the shape
   can be agreed before the work.
2. Keep the commit focused; a rename and a behaviour change belong in separate
   commits.
3. Describe user-visible changes in the pull request body — that text is what
   the next GitHub Release description is assembled from. This repository has
   no `CHANGELOG.md`.
4. Make sure `nix flake check` passes.

## Cutting a release

Since 1.0.0 the library follows [SemVer](https://semver.org/), and its
exported surface is frozen for the 1.x series — see
[Stability](scope.md#stability) for exactly what that covers. A change that
would break it is a 2.0.0, not a 1.x, and needs the issue from step 1 above
before any code is written.

`cl-history-kit.asd` is the only place the version string is edited: the
`:version` of `cl-history-kit` and of `cl-history-kit/test`. `flake.nix` reads
it via `cl-nix-forge`'s `fromAsdSystem`, which requires both systems'
`:version` forms to agree and fails loudly if they ever drift, so every Nix
derivation follows the `.asd` automatically.

Then:

1. Write the release notes. They live in the GitHub Release description and
   nowhere else — there is no `CHANGELOG.md` and no `docs/src/changelog.md`.
   Select entries by "does a user of this package have to change their own
   code", which is why the notes are not generated from commit titles.
2. Run `nix flake check`. If `flake.nix` pins a new dependency version, commit
   the resulting `flake.lock` in the same change: a lock still resolving the
   previous pin means CI silently tests against the *old* dependency.
3. Tag the release `vX.Y.Z`. `release.yml` runs on that push: it refuses the
   tag if it disagrees with the `.asd` version, re-runs `nix flake check`
   against the tagged tree, and then opens a **draft** release with an empty
   body. Paste the notes from step 1 in and publish it:

   ```sh
   gh release edit vX.Y.Z --notes-file notes.md --draft=false
   ```

   The draft is deliberate: an unpublished release appears neither under
   "Latest release" nor in `gh release list`, so a release whose notes were
   forgotten never reaches downstream. The flake's own `cl-weave` input is
   pinned to such a tag, so downstream flakes can pin this one the same way.
