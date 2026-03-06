{ pkgs, ekiree-dashboard, ... }:
{
  services.ekiree-dashboard = {
    enable = true;
    deploymentProfile = "production";

    domain = "wsp.ekiree.tech";
    acmeEmail = "noah@ekiree.tech";

    package = ekiree-dashboard.packages.${pkgs.system}.default;
    workers = 3;
    bindAddress = "127.0.0.1";
    port = 8000;

    database = {
      createLocally = true;
      host = "";
      name = "poetfolio_prod";
      user = "poetfolio";
    };

    email.enable = true;
    s3.enable = true;

    backup = {
      enable = true;
      schedule = "daily";
      localDir = "/var/backups/ekiree-dashboard";
      s3.enable = true;
    };

    # Local untracked file created from secrets/whittier.yaml.example
    secretsFile = ../secrets/whittier.yaml;
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
