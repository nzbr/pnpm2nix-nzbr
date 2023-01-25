{ lib
, runCommand
, remarshal
, fetchurl
, ...
}:

with lib;
let
  fixVersion = ver: head (splitString "_" ver);
  splitName = name: tail (splitString "/" name);
  getVersion = name: fixVersion (last (splitName name));
  withoutVersion = name: concatStringsSep "/" (init (splitName name));
in
rec {

  parseLockfile = lockfile: builtins.fromJSON (readFile (runCommand "toJSON" { } "${remarshal}/bin/yaml2json ${lockfile} $out"));

  dependencyTarballs = { registry, lockfile }:
    unique (
      mapAttrsToList
        (n: v:
          let
            name = withoutVersion n;
            baseName = last (init (splitName n));
            version = getVersion n;
          in
          fetchurl {
            url = "${registry}/${name}/-/${baseName}-${version}.tgz";
            sha512 = v.resolution.integrity;
          }
        )
        (parseLockfile lockfile).packages
    );

}
