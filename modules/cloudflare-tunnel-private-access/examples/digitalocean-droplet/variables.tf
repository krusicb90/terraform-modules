variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "ID of the Cloudflare zone for the domain."
  type        = string
}

variable "cloudflare_team_name" {
  description = "Zero Trust team name: the first part of <team>.cloudflareaccess.com."
  type        = string
}

variable "domain" {
  description = "Domain of the zone, for example example.com."
  type        = string
}

variable "allowed_emails" {
  description = "Email addresses that may reach the application and SSH."
  type        = list(string)
}

variable "region" {
  description = "DigitalOcean region."
  type        = string
  default     = "fra1"
}

variable "ssh_key_fingerprints" {
  description = "Fingerprints of the DigitalOcean SSH keys to install on the droplet."
  type        = list(string)
}
