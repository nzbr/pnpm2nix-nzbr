{ lib
, stdenv
, nodejs
, callPackage
, runCommand
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
    , copyNodeModules ? false
    , copyPnpmStore ? true
    , extraBuildInputs ? [ ]
    , ...
    }@attrs:
    let
      pnpmStore = runCommand "${name}-pnpm-store"
        {
          nativeBuildInputs = [ nodejs pnpm ];
        } ''
        mkdir -p $out

        store=$(pnpm store path)
        mkdir -p $(dirname $store)
        ln -s $out $(pnpm store path)

        pnpm store add ${concatStringsSep " " (dependencyTarballs { inherit registry; lockfile = pnpmLockYaml; })}
      '';

      nodeModules = stdenv.mkDerivation {
        name = "${name}-node-modules";
        nativeBuildInputs = [ nodejs pnpm ];

        unpackPhase = ''
          cp ${packageJSON} package.json
          cp ${pnpmLockYaml} pnpm-lock.yaml
        '';

        buildPhase = ''
          store=$(pnpm store path)
          mkdir -p $(dirname $store)
          # solve pnpm: EACCES: permission denied, copyfile '/build/.pnpm-store

          ${if !copyPnpmStore
          then "ln -s"
          else "cp -RL"
           } ${pnpmStore} $(pnpm store path)

          pnpm install --frozen-lockfile --offline
        '';

        installPhase = ''
          cp -r node_modules/. $out
        '';
      };
    in
    stdenv.mkDerivation ({
      inherit src name;

      nativeBuildInputs = [ nodejs pnpm ] ++ extraBuildInputs;

      configurePhase = ''
        runHook preConfigure

        ${if !copyNodeModules
          then "ln -s"
          else "cp -r"
        } ${nodeModules}/. node_modules

        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild

        pnpm run ${script}

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mv ${distDir} $out

        runHook postInstall
      '';

    } // attrs);
}
