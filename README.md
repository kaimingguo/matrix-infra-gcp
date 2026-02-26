# matrix-infra-gcp

Terraform + Ansible infrastructure for deploying a self-hosted [Matrix Synapse](https://github.com/element-hq/synapse) homeserver on GCP with FreeBSD.

## Stack

- **Compute**: GCP e2-small instance running FreeBSD 15.0 with ZFS
- **Storage**: Separate persistent disk (pd-standard, 30 GB default) for PostgreSQL and Synapse data
- **Database**: PostgreSQL 17 on a ZFS dataset tuned for database workloads (recordsize=8k)
- **Reverse proxy**: Caddy (automatic TLS via Let's Encrypt)
- **DNS**: Cloudflare
- **Secrets**: GCP Secret Manager (DB password, Synapse keys)
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
                  │                                      │
                  │   ┌──────────────────────────────┐   │
                  │   │  pd-standard (data disk)     │   │
                  │   │  datapool/postgres            │   │
                  │   │  datapool/matrix-synapse      │   │
                  │   └──────────────────────────────┘   │
                  └──────────────────────────────────────┘
                        ▲
                        │ SSH via IAP tunnel (no public :22)
                        │
                  GCP Secret Manager
                  (DB password, Synapse secrets)
```

## Files

| File | Purpose |
|------|---------|
| `main.tf` | GCP resources, Cloudflare DNS, Secret Manager, Ansible provisioner |
| `variables.tf` | Input variables with defaults |
| `providers.tf` | Terraform provider configuration |
| `playbook.yml` | Ansible playbook — ZFS, PostgreSQL, Synapse, Caddy |
| `group_vars/all.yml.tftpl` | Ansible vars template (rendered by Terraform) |
| `ansible.cfg` | Ansible settings (FreeBSD tmpfile workaround) |

## License

[BSD-3-Clause](LICENSE)
