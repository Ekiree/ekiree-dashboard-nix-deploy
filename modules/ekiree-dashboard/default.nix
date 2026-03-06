{ config, lib, pkgs, ekiree-dashboard, ... }:
let
  cfg = config.services.ekiree-dashboard;
  isProd = cfg.deploymentProfile == "production";
  appUser = "ekiree-dashboard";
  appGroup = "ekiree-dashboard";
  serviceName = "ekiree-dashboard";
  migrateServiceName = "${serviceName}-migrate";
  dbInitServiceName = "${serviceName}-db-init";
  backupServiceName = "${serviceName}-backup";
  backupTimerName = "${backupServiceName}-timer";

  usesSopsSecrets = cfg.secretsFile != null;
  nginxEnabled = isProd || cfg.dev.enableNginx;

  appSecretNames = [
    "POETFOLIO_SECRET_KEY"
    "POETFOLIO_ALLOWED_HOSTS"
    "POETFOLIO_CSRF_TRUSTED_ORIGINS"
    "POETFOLIO_PRODUCTION"
    "POETFOLIO_DB_HOST"
    "POETFOLIO_DB_NAME"
    "POETFOLIO_DB_USER"
    "POETFOLIO_DB_PASSWORD"
    "POETFOLIO_EMAIL_HOST"
    "POETFOLIO_EMAIL_USER"
    "POETFOLIO_EMAIL_PASSWORD"
    "USE_S3"
    "S3_BUCKET_NAME"
    "S3_BUCKET_ENDPOINT"
    "S3_ACCESS_KEY"
    "S3_SECRET_KEY"
    "BACKUP_BUCKET_NAME"
    "BACKUP_BUCKET_ENDPOINT"
    "BACKUP_ACCESS_KEY"
    "BACKUP_SECRET_KEY"
  ];

  mkAppSecret = name: {
    owner = appUser;
    group = appGroup;
    mode = "0400";
    sopsFile = cfg.secretsFile;
    restartUnits = [ serviceName migrateServiceName backupServiceName dbInitServiceName ];
  };

  getSecretOrEnv = name: fallback: ''
    if [ -f "/run/secrets/${name}" ]; then
      cat "/run/secrets/${name}"
    elif [ -n "''${${name}:-}" ]; then
      printf "%s" "''${${name}}"
    else
      printf "%s" "${fallback}"
    fi
  '';
in
{
  options.services.ekiree-dashboard = {
    enable = lib.mkEnableOption "Ekiree dashboard service";

    deploymentProfile = lib.mkOption {
      type = lib.types.enum [ "production" "development" ];
      default = "production";
      description = "Choose production or local development behavior.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Public domain for nginx virtual host.";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email used for ACME in production.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = ekiree-dashboard.packages.${pkgs.system}.default;
      defaultText = lib.literalExpression "ekiree-dashboard.packages.${pkgs.system}.default";
      description = "Packaged Python environment containing gunicorn and the Django app.";
    };

    workers = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Gunicorn worker count.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Gunicorn bind address.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Gunicorn bind port.";
    };

    secretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "sops file containing secret keys used by the service.";
    };

    database = {
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create and host MariaDB on this machine.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "DB host (empty string means Unix socket).";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "poetfolio_dev";
        description = "Database name.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "poetfolio";
        description = "Database user.";
      };
    };

    email.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SMTP secrets/env wiring.";
    };

    s3.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable S3 media secrets/env wiring.";
    };

    backup = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable periodic MariaDB backups.";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd OnCalendar expression.";
      };

      localDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/backups/ekiree-dashboard";
        description = "Local backup destination path.";
      };

      s3.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Upload backups to S3-compatible storage.";
      };
    };

    dev = {
      enableNginx = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable nginx in development profile.";
      };

      envFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional environment file for local development (EnvironmentFile format).";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = !isProd || cfg.acmeEmail != null;
          message = "services.ekiree-dashboard.acmeEmail must be set for production profile.";
        }
        {
          assertion = !isProd || cfg.domain != "localhost";
          message = "services.ekiree-dashboard.domain must be a real DNS host in production.";
        }
        {
          assertion = !usesSopsSecrets || config ? sops;
          message = "sops-nix module must be imported when secretsFile is set.";
        }
      ];

      users.groups.${appGroup} = {};
      users.users.${appUser} = {
        isSystemUser = true;
        group = appGroup;
        home = "/var/lib/${appUser}";
        createHome = true;
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/${appUser} 0750 ${appUser} ${appGroup} -"
        "d /var/lib/${appUser}/media 0750 ${appUser} ${appGroup} -"
        "d /var/lib/${appUser}/static 0750 ${appUser} ${appGroup} -"
      ];
    }

    (lib.mkIf usesSopsSecrets {
      sops.defaultSopsFile = cfg.secretsFile;
      sops.secrets = lib.genAttrs appSecretNames mkAppSecret;
    })

    (lib.mkIf cfg.database.createLocally {
      services.mysql.enable = true;
      services.mysql.package = pkgs.mariadb;

      systemd.services.${dbInitServiceName} = {
        description = "Initialize local MariaDB database and account for ${serviceName}";
        after = [ "mysql.service" ];
        requires = [ "mysql.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          RemainAfterExit = true;
        };
        environment = {
          POETFOLIO_DB_NAME = cfg.database.name;
          POETFOLIO_DB_USER = cfg.database.user;
          POETFOLIO_DB_HOST = cfg.database.host;
        };
        script = ''
          set -eu
          DB_NAME="$(${getSecretOrEnv "POETFOLIO_DB_NAME" cfg.database.name})"
          DB_USER="$(${getSecretOrEnv "POETFOLIO_DB_USER" cfg.database.user})"
          DB_PASSWORD="$(${getSecretOrEnv "POETFOLIO_DB_PASSWORD" ""})"

          SQL=$(cat <<EOF
          CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
          CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
          GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
          FLUSH PRIVILEGES;
          EOF
          )

          ${pkgs.mariadb}/bin/mysql -u root <<EOF
          $SQL
          EOF
        '';
      };
    })

    {
      systemd.services.${migrateServiceName} = {
        description = "Run Django migrations for ${serviceName}";
        after = [ "network-online.target" ] ++ lib.optional cfg.database.createLocally "mysql.service";
        requires = lib.optional cfg.database.createLocally "mysql.service";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = appUser;
          Group = appGroup;
          UMask = "0077";
          PrivateTmp = true;
          NoNewPrivileges = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/var/lib/${appUser}" "/tmp" ];
        };
        environment = {
          DOCKER_SECRETS = if usesSopsSecrets then "True" else "False";
          POETFOLIO_PRODUCTION = if isProd then "True" else "False";
          POETFOLIO_DB_NAME = cfg.database.name;
          POETFOLIO_DB_USER = cfg.database.user;
          POETFOLIO_DB_HOST = cfg.database.host;
          POETFOLIO_MEDIA = "/var/lib/${appUser}/media";
          POETFOLIO_STATIC = "/var/lib/${appUser}/static";
          USE_S3 = if cfg.s3.enable then "TRUE" else "FALSE";
        };
        path = [ pkgs.findutils pkgs.coreutils pkgs.bash pkgs.mariadb ];
        script = ''
          set -eu

          DB_HOST="$(${getSecretOrEnv "POETFOLIO_DB_HOST" cfg.database.host})"
          DB_USER="$(${getSecretOrEnv "POETFOLIO_DB_USER" cfg.database.user})"
          DB_PASSWORD="$(${getSecretOrEnv "POETFOLIO_DB_PASSWORD" ""})"

          for i in $(seq 1 60); do
            if [ -n "$DB_HOST" ]; then
              if ${pkgs.mariadb}/bin/mysqladmin --protocol=tcp -h"$DB_HOST" -u"$DB_USER" --password="$DB_PASSWORD" ping >/dev/null 2>&1; then
                break
              fi
            else
              if ${pkgs.mariadb}/bin/mysqladmin --socket=/run/mysqld/mysqld.sock -u"$DB_USER" --password="$DB_PASSWORD" ping >/dev/null 2>&1; then
                break
              fi
            fi
            sleep 2
            if [ "$i" -eq 60 ]; then
              echo "Database did not become ready in time." >&2
              exit 1
            fi
          done

          MANAGE_PATH="$(${pkgs.findutils}/bin/find ${cfg.package}/lib -path '*/site-packages/ekiree_dashboard/manage.py' | head -n 1)"
          if [ -z "$MANAGE_PATH" ]; then
            echo "manage.py was not found in ${cfg.package}" >&2
            exit 1
          fi
          exec ${cfg.package}/bin/python "$MANAGE_PATH" migrate --noinput
        '';
      };

      systemd.services.${serviceName} = {
        description = "Gunicorn for ${serviceName}";
        after = [ "${migrateServiceName}.service" ];
        requires = [ "${migrateServiceName}.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = appUser;
          Group = appGroup;
          WorkingDirectory = "/var/lib/${appUser}";
          Restart = "on-failure";
          UMask = "0077";
          RuntimeDirectory = appUser;
          StateDirectory = appUser;
          CacheDirectory = appUser;
          PrivateTmp = true;
          NoNewPrivileges = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/var/lib/${appUser}" "/tmp" ];
        };
        environment = {
          DOCKER_SECRETS = if usesSopsSecrets then "True" else "False";
          POETFOLIO_PRODUCTION = if isProd then "True" else "False";
          POETFOLIO_DB_NAME = cfg.database.name;
          POETFOLIO_DB_USER = cfg.database.user;
          POETFOLIO_DB_HOST = cfg.database.host;
          POETFOLIO_MEDIA = "/var/lib/${appUser}/media";
          POETFOLIO_STATIC = "/var/lib/${appUser}/static";
          USE_S3 = if cfg.s3.enable then "TRUE" else "FALSE";
        };
        path = [ pkgs.findutils pkgs.coreutils pkgs.bash ];
        script = ''
          set -eu
          APP_ROOT="$(${pkgs.findutils}/bin/find ${cfg.package}/lib -path '*/site-packages/ekiree_dashboard/poetfolio' | head -n 1 | ${pkgs.coreutils}/bin/xargs -r dirname)"
          if [ -z "$APP_ROOT" ]; then
            echo "poetfolio package root was not found in ${cfg.package}" >&2
            exit 1
          fi
          cd "$APP_ROOT"
          exec ${cfg.package}/bin/gunicorn \
            --bind ${cfg.bindAddress}:${toString cfg.port} \
            --workers ${toString cfg.workers} \
            poetfolio.wsgi:application
        '';
      };
    }

    (lib.mkIf (cfg.dev.envFile != null) {
      systemd.services.${serviceName}.serviceConfig.EnvironmentFile = [ cfg.dev.envFile ];
      systemd.services.${migrateServiceName}.serviceConfig.EnvironmentFile = [ cfg.dev.envFile ];
    })

    (lib.mkIf (cfg.dev.envFile != null && cfg.database.createLocally) {
      systemd.services.${dbInitServiceName}.serviceConfig.EnvironmentFile = [ cfg.dev.envFile ];
    })

    (lib.mkIf nginxEnabled {
      services.nginx.enable = true;
      services.nginx.virtualHosts.${cfg.domain} = {
        locations."/" = {
          proxyPass = "http://${cfg.bindAddress}:${toString cfg.port}";
          recommendedProxySettings = true;
        };
        forceSSL = isProd;
        enableACME = isProd;
      };
    })

    (lib.mkIf (nginxEnabled && isProd) {
      security.acme.acceptTerms = true;
      security.acme.defaults.email = cfg.acmeEmail;
    })

    (lib.mkIf cfg.backup.enable {
      systemd.services.${backupServiceName} = {
        description = "Backup MariaDB database for ${serviceName}";
        serviceConfig = {
          Type = "oneshot";
          User = appUser;
          Group = appGroup;
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ cfg.backup.localDir "/tmp" ];
        };
        path = [ pkgs.mariadb pkgs.gzip pkgs.coreutils ] ++ lib.optional cfg.backup.s3.enable pkgs.awscli2;
        environment = {
          DOCKER_SECRETS = if usesSopsSecrets then "True" else "False";
          POETFOLIO_DB_NAME = cfg.database.name;
          POETFOLIO_DB_USER = cfg.database.user;
          POETFOLIO_DB_HOST = cfg.database.host;
        };
        script = ''
          set -eu
          mkdir -p ${cfg.backup.localDir}

          DB_HOST="$(${getSecretOrEnv "POETFOLIO_DB_HOST" cfg.database.host})"
          DB_NAME="$(${getSecretOrEnv "POETFOLIO_DB_NAME" cfg.database.name})"
          DB_USER="$(${getSecretOrEnv "POETFOLIO_DB_USER" cfg.database.user})"
          DB_PASSWORD="$(${getSecretOrEnv "POETFOLIO_DB_PASSWORD" ""})"
          TS="$(${pkgs.coreutils}/bin/date +%Y-%m-%dT%H-%M-%S)"
          OUT="${cfg.backup.localDir}/$DB_NAME-$TS.sql.gz"

          if [ -n "$DB_HOST" ]; then
            ${pkgs.mariadb}/bin/mariadb-dump --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" "$DB_NAME" | ${pkgs.gzip}/bin/gzip -9 > "$OUT"
          else
            ${pkgs.mariadb}/bin/mariadb-dump --socket=/run/mysqld/mysqld.sock --user="$DB_USER" --password="$DB_PASSWORD" "$DB_NAME" | ${pkgs.gzip}/bin/gzip -9 > "$OUT"
          fi

          ${lib.optionalString cfg.backup.s3.enable ''
            BUCKET="$(${getSecretOrEnv "BACKUP_BUCKET_NAME" ""})"
            ENDPOINT="$(${getSecretOrEnv "BACKUP_BUCKET_ENDPOINT" ""})"
            ACCESS="$(${getSecretOrEnv "BACKUP_ACCESS_KEY" ""})"
            SECRET="$(${getSecretOrEnv "BACKUP_SECRET_KEY" ""})"

            export AWS_ACCESS_KEY_ID="$ACCESS"
            export AWS_SECRET_ACCESS_KEY="$SECRET"
            ${pkgs.awscli2}/bin/aws --endpoint-url "$ENDPOINT" s3 cp "$OUT" "s3://$BUCKET/$(basename "$OUT")"
          ''}
        '';
      };

      systemd.timers.${backupTimerName} = {
        description = "Timer for ${backupServiceName}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.backup.schedule;
          Persistent = true;
          Unit = "${backupServiceName}.service";
        };
      };
    })

    (lib.mkIf (cfg.backup.enable && cfg.dev.envFile != null) {
      systemd.services.${backupServiceName}.serviceConfig.EnvironmentFile = [ cfg.dev.envFile ];
    })
  ]);
}
