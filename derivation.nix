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
    , version ? (fromJSON (readFile packageJSON)).version or null
    , name ? if version != null then "${pname}-${version}" else pname
    , nodejs ? nodePkg
    , pnpm ? nodejs.pkgs.pnpm
    , registry ? "https://registry.npmjs.org"
    , script ? "build"
    , distDir ? "dist"
    , copyPnpmStore ? true
    , copyNodeModules ? false
    , extraNodeModuleSources ? [ ]
    , extraBuildInputs ? [ ]
    , ...
    }@attrs:
    stdenv.mkDerivation (
      recursiveUpdate
        (rec {
          inherit src name;

          nativeBuildInputs = [ nodejs pnpm ] ++ extraBuildInputs;

          configurePhase = ''
            runHook preConfigure

            ${if !copyNodeModules
              then "ln -s"
              else "cp -r"
            } ${passthru.nodeModules}/. node_modules

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

          passthru = {
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
                ${concatStringsSep "\n" (
                  map (v:
                    let
                      nv = if isAttrs v then v else { name = "."; value = v; };
                    in
                    "cp -vr ${nv.value} ${nv.name}"
                  )
                  ([
                    { name = "package.json"; value = packageJSON; }
                    { name = "pnpm-lock.yaml"; value = pnpmLockYaml; }
                  ] ++ extraNodeModuleSources)
                )}
              '';

              buildPhase = ''
                store=$(pnpm store path)
                mkdir -p $(dirname $store)

                # solve pnpm: EACCES: permission denied, copyfile '/build/.pnpm-store
                ${if !copyPnpmStore
                  then "ln -s"
                  else "cp -RL"
                } ${passthru.pnpmStore} $(pnpm store path)

                pnpm install --frozen-lockfile --offline
              '';

              installPhase = ''
                cp -r node_modules/. $out
              '';
            };
          };

        })
        (attrs // { extraNodeModuleSources = null; })
    );
}
