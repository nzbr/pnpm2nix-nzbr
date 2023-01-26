{ lib
, stdenv
, nodejs
, callPackage
, ...
}:

with builtins; with lib; with callPackage ./lockfile.nix { };
let
  nodePkg = nodejs;
in
{
  mkPnpmPackage =
    { src
    , packageJSON ? src + "/package.json"
    , pnpmLockYaml ? src + "/pnpm-lock.yaml"
    , pname ? (fromJSON (readFile packageJSON)).name
    , version ? (fromJSON (readFile packageJSON)).version
    , name ? "${pname}-${version}"
    , nodejs ? nodePkg
    , pnpm ? nodejs.pkgs.pnpm
    , registry ? "https://registry.npmjs.org"
    , script ? "build"
    , distDir ? "dist"
    , extraBuildInputs ? []
    }@attrs: stdenv.mkDerivation ({
      inherit src name;

      nativeBuildInputs = [ nodejs pnpm ] ++ extraBuildInputs;

      configurePhase = ''
        pnpm store add ${concatStringsSep " " (dependencyTarballs { inherit registry; lockfile = pnpmLockYaml; })}
        pnpm install --frozen-lockfile --offline
      '';

      buildPhase = ''
        pnpm run ${script}
      '';

      installPhase = ''
        mv ${distDir} $out
      '';

    } // attrs);
}
