# ============================================
# GCP APIs
# ============================================
resource "google_project_service" "iap" {
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
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

resource "random_password" "mautrix_telegram_db_password" {
  length  = 32
  special = false
}

resource "random_password" "mautrix_telegram_as_token" {
  length  = 64
  special = false
}

resource "random_password" "mautrix_telegram_hs_token" {
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
    mautrix_telegram_db_password       = random_password.mautrix_telegram_db_password.result
    mautrix_telegram_as_token          = random_password.mautrix_telegram_as_token.result
    mautrix_telegram_hs_token          = random_password.mautrix_telegram_hs_token.result
    telegram_api_id                    = coalesce(var.telegram_api_id, "PLACEHOLDER")
    telegram_api_hash                  = coalesce(var.telegram_api_hash, "PLACEHOLDER")
    telegram_bot_token                 = coalesce(var.telegram_bot_token, "PLACEHOLDER")
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

resource "google_compute_firewall" "ssh_iap" {
  name    = "matrix-allow-ssh-iap"
  network = google_compute_network.matrix.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags   = ["matrix-server"]
  source_ranges = ["35.235.240.0/20"] # GCP IAP TCP forwarding range
}

# ============================================
# IAP Access
# ============================================
resource "google_project_iam_member" "iap_tunnel_user" {
  project = var.gcp_project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.matrix.email}"
}

resource "google_project_iam_member" "iap_tunnel_self" {
  project = var.gcp_project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "user:${var.admin_email}"
}

# ============================================
# GCP Compute
# ============================================
resource "google_compute_address" "matrix" {
  name         = "matrix-ip"
  region       = var.region
  network_tier = var.network_tier
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
      nat_ip       = google_compute_address.matrix.address
      network_tier = var.network_tier
    }
  }

  service_account {
    email  = google_service_account.matrix.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${file(var.ssh_pub_key)}"
    user-data      = <<-EOT
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
# GCS Backup Bucket
# ============================================
resource "google_storage_bucket" "backups" {
  name          = "matrix-backups-${var.gcp_project_id}"
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = var.backup_gcs_retention_days
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.matrix.email}"
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
          ansible_host: ${google_compute_instance.matrix.name}
          ansible_user: ${var.ssh_user}
          ansible_python_interpreter: /usr/local/bin/python3
          ansible_ssh_common_args: >-
            -o StrictHostKeyChecking=no
            -o IdentitiesOnly=yes
            -o ProxyCommand="gcloud compute start-iap-tunnel %h %p
            --listen-on-stdin
            --project=${var.gcp_project_id}
            --zone=${var.zone}"
  EOT
}

resource "local_file" "ansible_vars" {
  filename = "${path.module}/group_vars/all.yml"
  content = templatefile("${path.module}/group_vars/all.yml.tftpl", {
    server_ip              = google_compute_address.matrix.address
    gcp_project_id         = var.gcp_project_id
    domain_name            = var.domain_name
    subdomain              = var.subdomain
    admin_email            = var.admin_email
    backup_bucket          = google_storage_bucket.backups.name
    enable_telegram_bridge = true
  })

  file_permission = "0600"
}

# ============================================
# GCP Secret Manager
# ============================================
resource "google_secret_manager_secret" "matrix" {
  for_each  = local.secrets
  secret_id = "matrix-${replace(each.key, "_", "-")}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "matrix" {
  for_each    = local.secrets
  secret      = google_secret_manager_secret.matrix[each.key].id
  secret_data = each.value
}

resource "google_secret_manager_secret_iam_member" "matrix_accessor" {
  for_each  = local.secrets
  secret_id = google_secret_manager_secret.matrix[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.matrix.email}"
}

# ============================================
# Ansible Provisioning
# ============================================
resource "null_resource" "ansible_provision" {
  depends_on = [
    google_compute_instance.matrix,
    google_compute_firewall.ssh_iap,
    google_project_service.iap,
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
      echo "Waiting for SSH via IAP to become available..."
      for i in $(seq 1 30); do
        if gcloud compute ssh ${var.ssh_user}@${google_compute_instance.matrix.name} \
          --project=${var.gcp_project_id} \
          --zone=${var.zone} \
          --tunnel-through-iap \
          --ssh-key-file=${var.ssh_private_key} \
          --strict-host-key-checking=no \
          --command='echo ready' 2>/dev/null; then
          echo "SSH via IAP is ready after ~$((i * 10)) seconds"
          break
        fi
        if [ "$i" -eq 30 ]; then
          echo "ERROR: SSH via IAP not available after 5 minutes"
          exit 1
        fi
        echo "  Attempt $i/30 - retrying in 10s..."
        sleep 10
      done

      ansible-playbook \
        -i inventory.yml \
        --private-key ${var.ssh_private_key} \
        playbook.yml
    EOT

    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_FORCE_COLOR       = "True"
      PATH                      = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
    }
  }
}
