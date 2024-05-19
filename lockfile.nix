{ lib
, runCommand
, remarshal
, fetchurl
, ...
}:

with lib;
rec {

  parseLockfile = lockfile: builtins.fromJSON (readFile (runCommand "toJSON" { } "${remarshal}/bin/yaml2json ${lockfile} $out"));

  processLockfile = { registry, lockfile, noDevDependencies }:
    let
      splitVersion = name: splitString "@" (head (splitString "(" name));
      getVersion = name: last (splitVersion name);
      withoutVersion = name: concatStringsSep "@" (init (splitVersion name));
      mkTarball = pkg: contents:
        runCommand "${last (init (splitString "/" (head (splitString "(" pkg))))}.tgz" { } ''
          tar -czf $out -C ${contents} .
        '';
      findTarball = n: v:
        if (v.resolution.type or "") == "git" then
          mkTarball n
            (
              fetchGit {
                url = v.resolution.repo;
                rev = v.resolution.commit;
                shallow = true;
              }
            )
        else if hasAttrByPath [ "resolution" "tarball" ] v && hasAttrByPath [ "resolution" "integrity" ] v then
          fetchurl
            {
              url = v.resolution.tarball;
              ${head (splitString "-" v.resolution.integrity)} = v.resolution.integrity;
            }
        else if hasPrefix "https://codeload.github.com" (v.resolution.tarball or "") then
          let
            m = strings.match "https://codeload.github.com/([^/]+)/([^/]+)/tar\\.gz/([a-f0-9]+)" v.resolution.tarball;
          in
          mkTarball n (
            fetchGit {
              url = "https://github.com/${elemAt m 0}/${elemAt m 1}";
              rev = (elemAt m 2);
              shallow = true;
            }
          )
        else if (v ? id) then
          let
            split = splitString "/" v.id;
          in
          mkTarball n (
            fetchGit {
              url = "https://${concatStringsSep "/" (init split)}.git";
              rev = (last split);
              shallow = true;
            }
          )
        else if hasPrefix "/" n then
          let
            name = withoutVersion n;
            baseName = last (splitString "/" (withoutVersion n));
            version = getVersion n;
          in
          fetchurl {
            url = "${registry}/${name}/-/${baseName}-${version}.tgz";
            ${head (splitString "-" v.resolution.integrity)} = v.resolution.integrity;
          }
        else
          throw "no match found for ${n}";
    in
    {
      dependencyTarballs =
        unique (
          mapAttrsToList
            findTarball
            (filterAttrs
              (n: v: !noDevDependencies || !(v.dev or false))
              (parseLockfile lockfile).packages
            )
        );

      patchedLockfile =
        let
          orig = parseLockfile lockfile;
        in
        orig // {
          packages = mapAttrs
            (n: v:
              v // (
                if noDevDependencies && (v.dev or false)
                then { resolution = { }; }
                else {
                  resolution.tarball = "file:${findTarball n v}";
                }
              )
            )
            orig.packages;

        };
    };

}
