{ lib
, runCommand
, remarshal
, fetchurl
, ...
}:

with lib;
let
  splitVersion = name: splitString "@" (head (splitString "(" name));
  getVersion = name: last (splitVersion name);
  withoutVersion = name: concatStringsSep "@" (init (splitVersion name));
  gitTarball = n: v:
    let
      repo =
        if ((v.resolution.type or "") == "git")
        then
          fetchGit
            {
              url = v.resolution.repo;
              rev = v.resolution.commit;
              shallow = true;
            }
        else
          let
            split = splitString "/" n;
          in
          fetchGit {
            url = "https://${concatStringsSep "/" (init split)}.git";
            rev = (last split);
            shallow = true;
          };
    in
    # runCommand (last (init (traceValSeq (splitString "/" (traceValSeq (withoutVersion (traceValSeq n))))))) { } ''
    runCommand "${last (init (splitString "/" (head (splitString "(" n))))}.tgz" { } ''
      tar -czf $out -C ${repo} .
    '';
in
rec {

  parseLockfile = lockfile: builtins.fromJSON (readFile (runCommand "toJSON" { } "${remarshal}/bin/yaml2json ${lockfile} $out"));

  dependencyTarballs = { registry, lockfile }:
    unique (
      mapAttrsToList
        (n: v:
          if hasPrefix "/" n then
            let
              name = withoutVersion n;
              baseName = last (splitString "/" (withoutVersion n));
              version = getVersion n;
            in
            fetchurl (
              {
                url = v.resolution.tarball or "${registry}/${name}/-/${baseName}-${version}.tgz";
              } // (
                if hasPrefix "sha1-" v.resolution.integrity then
                  { sha1 = v.resolution.integrity; }
                else
                  { sha512 = v.resolution.integrity; }
              )
            )
          else
            gitTarball n v
        )
        (parseLockfile lockfile).packages
    );

  patchLockfile = lockfile:
    let
      orig = parseLockfile lockfile;
    in
    orig // {
      packages = mapAttrs
        (n: v:
          if hasPrefix "/" n
          then v
          else v // {
            resolution.tarball = "file:${gitTarball n v}";
          }
        )
        orig.packages;

    };

}
