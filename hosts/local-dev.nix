{ pkgs, ekiree-dashboard, ... }:
{
  services.ekiree-dashboard = {
    enable = true;
    deploymentProfile = "development";

    package = ekiree-dashboard.packages.${pkgs.system}.default;

    domain = "localhost";
    bindAddress = "127.0.0.1";
    port = 8000;
    workers = 2;

    database = {
      createLocally = true;
      host = "";
      name = "poetfolio_dev";
      user = "poetfolio";
    };

    dev = {
      enableNginx = false;
      envFile = null;
    };

    email.enable = false;
    s3.enable = false;
    backup.enable = false;
  };
}
