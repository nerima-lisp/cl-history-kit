# Installation

`cl-history-kit` has no runtime dependencies. The test system additionally uses
[cl-weave](https://github.com/nerima-lisp/cl-weave).

=== "Nix flake"

    ```sh
    nix build github:nerima-lisp/cl-history-kit
    ```

    The flake exposes:

    | Output | What it is |
    | --- | --- |
    | `packages.<system>.cl-history-kit` | The ASDF system, built with SBCL |
    | `packages.<system>.docs` | This documentation site, built offline |
    | `packages.<system>.coverage` | The `sb-cover` report for `src/`; `$out` **is** the report — `nix build .#coverage` |
    | `devShells.<system>.default` | SBCL with the source registry pre-set |
    | `checks.<system>.default` | The SBCL test suite |
    | `checks.<system>.coverage` | The same `sb-cover` report, asserted non-empty |
    | `checks.<system>.formatting` | The treefmt (nixfmt) gate |
    | `checks.<system>.docs` | Asserts the built docs site is non-empty |
    | `apps.<system>.test` | `nix run .#test` — the suite on its own |
    | `apps.<system>.benchmark` | `nix run .#benchmark` — lookup, navigation, merge, and `:keep` recording throughput |

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

CI builds and tests SBCL on `x86_64-linux` and `aarch64-darwin`, so those are
the combinations with a continuous guarantee, and they are exactly the systems
the flake declares — it never advertises a platform it does not verify. Other
implementations and platforms are expected to work, but are not gated on.

## Verifying the installation

```sh
sbcl --script run-tests.lisp
```

For this direct command, ensure both `cl-history-kit` and the test dependency
`cl-weave` are visible to ASDF first. `nix run .#test` configures that registry
automatically.

or, through Nix, which additionally builds the packaged system and runs the
coverage, formatting, and documentation checks:

```sh
nix flake check
```

Next: the [Quick Start](quick-start.md).
