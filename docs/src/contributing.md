# Contributing

Contributions are welcome. This page covers the development workflow, how to
run the tests, and the conventions the codebase follows.

## Development environment

The repository is a Nix flake. The simplest way to get a working toolchain is:

```sh
nix develop
```

This drops you into a shell with SBCL and `CL_SOURCE_REGISTRY` already pointing
at this checkout and `cl-weave`. If you use [direnv](https://direnv.net/),
`direnv allow` loads it automatically.

If you prefer a local SBCL, ensure `cl-history-kit` and (for the tests)
`cl-weave` are visible to ASDF, then load the system:

```lisp
(asdf:load-system "cl-history-kit")
```

## Running the tests

```sh
sbcl --script run-tests.lisp
```

or, through Nix, which additionally runs the treefmt formatting gate:

```sh
nix flake check
```

`nix run .#test` runs the suite on its own.

The suite uses [cl-weave](https://github.com/nerima-lisp/cl-weave). Every spec
gets a 10-second per-attempt wall-clock budget, so a hanging test fails with a
clear timeout status rather than stalling CI.

## Repository layout

```text
src/
  package.lisp      the single public package; everything else is internal
  text.lisp         case-aware text predicates (prefix, equal, contains, line)
  entry.lisp        the immutable entry value object
  store.lisp        the bounded store and its checked readers
  operations.lisp   add, clear, delete, merge
  search.lisp       the four search modes and the autosuggestion suffix
  navigation.lisp   the recall cursor
t/
  package.lisp      the test package and the RUN-TESTS entry point
  matchers.lisp     domain matchers and generators shared by every spec
  *-test.lisp       one spec file per concern, mirroring src/
docs/
  mkdocs.yml        Material for MkDocs configuration
  src/              the documentation pages
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

- **Validate at the boundary.** Every public entry point begins with
  `check-type` on its arguments. Internal helpers assume valid input.
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
3. Update `CHANGELOG.md` under an `Unreleased` heading.
4. Make sure `nix flake check` passes.
