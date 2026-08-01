{
  description = "Dependency-free command-history store, search, and recall navigation for Common Lisp";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # `inputs.nixpkgs.follows` is mandatory on every input: without it each one
    # drags in its own nixpkgs, inflating flake.lock and rebuilding the same
    # derivations.

    # The org flake preset. Everything this file used to spell out by hand --
    # the `.asd` version extraction, `forAllSystems`, the treefmt eval wired to
    # both `formatter` and `checks.formatting`, the mkdocs package plus its
    # check, the run-tests.lisp gate, the `apps.test`/`apps.default` pair and
    # the devShell -- is the single `mkPackageFlake` call below, so none of it
    # can drift from the other nerima-lisp repositories.
    #
    # Pinned to a release TAG, never to a branch: a bare
    # `github:nerima-lisp/cl-nix-forge` follows that repository's default
    # branch, so an upstream push to main would change this build without
    # warning.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-weave,
      treefmt-nix,
    }:
    let
      # Only what is verified: x86_64-linux, which is what CI builds and tests.
      # aarch64-darwin was dropped on 2026-08-01 along with the macOS half of
      # the ci.yml matrix. aarch64-linux and x86_64-darwin were never declared,
      # because nothing runs them and a platform no runner can build makes
      # `nix flake check --all-systems` fail with "platform mismatch" rather
      # than skip it.
      #
      # Consequence, accepted deliberately: mkPackageFlake generates EVERY
      # per-system output from this one list -- packages, checks, apps and
      # devShells alike -- so `nix develop` and `nix build` no longer work on
      # macOS. Development happens on Linux. See PACKAGE_STANDARD.md, section
      # "systems".
      systems = [
        "x86_64-linux"
      ];

      # The sb-cover HTML report, used as BOTH `packages.coverage` and
      # `checks.coverage`. Spelled once as a function of `ctx` so the two
      # attributes are literally the same derivation rather than two calls
      # that happen to agree.
      #
      # `mkCoverageReport` owns the declaim/`:force t`/declaim dance
      # `coverage.lisp` used to hand-write: instrumentation is a COMPILE-time
      # property, so only code compiled while `store-coverage-data` is
      # proclaimed records anything, and the derivation's own buildPhase
      # already compiled cl-history-kit without it. `:force t` is therefore
      # correctness, not a performance knob -- without it ASDF finds the
      # existing fasls current and the report comes back empty.
      #
      # `entryPoint` defaults to `run-tests.lisp`, the same file
      # `checks.default` and `apps.test` already drive, so the suite that
      # generates the report is the suite everything else runs. This does NOT
      # gate on a coverage percentage: the report exists to make the number
      # visible and trending, not to block merges on a threshold nobody has
      # agreed to yet -- see docs/src/project/development.md's Coverage section for
      # why the raw expression percentage cannot reach 100.
      coverageReport =
        ctx:
        ctx.cl.mkCoverageReport {
          drv = ctx.package;
          name = "cl-history-kit-coverage";
          timeoutSeconds = 120;
          killAfterSeconds = 15;
        };

      # `nix run .#benchmark`: first prefix lookup, cached `history-previous`
      # navigation, a merge into a full bounded history, and recording into a
      # full `:keep` history. Package the script through the same dependency
      # environment `lispScript` gives any other entry point, rather than
      # benchmark.lisp re-deriving its own source registry as it did under
      # the hand-written flake.
      benchmarkApp =
        ctx:
        ctx.cl.mkApp {
          drv = ctx.cl.lispScript {
            name = "cl-history-kit-benchmark";
            src = ./benchmark.lisp;
            dependencies = [ ctx.package ];
          };
          description = "Benchmark history lookup, navigation, bounded merges, and :KEEP recording";
        };
    in
    # `mkPackageFlake` spans systems -- it obtains a `pkgs` and its own
    # cl-nix-forge instance per entry in `systems` -- so the per-system `lib`
    # this function is taken from contributes nothing but the function itself.
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;

      pname = "cl-history-kit";

      # Single source of truth for the package version: the `:version` form in
      # cl-history-kit.asd. A release only ever edits the .asd file and every
      # derivation carrying a version -- the package, the docs site, and both
      # store paths -- follows automatically. There is deliberately no
      # `version` argument to pass.
      asd = ./cl-history-kit.asd;

      # Spelled out rather than left to `mkPackageFlake`'s documented default
      # of `self`, because that default does not evaluate: a flake's `self` is
      # an attrset with an `outPath`, and `lib.fileset` refuses string-like
      # values. `./.` is the same directory as a path literal. `self` is still
      # what the preset hands the treefmt gate, which wants the UNFILTERED
      # tree and takes a store path happily.
      root = ./.;

      meta = {
        description = "Dependency-free command-history store, search, and recall navigation for Common Lisp";
        homepage = "https://github.com/nerima-lisp/cl-history-kit";
        license = nixpkgs.lib.licenses.mit;
        platforms = nixpkgs.lib.platforms.unix;
      };

      # cl-weave is a dependency of `cl-history-kit/test` and of nothing else
      # (see cl-history-kit.asd), so it is a CHECK dependency: it must not
      # enter the library's closure or the overlay's `pkgs.cl-history-kit`.
      # These are BUILT DERIVATIONS, never CL_SOURCE_REGISTRY strings --
      # assembling that registry is cl-nix-forge's job and it does it
      # transitively, which is what replaces the hand-rolled
      # `"${cl-weave}//:${self}//"` this file used to thread through the
      # check, the app and the devShell separately.
      #
      # `packages.*.cl-weave` is cl-weave's ASDF SYSTEM, built by cl-weave's
      # own flake -- a different output from its `packages.*.default`, which
      # is the delivered CLI. Taking the system means this repository never
      # compiles cl-weave itself.
      lispCheckDependencies = ctx: [ cl-weave.packages.${ctx.system}.cl-weave ];

      # Drives BOTH `checks.default` and `apps.test`, from this one number, so
      # the command a contributor runs by hand and the gate CI runs cannot
      # drift apart. `killAfterSeconds` sends SIGKILL 15s after the SIGTERM
      # deadline, so a hanging test fails with a clear timeout status instead
      # of outliving the deadline and running to the platform default.
      timeoutSeconds = 120;
      killAfterSeconds = 15;

      # docs/mkdocs.yml + docs/src/, built with `--strict` so a broken link or
      # a page missing from the nav is a build failure. `checks.docs` comes
      # with it, and is the point: without that gate the docs are only ever
      # built by the publish workflow, which runs after a merge to main --
      # meaning such a break surfaces as a failed deploy rather than as a
      # failed pull request. Material for MkDocs bundles all of its assets,
      # so the build needs no network access inside the Nix sandbox.
      docs.root = ./docs;

      # ONE treefmt evaluation drives `nix fmt` and the `checks.formatting`
      # gate, so the formatter and CI can never disagree about what
      # "formatted" means. `evalModule` is passed in rather than closed over
      # so this repository picks its own treefmt-nix version. Scope stays Nix
      # only: nixfmt (RFC-style) is a zero-footgun, low-diff formatter,
      # whereas a YAML formatter mangles the GitHub Actions `on:` key and
      # Markdown reformatting would churn the whole docs tree for no
      # reviewable gain.
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching.
      extraOutputs = ctx: {
        packages.coverage = coverageReport ctx;
        checks.coverage = coverageReport ctx;

        apps.benchmark = benchmarkApp ctx;
      };
    };
}
