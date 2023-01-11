{
  description = "qemu+nix for code evaluation";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    nur.url = "github:nix-community/NUR";
    nixpkgs-mozilla.url = "github:mozilla/nixpkgs-mozilla";
  };

  outputs = { self, flake-utils, nixpkgs, ... }@inputs: flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs {
      inherit system;
      config = import ./nixpkgs-config.nix;
      overlays = [
        inputs.nur.overlay
        inputs.nixpkgs-mozilla.overlays.rust
        (self: super: {
          path = nixpkgs; # avoids needlessly copying the nixpkgs source for the nix evaluator
          inherit (self.nur.repos.tilpner.pkgs) kernelConfig;
        })
      ];
    };
  in rec {
    legacyPackages = pkgs.callPackage self {};
    packages = legacyPackages.evaluators // rec {
      inherit (legacyPackages) all;
      default = all;
    };
  });
}
