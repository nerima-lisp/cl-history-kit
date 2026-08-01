# Getting Started

`cl-history-kit` has no runtime dependencies. The test system additionally uses
[cl-weave](https://github.com/nerima-lisp/cl-weave).

## Install

=== "Nix flake"

    ```sh
    nix build github:nerima-lisp/cl-history-kit
    ```

    To depend on it from another flake, pinned to a release tag:

    ```nix
    {
      inputs.cl-history-kit = {
        url = "github:nerima-lisp/cl-history-kit/v1.0.0";
        inputs.nixpkgs.follows = "nixpkgs";
      };
    }
    ```

    The suffix is a Git ref, not a version range. Keep the complete, published
    release tag to make builds reproducible; dropping `/v1.0.0` instead tracks
    the default branch.

    [Development](project/development.md#flake-outputs) lists every output the
    flake exposes.

=== "ASDF"

    Put the repository somewhere ASDF looks — `~/common-lisp/`, a Quicklisp
    `local-projects/` directory, or a path on `CL_SOURCE_REGISTRY` — then load
    it:

    ```lisp
    (asdf:load-system "cl-history-kit")
    ```

    Everything public lives in the `history-kit` package:

    ```lisp
    (history-kit:make-history :capacity 500)
    ```

    If you would rather not prefix every call, import the symbols you use:

    ```lisp
    (defpackage #:my-repl
      (:use #:cl)
      (:import-from #:history-kit
       #:make-history #:history-add
       #:history-previous #:history-next))
    ```

## Supported implementations

The library is portable Common Lisp: standard sequence, string, and hash-table
operations only, with no implementation-specific code and no feature
conditionals.

CI builds and tests SBCL on `x86_64-linux`, so that is the combination with a
continuous guarantee, and it is exactly what the flake declares — it never
advertises a platform it does not verify. `aarch64-darwin` was dropped on
2026-08-01, which means `nix develop` and `nix build` no longer work on macOS.
Other implementations and platforms are expected to work, but are not gated
on.

## Verifying the installation

```sh
sbcl --script run-tests.lisp
```

For this direct command, ensure both `cl-history-kit` and the test dependency
`cl-weave` are visible to ASDF first; `nix run .#test` configures that registry
automatically. `nix flake check` additionally builds the packaged system and
runs the coverage, formatting, and documentation checks.

## Record some entries

A store keeps entries newest first and never grows past its capacity.

```lisp
(defparameter *history* (history-kit:make-history :capacity 1000))

(history-kit:history-add *history* "git status" :exit-code 0)
(history-kit:history-add *history* "ls -la" :exit-code 0)
(history-kit:history-add *history* "git commit -m wip" :exit-code 1)

(history-kit:history-count *history*)   ; => 3

(history-kit:history-entry-texts
 (history-kit:history-entries *history*))
;; => ("git commit -m wip" "ls -la" "git status")
```

Recording a command that is already stored moves it to the top instead of
leaving a stale copy behind:

```lisp
(history-kit:history-add *history* "ls -la")

(history-kit:history-entry-texts
 (history-kit:history-entries *history*))
;; => ("ls -la" "git commit -m wip" "git status")
```

That is the default `:remove` duplicate policy. Pass
`:duplicate-policy :keep` at construction for an exact chronological log
instead — see [Entries and the Store](guide/store.md).

## Search

```lisp
(history-kit:history-entry-texts
 (history-kit:history-search *history* "git"))
;; => ("git commit -m wip" "git status")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "commit" :mode :contains))
;; => ("git commit -m wip")
```

Smartcase is on by default: an all-lower-case query matches loosely, and one
containing an upper-case character matches exactly.

```lisp
(history-kit:history-add *history* "Git log")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "git"))   ; loose
;; => ("Git log" "git commit -m wip" "git status")

(history-kit:history-entry-texts
 (history-kit:history-search *history* "Git"))   ; exact
;; => ("Git log")
```

## Recall with Up and Down

`history-previous` is what ++arrow-up++ calls. The text currently in the input
buffer is passed in, and on the first press it becomes the filter for the whole
walk *and* the input restored at the end of it.

```lisp
(defparameter *history* (history-kit:make-history))
(history-kit:history-add *history* "git status")
(history-kit:history-add *history* "ls -la")
(history-kit:history-add *history* "git commit -m wip")

;; The user has typed "git " and presses Up.
(history-kit:history-previous *history* "git ")  ; => "git commit -m wip"
;; "ls -la" is skipped: it does not match the frozen filter.
(history-kit:history-previous *history* "git ")  ; => "git status"
;; Nothing older matches; the cursor stays put.
(history-kit:history-previous *history* "git ")  ; => NIL

;; Down walks back toward the newest match...
(history-kit:history-next *history*)             ; => "git commit -m wip"
;; ...and stepping past it restores what was typed.
(history-kit:history-next *history*)             ; => "git "

(history-kit:history-navigating-p *history*)     ; => NIL
```

## A minimal read-eval-print loop

Putting it together, this is the shape of an interactive loop's history
handling:

```lisp
(defun handle-key (history key buffer)
  "Return the new input buffer after KEY."
  (case key
    (:up   (or (history-kit:history-previous history buffer) buffer))
    (:down (or (history-kit:history-next history) buffer))
    (:enter
     (history-kit:history-add history buffer)   ; also resets navigation
     "")
    (t buffer)))
```

Note that `history-add` resets navigation on its own: recording an entry shifts
every index, so a cursor left over from before would silently point somewhere
else. See [Recall Navigation](guide/navigation.md) for the full set of reset
triggers.

## Where to next

- [Entries and the Store](guide/store.md) — capacity, duplicate policies, merging
- [Search](guide/search.md) — the four modes and smartcase in detail
- [Recall Navigation](guide/navigation.md) — the cursor semantics in full
- [API Reference](reference/api.md) — every exported symbol
