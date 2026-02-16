# matrix-infra

Terraform + Ansible infrastructure for deploying a self-hosted [Matrix Synapse](https://github.com/element-hq/synapse) homeserver on GCP with FreeBSD.

## Stack

- **Compute**: GCP e2-small instance running FreeBSD 15.0 with ZFS
- **Database**: PostgreSQL 17 on a ZFS dataset tuned for database workloads
- **Reverse proxy**: Caddy (automatic TLS via Let's Encrypt)
- **DNS**: Cloudflare
- **Provisioning**: Terraform creates infrastructure, Ansible configures the server

## Prerequisites

- [Terraform](https://www.terraform.io/) >= 1.0
- [Ansible](https://www.ansible.com/) with `community.general` and `community.postgresql` collections
- A GCP project with Compute Engine API enabled
- A Cloudflare-managed domain
- An SSH key pair

## Usage

1. Copy and fill in your variables:

   ```sh
   cp terraform.tfvars.example terraform.tfvars
   $EDITOR terraform.tfvars
   ```

2. Deploy:

   ```sh
   terraform init
   terraform apply
   ```

   Terraform provisions the GCP instance, sets up Cloudflare DNS records, and runs the Ansible playbook automatically.

3. Create an admin user:

   ```sh
   ssh freebsd@<server-ip>
   register_new_matrix_user -c /usr/local/etc/matrix-synapse/homeserver.yaml http://localhost:8008
   ```

4. Verify federation:

   ```sh
   curl https://matrix.example.com/.well-known/matrix/server
   ```

## Architecture

```
                  ┌──────────────────────────────────┐
                  │         GCP e2-small              │
                  │         FreeBSD 15.0              │
Internet ──▶ :443 ──▶ Caddy ──▶ :8008 Synapse       │
         ──▶ :8448 ──▶        (federation)           │
                  │                 │                 │
                  │            PostgreSQL 17          │
                  │          (ZFS recordsize=8k)      │
                  └──────────────────────────────────┘
```

## License

[BSD-3-Clause](LICENSE)
