
{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    git-ignore-nix.url = "github:hercules-ci/gitignore.nix/master";
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, flake-utils, nixpkgs, unstable, git-ignore-nix }: let
    hpath = { prefix ? null, compiler ? null }:
      (if prefix == null then [] else [ prefix ]) ++
      (if compiler == null
       then [ "haskellPackages" ]
       else [ "haskell" "packages" compiler ]);

    fromHOL = hol: comp: final: prev: with prev.lib; with attrsets;
      let
        path   = hpath comp;
        root   = head path;
        branch = tail path;
        hpkgs' = (getAttrFromPath path prev).override (old: {
          overrides = composeExtensions (old.overrides or (_: _: {}))
            (hol final prev);
        });
      in {
        ${root} = recursiveUpdate prev.${root} (setAttrByPath branch hpkgs');
      };

    hoverlay = final: prev: hself: hsuper:
      with prev.haskell.lib.compose; {
        xmonad = hself.callCabal2nix "xmonad"
          (git-ignore-nix.lib.gitignoreSource ./.) { };
        xmobar = hself.callCabal2nix "xmobar"
          (git-ignore-nix.lib.gitignoreSource ./.) { };
      };

    overlay = fromHOL hoverlay {};

    nixosModule = { config, pkgs, lib, ... }: with lib; with attrsets;
      let
        cfg = config.services.xserver.windowManager.xmonad.flake;
        comp = { inherit (cfg) prefix compiler; };
      in {
        options = {
          services.xserver.windowManager.xmonad.flake = with types; {
            enable = mkEnableOption "flake";
            prefix = mkOption {
              default = null;
              type = nullOr str;
              example = literalExpression "\"unstable\"";
              description = ''
                Specify a nested alternative <literal>pkgs</literal> by attrName.
              '';
            };
            compiler = mkOption {
              default = null;
              type = nullOr str;
              example = literalExpression "\"ghc922\"";
              description = ''
                Which compiler to build xmonad with.
                Must be an attribute of <literal>pkgs.haskell.packages</literal>.
                Sets <option>xmonad.haskellPackages</option> to match.
              '';
            };
          };
        };
        config = mkIf cfg.enable {
          nixpkgs.overlays = [ (fromHOL hoverlay comp) ];
          services.xserver.windowManager.xmonad.haskellPackages =
            getAttrFromPath (hpath comp) pkgs;
        };
      };

  in flake-utils.lib.eachDefaultSystem (system:
  let pkgs = import nixpkgs { inherit system overlays; };
      hpkg = pkgs.lib.attrsets.getAttrFromPath (hpath {}) pkgs;
      modifyDevShell =
        if builtins.pathExists ./develop.nix
        then import ./develop.nix
        else _: x: x;
  in
  rec {
    devShell = hpkg.shellFor (modifyDevShell pkgs {
      packages = p: [ p.xmonad p.xmobar ];
    });
    defaultPackage = hpkg.xmonad;
  }) // {
    inherit overlay;
  };
}
