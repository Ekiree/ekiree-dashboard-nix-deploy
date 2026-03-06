{
  description = "Ekiree Dashboard NixOS deployment configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ekiree-dashboard = {
      url = "github:ekiree-technology/ekiree-dashboard";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, ekiree-dashboard, ... }: {
    nixosModules.ekiree-dashboard = import ./modules/ekiree-dashboard;

    nixosConfigurations = {
      whittier = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          sops-nix.nixosModules.sops
          self.nixosModules.ekiree-dashboard
          ./hosts/whittier.nix
        ];
        specialArgs = { inherit ekiree-dashboard; };
      };

      local-dev = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          sops-nix.nixosModules.sops
          self.nixosModules.ekiree-dashboard
          ./hosts/local-dev.nix
        ];
        specialArgs = { inherit ekiree-dashboard; };
      };
    };
  };
}
