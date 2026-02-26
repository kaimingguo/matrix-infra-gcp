# variables.tf
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "GCP machine type"
  type        = string
  default     = "e2-small"
}

variable "data_disk_size" {
  description = "Data disk size in GB"
  type        = number
  default     = 30
}

variable "network_tier" {
  description = "GCP network tier"
  type        = string
  default     = "PREMIUM"
}

variable "domain_name" {
  description = "Root domain name (e.g., example.com)"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for Matrix service"
  type        = string
  default     = "matrix"
}

variable "admin_email" {
  description = "Admin email for Let's Encrypt and IAP access"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "ssh_user" {
  description = "SSH user"
  type        = string
  default     = "freebsd"
}

variable "ssh_pub_key" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/id_ed25519"
}
