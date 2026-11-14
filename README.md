# cl-history-kit

[![CI](https://github.com/nerima-lisp/cl-history-kit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-history-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-history-kit/)

`cl-history-kit` is a dependency-free command-history library for SBCL: a
capacity-bounded store of recorded input lines with optional per-entry
metadata, prefix, substring, per-line, and fuzzy search with smartcase, and a
prefix-filtered recall cursor for Up/Down key handling. The
cursor keeps its filter for the whole walk and restores the original input when
walking forward past the newest match.

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

### Metadata and fuzzy search

```lisp
;; Optional context recorded with each entry; every key defaults to NIL.
(history-kit:history-add *history* "make test"
                         :exit-code 0 :cwd "/src/app"
                         :duration-ms 5120 :origin :typed :session "tty1")

;; Autosuggest from the current directory first.
(history-kit:history-search *history* "make" :mode :line-prefix :limit 1
                            :filter (lambda (entry)
                                      (equal (history-kit:history-entry-cwd entry)
                                             "/src/app")))

;; Ctrl-R: subsequence matches ranked by score, best first.
(history-kit:history-fuzzy-search *history* "gcm" :limit 10)

;; Walk entries newest first without consing a snapshot list.
(history-kit:map-history (lambda (entry) (print (history-kit:history-entry-text entry)))
                         *history* :limit 3)
```

## Install

```nix
# flake.nix
inputs.cl-history-kit = {
  url = "github:nerima-lisp/cl-history-kit/v1.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch.

Without Nix, put the repository where ASDF can find it and evaluate
`(asdf:load-system "cl-history-kit")`. There are no runtime dependencies; only
the test system needs `cl-weave`.

## Documentation

- [Getting Started](https://nerima-lisp.github.io/cl-history-kit/getting-started/)
- [Search](https://nerima-lisp.github.io/cl-history-kit/guide/search/)
- [Recall Navigation](https://nerima-lisp.github.io/cl-history-kit/guide/navigation/)
  — the frozen filter, wraparound, and wiring the cursor to keys
- [API Reference](https://nerima-lisp.github.io/cl-history-kit/reference/api/)
- [Scope and Non-Goals](https://nerima-lisp.github.io/cl-history-kit/project/scope/)
  — what is deliberately left to the host, and the 1.x stability promise

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix run .#test       # run the test suite
nix run .#benchmark  # measure lookup, navigation, merge, and recording; then a 100k-entry history
nix flake check      # packaged system + tests + coverage + formatting + docs
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework. Before running `sbcl --script run-tests.lisp` without
Nix, make both `cl-history-kit` and `cl-weave` visible to ASDF.

`nix run .#benchmark` reports first prefix lookup, cached `history-previous`
navigation, a merge into a full bounded history, and recording into a full
`:keep` history. The usual `:remove` policy uses an internal text index, so a
new command does not scan retained entries; re-recording an existing command
does compact the ring in place. A second section builds a 100,000-entry
history and reports throughput and bytes consed per operation for a
`history-entries` snapshot, a full scan over it, autosuggest prefix lookups,
and `:contains` scans. Treat the output as a same-machine regression signal,
not a cross-machine ranking.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
