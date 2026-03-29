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

output "ssh_command" {
  value       = "gcloud compute ssh ${var.ssh_user}@${google_compute_instance.matrix.name} --project=${var.gcp_project_id} --zone=${var.zone} --tunnel-through-iap"
  description = "SSH into the Matrix server via IAP"
}

output "create_admin_command" {
  value       = "gcloud compute ssh ${var.ssh_user}@${google_compute_instance.matrix.name} --project=${var.gcp_project_id} --zone=${var.zone} --tunnel-through-iap -- 'register_new_matrix_user -c /usr/local/etc/matrix-synapse/homeserver.yaml http://localhost:8008'"
  description = "Command to create admin user"
}
