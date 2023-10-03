import <nixpkgs> {
  config = import ./nixpkgs-config.nix;
  overlays = [
    (self: super: {
      nur = super.callPackage (import (builtins.fetchTarball {
        url = "https://github.com/nix-community/NUR/archive/master.tar.gz";
      })) {};

      inherit (self.nur.repos.tilpner.pkgs) kernelConfig;
    })

    (import "${builtins.fetchTarball {
      url = "https://github.com/mozilla/nixpkgs-mozilla/archive/master.tar.gz";
    }}/rust-overlay.nix")
  ];
}
