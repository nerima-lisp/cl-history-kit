{
  description = "Dependency-free command-history store, search, and recall navigation for Common Lisp";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      cl-weave,
      treefmt-nix,
      ...
    }:
    let
      # Every declared system is verified: ci.yml runs `nix flake check` --
      # the SBCL suite plus the formatting gate -- once per entry here, on a
      # runner of that platform. The flake never advertises a platform CI does
      # not build and test, so adding one means adding the matching CI matrix
      # entry in the same change.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      sourceRegistry = "${cl-weave}//:${self}//";

      # Single source of truth for the package version: the `:version` form in
      # cl-history-kit.asd. A release only ever edits the .asd file and every
      # Nix derivation below follows automatically, so the flake can no longer
      # disagree with the .asd the way cl-cc does (flake 0.8.0, asd 0.1.0, tag
      # v0.1.0). Nix regexes are whole-string anchored and `.` never spans
      # newlines, so the version is extracted line-by-line rather than with one
      # multi-line match. The first matching line wins, which is the main
      # system's -- the test system repeats the same version below it.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./cl-history-kit.asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate.
      # Scope is Nix only: nixfmt (RFC-style) is a zero-footgun, low-diff
      # formatter, whereas YAML formatters mangle the GitHub Actions `on:`
      # key and Markdown reformatting would churn the whole docs tree --
      # neither is "low-cost", so both are intentionally left out.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          cl-history-kit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-history-kit";
            inherit version;
            src = self;
            systems = [ "cl-history-kit" ];
          };
          default = cl-history-kit;

          # Rendered documentation site (Material for MkDocs).
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          docs = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-history-kit-docs";
            inherit version;
            src = pkgs.lib.fileset.toSource {
              root = ./docs;
              fileset = pkgs.lib.fileset.unions [
                ./docs/mkdocs.yml
                ./docs/src
              ];
            };
            nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
            buildPhase = ''
              runHook preBuild
              mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
              runHook postBuild
            '';
            dontInstall = true;
            meta = {
              description = "Rendered MkDocs (Material) documentation for cl-history-kit";
              homepage = "https://github.com/nerima-lisp/cl-history-kit";
              license = pkgs.lib.licenses.mit;
            };
          };

          # sb-cover / cl-weave branch-and-expression coverage report for
          # src/, reproducing what `coverage.lisp` does locally as a buildable
          # artifact. Not wired into `checks`: the raw expression percentage
          # cannot reach 100 for reasons documented in
          # docs/src/contributing.md's "Coverage" section (IN-PACKAGE forms,
          # DEFSTRUCT slot options, and DEFMACRO bodies are not independently
          # steppable), so gating on that number would be a false signal
          # rather than a real regression check.
          coverage = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-history-kit-coverage";
            inherit version;
            src = self;
            nativeBuildInputs = [ pkgs.sbcl ];
            CL_SOURCE_REGISTRY = sourceRegistry;
            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME" "$out"
              timeout 120 sbcl --script ${self}/coverage.lisp "$out"
              runHook postBuild
            '';
            dontInstall = true;
            meta = {
              description = "sb-cover / cl-weave coverage report for cl-history-kit's src/";
              homepage = "https://github.com/nerima-lisp/cl-history-kit";
              license = pkgs.lib.licenses.mit;
            };
          };
        }
      );

      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default =
            pkgs.runCommand "cl-history-kit-tests"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.coreutils
                ];
                CL_SOURCE_REGISTRY = sourceRegistry;
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME" "$out"
                timeout 120 sbcl --script ${self}/run-tests.lisp
                touch "$out/passed"
              '';

          # Fails `nix flake check` when any tracked file is unformatted,
          # turning the formatter into an enforced CI gate.
          formatting = treefmtEval.${system}.config.build.check self;

          # The docs package builds with `mkdocs --strict`, so a broken link or
          # a page missing from the nav fails the build. Without this the docs
          # are only ever built by the publish workflow, which runs after a
          # merge to main, meaning such a break surfaces as a failed deploy
          # rather than as a failed pull request.
          docs = self.packages.${system}.docs;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          test = pkgs.writeShellApplication {
            name = "cl-history-kit-test";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${sourceRegistry}"
              exec timeout 120 sbcl --script ${self}/run-tests.lisp
            '';
          };
          coverage = pkgs.writeShellApplication {
            name = "cl-history-kit-coverage";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${sourceRegistry}"
              out="''${1:-$(mktemp -d)}"
              timeout 120 sbcl --script ${self}/coverage.lisp "$out"
              echo "coverage report: $out/coverage/cover-index.html"
            '';
          };
        in
        # `meta.description` on each app is what `nix flake show` lists and
        # what stops `nix flake check` warning that the app lacks it.
        {
          default = {
            type = "app";
            program = "${test}/bin/cl-history-kit-test";
            meta.description = "Run the cl-history-kit test suite";
          };
          test = {
            type = "app";
            program = "${test}/bin/cl-history-kit-test";
            meta.description = "Run the cl-history-kit test suite";
          };
          coverage = {
            type = "app";
            program = "${coverage}/bin/cl-history-kit-coverage";
            meta.description = "Write the sb-cover report for cl-history-kit's src/";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.sbcl ];
            CL_SOURCE_REGISTRY = sourceRegistry;
          };
        }
      );
    };
}
