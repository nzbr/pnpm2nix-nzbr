{ mkPnpmPackage, vips, ... }:

mkPnpmPackage {
  src = ./.;

  # needed by sharp
  extraBuildInputs = [ vips ];
  installInPlace = true;
}
