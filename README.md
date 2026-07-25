# cl-history-kit

[![CI](https://github.com/nerima-lisp/cl-history-kit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-history-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-history-kit/)

`cl-history-kit` is a dependency-free command-history library for SBCL: a
capacity-bounded store of recorded input lines, four search modes with
smartcase, and the prefix-filtered recall cursor that an Up/Down key pair
drives. It exists for the two details a hand-rolled list-with-a-cursor keeps
losing — the filter stays frozen for the whole walk, even once the buffer shows
a recalled command that no longer resembles the original prefix, and walking
forward past the newest match hands back exactly what you had typed rather than
an empty buffer.

Full documentation is published at <https://nerima-lisp.github.io/cl-history-kit/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```lisp
(asdf:load-system "cl-history-kit")

(defparameter *history* (history-kit:make-history :capacity 1000))
(history-kit:history-add *history* "git status" :exit-code 0)
(history-kit:history-add *history* "ls -la" :exit-code 0)
(history-kit:history-add *history* "git commit -m wip" :exit-code 1)

;; Up: the typed text becomes the filter for the whole walk.
(history-kit:history-previous *history* "git ")  ; => "git commit -m wip"
(history-kit:history-previous *history* "git ")  ; => "git status"

;; Down walks back toward the newest match, then restores what was typed.
(history-kit:history-next *history*)             ; => "git commit -m wip"
(history-kit:history-next *history*)             ; => "git "
```

## Install

```nix
# flake.nix
inputs.cl-history-kit = {
  url = "github:nerima-lisp/cl-history-kit/v1.0.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch.

Without Nix, put the repository where ASDF can find it and evaluate
`(asdf:load-system "cl-history-kit")`. There are no runtime dependencies; only
the test system needs `cl-weave`.

## Documentation

- [Installation](https://nerima-lisp.github.io/cl-history-kit/installation/)
- [Quick Start](https://nerima-lisp.github.io/cl-history-kit/quick-start/)
- [Recall Navigation](https://nerima-lisp.github.io/cl-history-kit/navigation/)
  — the frozen filter, wraparound, and wiring the cursor to keys
- [API Reference](https://nerima-lisp.github.io/cl-history-kit/api-reference/)
- [Scope and Non-Goals](https://nerima-lisp.github.io/cl-history-kit/scope/)
  — what is deliberately left to the host, and the 1.x stability promise

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework; `sbcl --script run-tests.lisp` runs them without Nix.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
