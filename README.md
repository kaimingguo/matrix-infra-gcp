# matrix-infra-gcp

Terraform + Ansible infrastructure for deploying a self-hosted [Matrix Synapse](https://github.com/element-hq/synapse) homeserver on GCP with FreeBSD.

## Stack

- **Compute**: GCP e2-small instance running FreeBSD 15.0 with ZFS
- **Storage**: Separate persistent disk (pd-standard, 30 GB default) for PostgreSQL and Synapse data
- **Database**: PostgreSQL 17 on a ZFS dataset tuned for database workloads (recordsize=8k)
- **Reverse proxy**: Caddy (automatic TLS via Let's Encrypt)
- **DNS**: Cloudflare
- **Secrets**: GCP Secret Manager (DB password, Synapse keys)
- **Backup**: Daily PostgreSQL dumps to GCS with automatic lifecycle cleanup
- **SSH access**: GCP Identity-Aware Proxy (IAP) tunneling — no public SSH port
- **Provisioning**: Terraform creates infrastructure, Ansible configures the server

## Prerequisites

- [Terraform](https://www.terraform.io/) >= 1.0
- [Ansible](https://www.ansible.com/) with `community.general` and `community.postgresql` collections
- [Google Cloud SDK](https://cloud.google.com/sdk) (`gcloud`) — used for IAP tunneling and secret access
- A GCP project with Compute Engine, IAP, and Secret Manager APIs enabled
- A Cloudflare-managed domain
- An SSH key pair (Ed25519 by default)

## Usage

1. Copy and fill in your variables:

   ```sh
   cp terraform.tfvars.example terraform.tfvars
   $EDITOR terraform.tfvars
   ```

   Required variables: `gcp_project_id`, `domain_name`, `admin_email`, `cloudflare_api_token`, `cloudflare_zone_id`. See `variables.tf` for all options and defaults.

2. Deploy:

   ```sh
   terraform init
   terraform apply
   ```

   Terraform provisions the GCP instance, sets up Cloudflare DNS, stores secrets in Secret Manager, and runs the Ansible playbook automatically via IAP tunnel.

3. Create an admin user:

   ```sh
   # SSH via IAP (shown in terraform output "ssh_command")
   gcloud compute ssh freebsd@matrix-synapse \
     --project=<project-id> --zone=<zone> --tunnel-through-iap

   register_new_matrix_user -c /usr/local/etc/matrix-synapse/homeserver.yaml http://localhost:8008
   ```

4. Verify federation:

   ```sh
   curl https://matrix.example.com/.well-known/matrix/server
   ```

## Architecture

```
                  ┌──────────────────────────────────────┐
                  │          GCP e2-small                 │
                  │          FreeBSD 15.0                 │
Internet ──▶ :443 ──▶ Caddy ──▶ :8008 Synapse           │
         ──▶ :8448 ──▶        (federation)               │
                  │                 │                     │
                  │            PostgreSQL 17              │
                  │          (ZFS recordsize=8k)          │
                  │                 │                     │
                  │   ┌──────────────────────────────┐   │
                  │   │  pd-standard (data disk)     │   │
                  │   │  datapool/postgres            │   │
                  │   │  datapool/matrix-synapse      │   │
                  │   └──────────────────────────────┘   │
                  └──────────────┬───────────────────────┘
                        ▲       │
                        │       │ Daily pg_dump (03:00 UTC)
                        │       ▼
                  GCP Secret   GCS Bucket
                  Manager      (30-day lifecycle)
```

## Backup

A daily cron job at 03:00 UTC dumps the PostgreSQL database and uploads it to a GCS bucket.

- **Format**: `pg_dump -Fc` (compressed custom format, supports `pg_restore`)
- **GCS bucket**: `matrix-backups-<project-id>` with a 30-day lifecycle rule (configurable via `backup_gcs_retention_days`)
- **Local retention**: 7 days in `/var/backups/postgres/`
- **Auth**: GCP instance metadata server — no SDK or credentials file needed
- **Log**: `/var/log/backup-postgres.log`

Run manually:

```sh
/usr/local/bin/backup-postgres.sh
```

Restore from a backup:

```sh
# List available backups
gcloud storage ls gs://matrix-backups-<project-id>/

# Download
gcloud storage cp gs://matrix-backups-<project-id>/synapse-20260226-030000.dump .

# Restore (drop + recreate)
pg_restore -U postgres -d synapse -c synapse-20260226-030000.dump
```

## Files

| File | Purpose |
|------|---------|
| `main.tf` | GCP resources, Cloudflare DNS, Secret Manager, GCS backup bucket, Ansible provisioner |
| `variables.tf` | Input variables with defaults |
| `providers.tf` | Terraform provider configuration |
| `playbook.yml` | Ansible playbook — ZFS, PostgreSQL, Synapse, Caddy, backup cron |
| `group_vars/all.yml.tftpl` | Ansible vars template (rendered by Terraform) |
| `scripts/backup-postgres.sh` | PostgreSQL backup script (deployed to server by Ansible) |
| `ansible.cfg` | Ansible settings (FreeBSD tmpfile workaround) |

## License

[BSD-3-Clause](LICENSE)
