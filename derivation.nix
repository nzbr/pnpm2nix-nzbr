{ lib
, stdenv
, nodejs
, rsync
, pkg-config
, callPackage
, writeText
, runCommand
, ...
}:

with builtins; with lib; with callPackage ./lockfile.nix { };
let
  nodePkg = nodejs;
  pkgConfigPkg = pkg-config;
in
{
  mkPnpmPackage =
    { workspace ? null
    , components ? []
    , src ? if (workspace != null && components != []) then workspace else null
    , packageJSON ? src + "/package.json"
    , componentPackageJSONs ? map (c: {
        name = "${c}/package.json";
        value = src + "/${c}/package.json";
      }) components
    , pnpmLockYaml ? src + "/pnpm-lock.yaml"
    , pnpmWorkspaceYaml ? (if workspace == null then null else workspace + "/pnpm-workspace.yaml")
    , pname ? (fromJSON (readFile packageJSON)).name
    , version ? (fromJSON (readFile packageJSON)).version or null
    , name ? if version != null then "${pname}-${version}" else pname
    , registry ? "https://registry.npmjs.org"
    , script ? "build"
    , distDir ? "dist"
    , distDirs ? (if workspace == null then [distDir] else (map (c: "${c}/dist") components))
    , installInPlace ? false
    , installEnv ? { }
    , buildEnv ? { }
    , noDevDependencies ? false
    , extraNodeModuleSources ? [ ]
    , copyPnpmStore ? true
    , copyNodeModules ? false
    , extraBuildInputs ? [ ]
    , nodejs ? nodePkg
    , pnpm ? nodejs.pkgs.pnpm
    , pkg-config ? pkgConfigPkg
    , ...
    }@attrs:
    let
      # Flag that can be computed from arguments, indicating a workspace was
      # supplied. Only used in these let bindings.
      isWorkspace = workspace != null && components != [];
      # Utility functions
      forEachConcat = f: xs: concatStringsSep "\n" (map f xs);
      forEachComponent = f: forEachConcat f components;
      # Computed values used below that don't loop
      nativeBuildInputs = [
        nodejs
        pnpm
        pkg-config
      ] ++ extraBuildInputs ++ (optional copyNodeModules rsync);
      copyLink =
        if copyNodeModules
          then "rsync -a --chmod=u+w"
          else "ln -s";
      rsyncSlash = optionalString copyNodeModules "/";
      packageFilesWithoutLockfile =
        [
          { name = "package.json"; value = packageJSON; }
        ] ++ componentPackageJSONs ++ computedNodeModuleSources;
      computedNodeModuleSources =
        (if pnpmWorkspaceYaml == null
          then []
          else [
            {name = "pnpm-workspace.yaml"; value = pnpmWorkspaceYaml;}
          ]
        ) ++ extraNodeModuleSources;
      # Computed values that loop over something
      nodeModulesDirs =
        if isWorkspace then
          ["node_modules"] ++ (map (c: "${c}/node_modules") components)
        else ["node_modules"];
      filterString = concatStringsSep " " (
        ["--recursive" "--stream"] ++
        map (c: "--filter ./${c}") components
      ) + " ";
      buildScripts = ''
        pnpm run ${optionalString isWorkspace filterString}${script}
      '';
      # Flag derived from value computed above, indicating the single dist
      # should be copied as $out directly, rather than $out/${distDir}
      computedDistDirIsOut =
        length distDirs == 1 && !isWorkspace;
    in
    stdenv.mkDerivation (
      recursiveUpdate
        (rec {
          inherit src name nativeBuildInputs;

          postUnpack = ''
            ${optionalString (pnpmWorkspaceYaml != null) ''
              cp ${pnpmWorkspaceYaml} pnpm-workspace.yaml
            ''}
            ${forEachComponent (component:
              ''mkdir -p "${component}"'')
            }
          '';

          configurePhase = ''
            export HOME=$NIX_BUILD_TOP # Some packages need a writable HOME
            export npm_config_nodedir=${nodejs}

            runHook preConfigure

            ${if installInPlace
              then passthru.nodeModules.buildPhase
              else
                forEachConcat (
                  nodeModulesDir: ''
                    ${copyLink} ${passthru.nodeModules}/${nodeModulesDir}${rsyncSlash} ${nodeModulesDir}
                  '') nodeModulesDirs
            }

            runHook postConfigure
          '';

          buildPhase = ''
            ${concatStringsSep "\n" (
              mapAttrsToList
                (n: v: ''export ${n}="${v}"'')
                buildEnv
            )}

            runHook preBuild

            ${buildScripts}

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            ${if computedDistDirIsOut then ''
                ${if distDir == "." then "cp -r" else "mv"} ${distDir} $out
              ''
              else ''
                mkdir -p $out
                ${forEachConcat (dDir: ''
                    cp -r --parents ${dDir} $out
                  '') distDirs
                }
              ''
            }

            runHook postInstall
          '';

          passthru =
            let
              processResult = processLockfile { inherit registry noDevDependencies; lockfile = pnpmLockYaml; };
            in
            {
              inherit attrs;

              patchedLockfile = processResult.patchedLockfile;
              patchedLockfileYaml = writeText "pnpm-lock.yaml" (toJSON passthru.patchedLockfile);

              pnpmStore = runCommand "${name}-pnpm-store"
                {
                  nativeBuildInputs = [ nodejs pnpm ];
                } ''
                mkdir -p $out

                store=$(pnpm store path)
                mkdir -p $(dirname $store)
                ln -s $out $(pnpm store path)

                pnpm store add ${concatStringsSep " " (unique processResult.dependencyTarballs)}
              '';

              nodeModules = stdenv.mkDerivation {
                name = "${name}-node-modules";

                inherit nativeBuildInputs;

                unpackPhase = concatStringsSep "\n"
                  ( [ # components is an empty list for non workspace builds
                      (forEachComponent (component: ''
                      mkdir -p "${component}"
                    '')) ] ++
                    map
                      (v:
                        let
                          nv = if isAttrs v then v else { name = "."; value = v; };
                        in
                        "cp -vr \"${nv.value}\" \"${nv.name}\""
                      )
                      ([{ name = "pnpm-lock.yaml"; value = passthru.patchedLockfileYaml; }]
                      ++ packageFilesWithoutLockfile)
                  );

                buildPhase = ''
                  export HOME=$NIX_BUILD_TOP # Some packages need a writable HOME

                  store=$(pnpm store path)
                  mkdir -p $(dirname $store)

                  cp -f ${passthru.patchedLockfileYaml} pnpm-lock.yaml

                  # solve pnpm: EACCES: permission denied, copyfile '/build/.pnpm-store
                  ${if !copyPnpmStore
                    then "ln -s"
                    else "cp -RL"
                  } ${passthru.pnpmStore} $(pnpm store path)

                  ${optionalString copyPnpmStore "chmod -R +w $(pnpm store path)"}

                  ${concatStringsSep "\n" (
                    mapAttrsToList
                      (n: v: ''export ${n}="${v}"'')
                      installEnv
                  )}

                  pnpm install --stream ${optionalString noDevDependencies "--prod "}--frozen-lockfile --offline
                '';

                installPhase = ''
                  mkdir -p $out
                  cp -r node_modules/. $out/node_modules
                  ${forEachComponent (component: ''
                    mkdir -p $out/"${component}"
                    cp -r "${component}/node_modules" $out/"${component}/node_modules"
                  '')}
                '';
              };
            };

        })
        (attrs // { extraNodeModuleSources = null; installEnv = null; buildEnv = null;})
    );
}
