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
    | `devShells.<system>.default` | SBCL with the source registry pre-set |
    | `checks.<system>.default` | The SBCL test suite |
    | `checks.<system>.formatting` | The treefmt (nixfmt) gate |
    | `apps.<system>.test` | `nix run .#test` — the suite on its own |

    To depend on it from another flake:

    ```nix
    {
      inputs.cl-history-kit = {
        url = "github:nerima-lisp/cl-history-kit";
        inputs.nixpkgs.follows = "nixpkgs";
      };
    }
    ```

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
continuous guarantee. The flake declares only that system rather than
advertising platforms it does not verify.

## Verifying the installation

```sh
sbcl --script run-tests.lisp
```

or, through Nix, which additionally runs the formatting gate:

```sh
nix flake check
```

Next: the [Quick Start](quick-start.md).
