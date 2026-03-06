# ekiree-dashboard infrastructure

Recommended public repository name: **`ekiree-dashboard-infra`**

This repository contains a NixOS module for running ekiree-dashboard in:

- `production` profile (nginx + ACME + sops-secrets)
- `development` profile (local-only, optional env file, no ACME)

## Quick start (development)

1. Copy the local env template:

   ```bash
   cp secrets/local-dev.env.example secrets/local-dev.env
   ```

2. Build the local development system:

   ```bash
   nix build .#nixosConfigurations.local-dev.config.system.build.toplevel
   ```

3. Run a VM test:

   ```bash
   nixos-rebuild build-vm --flake .#local-dev
   ```

## Production notes

- Copy the production template, then fill it:

  ```bash
  cp secrets/whittier.yaml.example secrets/whittier.yaml
  ```

- Encrypt `secrets/whittier.yaml` with `sops` before deployment.
- Ensure the host has the matching AGE private key for decryption.
- Build with:

  ```bash
  nix build .#nixosConfigurations.whittier.config.system.build.toplevel
  ```

## GitHub Actions Azure image build

Workflow: `.github/workflows/build-azure-image.yml`

- Trigger manually with **Actions → Build Azure NixOS Image → Run workflow**
- Select host (`whittier` or `local-dev`)
- Download the uploaded `azure-image-*` artifact from the workflow run
- Upload the resulting VHD artifact to Azure Storage, then create a custom image/VM from it

## Public repo secret hygiene

- Only `*.example` secret templates are committed.
- Real secret files under `secrets/*.yaml` and `secrets/*.env` are gitignored.
- Keep production secrets in a private system of record (private repo, secret manager, or offline vault).
