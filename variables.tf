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
  default     = 15
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

variable "backup_gcs_retention_days" {
  description = "Number of days to retain backups in GCS"
  type        = number
  default     = 30
}

# ============================================
# Telegram Bridge
# ============================================
variable "telegram_api_id" {
  description = "Telegram API ID from https://my.telegram.org"
  type        = string
  sensitive   = true
}

variable "telegram_api_hash" {
  description = "Telegram API hash from https://my.telegram.org"
  type        = string
  sensitive   = true
}

variable "telegram_bot_token" {
  description = "Telegram bot token from @BotFather"
  type        = string
  sensitive   = true
  default     = ""
}
