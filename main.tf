# ============================================
# Data Sources
# ============================================
data "http" "my_ip" {
  url = "https://api4.ipify.org"
}

# ============================================
# Random Secrets
# ============================================
resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "random_password" "synapse_secrets" {
  count   = 3
  length  = 64
  special = false
}

locals {
  synapse_hostname = "${var.subdomain}.${var.domain_name}"
  secrets = {
    db_password                        = random_password.db_password.result
    synapse_registration_shared_secret = random_password.synapse_secrets[0].result
    synapse_macaroon_secret_key        = random_password.synapse_secrets[1].result
    synapse_form_secret                = random_password.synapse_secrets[2].result
  }
}

# ============================================
# GCP Networking
# ============================================
resource "google_compute_network" "matrix" {
  name                    = "matrix-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "matrix" {
  name          = "matrix-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.matrix.id
}

resource "google_compute_firewall" "matrix_ingress" {
  name    = "matrix-allow-ingress"
  network = google_compute_network.matrix.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8448"]
  }

  target_tags   = ["matrix-server"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "ssh" {
  name    = "matrix-allow-ssh"
  network = google_compute_network.matrix.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags   = ["matrix-server"]
  source_ranges = ["${chomp(data.http.my_ip.response_body)}/32"]
}

# ============================================
# GCP Compute
# ============================================
resource "google_compute_address" "matrix" {
  name   = "matrix-ip"
  region = var.region
}

resource "google_compute_disk" "matrix_data" {
  name = "matrix-data"
  type = "pd-standard"
  zone = var.zone
  size = var.data_disk_size
}

resource "google_service_account" "matrix" {
  account_id   = "matrix-synapse"
  display_name = "Matrix Synapse Service Account"
}

resource "google_compute_instance" "matrix" {
  name         = "matrix-synapse"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["matrix-server"]

  boot_disk {
    initialize_params {
      image = "freebsd-org-cloud-dev/freebsd-15-0-release-amd64-zfs"
      size  = 22
    }
  }

  attached_disk {
    source      = google_compute_disk.matrix_data.id
    device_name = "data-disk"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.matrix.id
    access_config {
      nat_ip = google_compute_address.matrix.address
    }
  }

  service_account {
    email  = google_service_account.matrix.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys  = "${var.ssh_user}:${file(var.ssh_pub_key)}"
    user-data = <<-EOT
      #cloud-config
      pkg_bootstrap: true
      packages:
        - python311
        - py311-packaging
        - bash
      runcmd:
        - ln -sf /usr/local/bin/python3.11 /usr/local/bin/python3
    EOT
    startup-script = <<-EOT
      #!/bin/sh
      # FreeBSD 15 ZFS image: sshd fails during boot due to a race condition.
      # Wait for boot to settle, then ensure sshd is running.
      sleep 30
      if ! service sshd status > /dev/null 2>&1; then
        logger -t startup-script "sshd not running after boot, restarting..."
        service sshd restart
      fi
      # Install Python if cloud-init didn't run
      if ! command -v python3 > /dev/null 2>&1; then
        pkg install -y python311 py311-packaging bash
        ln -sf /usr/local/bin/python3.11 /usr/local/bin/python3
      fi
    EOT
  }

  allow_stopping_for_update = true
}

# ============================================
# Cloudflare DNS
# ============================================
resource "cloudflare_dns_record" "matrix_subdomain" {
  zone_id = var.cloudflare_zone_id
  name    = var.subdomain
  ttl     = 3600
  type    = "A"
  content = google_compute_address.matrix.address
  proxied = false
}

# ============================================
# Ansible Configuration
# ============================================
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.yml"
  content  = <<-EOT
    all:
      hosts:
        matrix:
          ansible_host: ${google_compute_address.matrix.address}
          ansible_user: ${var.ssh_user}
          ansible_python_interpreter: /usr/local/bin/python3
  EOT
}

resource "local_file" "ansible_vars" {
  filename = "${path.module}/group_vars/all.yml"
  content = templatefile("${path.module}/group_vars/all.yml.tftpl", {
    server_ip                          = google_compute_address.matrix.address
    domain_name                        = var.domain_name
    subdomain                          = var.subdomain
    db_password                        = local.secrets.db_password
    synapse_registration_shared_secret = local.secrets.synapse_registration_shared_secret
    synapse_macaroon_secret_key        = local.secrets.synapse_macaroon_secret_key
    synapse_form_secret                = local.secrets.synapse_form_secret
    admin_email                        = var.admin_email
  })

  file_permission = "0600"
}

resource "local_sensitive_file" "secrets_backup" {
  filename        = "${path.module}/.secrets.json"
  content         = jsonencode(local.secrets)
  file_permission = "0600"
}

# ============================================
# Ansible Provisioning
# ============================================
resource "null_resource" "ansible_provision" {
  depends_on = [
    google_compute_instance.matrix,
    google_compute_firewall.ssh,
    cloudflare_dns_record.matrix_subdomain,
    local_file.ansible_inventory,
    local_file.ansible_vars,
  ]

  triggers = {
    playbook_hash = filemd5("${path.module}/playbook.yml")
    vars_hash     = sha256(local_file.ansible_vars.content)
    instance_id   = google_compute_instance.matrix.instance_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for SSH to become available..."
      for i in $(seq 1 30); do
        if ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=5 -o BatchMode=yes \
          -i ${var.ssh_private_key} ${var.ssh_user}@${google_compute_address.matrix.address} 'echo ready' 2>/dev/null; then
          echo "SSH is ready after ~$((i * 10)) seconds"
          break
        fi
        if [ "$i" -eq 30 ]; then
          echo "ERROR: SSH not available after 5 minutes"
          exit 1
        fi
        echo "  Attempt $i/30 - retrying in 10s..."
        sleep 10
      done

      ansible-playbook \
        -i inventory.yml \
        --private-key ${var.ssh_private_key} \
        --ssh-extra-args='-o StrictHostKeyChecking=no -o IdentitiesOnly=yes' \
        playbook.yml
    EOT

    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_FORCE_COLOR       = "True"
    }
  }
}

# ============================================
# Outputs
# ============================================
output "matrix_ip" {
  value       = google_compute_address.matrix.address
  description = "Matrix server public IP"
}

output "matrix_url" {
  value       = "https://${local.synapse_hostname}"
  description = "Matrix Synapse URL"
}

output "user_id_format" {
  value       = "@user:${var.domain_name}"
  description = "Matrix user ID format"
}

output "nginx_well_known_config" {
  value       = <<-EOT
    # Add to nginx server block for ${var.domain_name}
    location /.well-known/matrix/server {
        default_type application/json;
        return 200 '{"m.server":"${local.synapse_hostname}:443"}';
    }

    location /.well-known/matrix/client {
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
        return 200 '{"m.homeserver":{"base_url":"https://${local.synapse_hostname}"}}';
    }
  EOT
  description = "Nginx config for .well-known Matrix delegation on the root domain"
}

output "federation_test" {
  value       = "curl https://${local.synapse_hostname}/.well-known/matrix/server"
  description = "Command to test federation"
}

output "create_admin_command" {
  value       = "ssh ${var.ssh_user}@${google_compute_address.matrix.address} 'register_new_matrix_user -c /usr/local/etc/matrix-synapse/homeserver.yaml http://localhost:8008'"
  description = "Command to create admin user"
}
