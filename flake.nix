{
  description = "Add laziness to your favourite plugin manager!";
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    gen-luarc.url = "github:mrcjkb/nix-gen-luarc-json";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    pre-commit-hooks,
    gen-luarc,
    ...
  } @ inputs: let
    name = "fn_finder";
    perSystem = nixpkgs.lib.genAttrs nixpkgs.lib.platforms.all;
    lpkgs = lp: with lp; [fennel luafilesystem];
    mk-luarc = pkgs:
      pkgs.mk-luarc {plugins = lpkgs pkgs.luajit.pkgs;};
    mk-nvim-args = src: neovim: let
      lpath = "package.path = package.path .. ';${builtins.concatStringsSep ";" (map neovim.lua.pkgs.getLuaPath (lpkgs neovim.lua.pkgs))}";
      lcpath = "package.cpath = package.cpath .. ';${builtins.concatStringsSep ";" (map neovim.lua.pkgs.getLuaCPath (lpkgs neovim.lua.pkgs))}";
    in ''${nixpkgs.lib.getExe neovim} --headless --cmd "lua ${lpath}" --cmd "lua ${lcpath}" --cmd "luafile ${src}/test.nvim" +qall!'';
    testshook = pkgs: {
      enable = true;
      name = "run-${name}-tests";
      entry = "${pkgs.writeShellScript "run-${name}-tests" ''
        set -e
        export HOME="$(mktemp -d)"
        gitroot="$(git rev-parse --show-toplevel)"
        if [ -z "$gitroot" ]; then
          echo "Error: Unable to determine Git root."
          exit 1
        fi
        ${mk-nvim-args "$gitroot" pkgs.neovim-unwrapped}
      ''}";
    };
    pre-commit-check = pkgs: luarc:
      pre-commit-hooks.lib.${pkgs.stdenv.hostPlatform.system}.run {
        src = self;
        hooks = {
          alejandra.enable = true;
          stylua.enable = true;
          luacheck = {
            enable = true;
          };
          lua-ls = {
            enable = true;
            settings.configuration = luarc;
          };
          editorconfig-checker.enable = true;
          markdownlint = {
            enable = false;
            settings.configuration = {
              MD028 = false;
              MD060 = false;
            };
            excludes = [
              "CHANGELOG.md"
            ];
          };
          lemmy-docgen = let
            lemmyscript = pkgs.writeShellScript "lemmy-helper" ''
              gitroot="$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
              if [ -z "$gitroot" ]; then
                echo "Error: Unable to determine Git root."
                exit 1
              fi
              DOCOUT="$(realpath "$gitroot/doc/${name}.txt")"
              luamain="$(realpath "$gitroot/lua/${name}/init.lua")"
              mkdir -p "$(dirname "$DOCOUT")"
              ${pkgs.lemmy-help}/bin/lemmy-help "$luamain" > "$DOCOUT"
            '';
          in {
            enable = true;
            name = "lemmy-docgen";
            entry = "${lemmyscript}";
          };
          run-tests = testshook pkgs;
        };
      };
  in {
    overlays.default = final: prev: let
      packageOverrides = luaself: luaprev: {
        ${name} = luaself.callPackage (
          {buildLuarocksPackage}:
            buildLuarocksPackage {
              pname = name;
              version = "scm-1";
              knownRockspec = "${self}/${name}-scm-1.rockspec";
              src = self;
              checkPhase = ''
                runHook preCheck
                export HOME=$(mktemp -d)
                ${mk-nvim-args "$src" final.neovim-unwrapped}
                runHook postCheck
              '';
            }
        ) {};
      };

      lua5_1 = prev.lua5_1.override {
        inherit packageOverrides;
      };
      lua51Packages = final.lua5_1.pkgs;

      vimPlugins =
        prev.vimPlugins
        // {
          ${name} = final.neovimUtils.buildNeovimPlugin {
            pname = name;
            version = "dev";
            src = self;
          };
        };
    in {
      inherit
        lua5_1
        lua51Packages
        vimPlugins
        ;
    };

    devShells = perSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system}.appendOverlays [
          gen-luarc.overlays.default
          self.overlays.default
        ];
        luarc = mk-luarc pkgs;
      in rec {
        default = pkgs.mkShell {
          name = "${name} devShell";
          DEVSHELL = 0;
          shellHook = ''
            ${(pre-commit-check pkgs luarc).shellHook}
            ln -fs ${pkgs.luarc-to-json luarc} .luarc.json
          '';
          buildInputs =
            self.checks.${system}.pre-commit-check.enabledPackages
            ++ (with pkgs; [
              lua-language-server
            ]);
        };
        devShell = default;
      }
    );

    packages = perSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system}.appendOverlays [
          self.overlays.default
        ];
      in {
        default = self.packages.${system}."${name}-vimPlugin";
        "${name}-luaPackage" = pkgs.lua51Packages.${name};
        "${name}-vimPlugin" = pkgs.vimPlugins.${name};
      }
    );

    checks = perSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system}.appendOverlays [
          gen-luarc.overlays.default
          self.overlays.default
        ];
        nightlypkgs = pkgs.appendOverlays [inputs.neovim-nightly-overlay.overlays.default];
      in {
        pre-commit-check = pre-commit-check pkgs (mk-luarc pkgs);
        vimPlugins = pkgs.vimPlugins.${name}.overrideAttrs {doCheck = true;};
        luaPackage = pkgs.lua51Packages.${name}.overrideAttrs {doCheck = true;};
        vimPlugins-nigtly = nightlypkgs.vimPlugins.${name}.overrideAttrs {doCheck = true;};
        luaPackage-nigtly = nightlypkgs.lua51Packages.${name}.overrideAttrs {doCheck = true;};
        type-check-nightly = pre-commit-hooks.lib.${system}.run {
          src = self;
          hooks = {
            lua-ls = {
              enable = true;
              settings.configuration = mk-luarc nightlypkgs;
            };
            run-tests = testshook pkgs;
          };
        };
      }
    );
  };
}
